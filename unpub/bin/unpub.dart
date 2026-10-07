import 'dart:io';

import 'package:args/args.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:unpub/src/mongo_store.dart';
import 'package:unpub/unpub.dart' as unpub;
import 'package:unpub_aws/core/aws_s3_worker.dart';
import 'package:unpub_aws/core/aws_web_identity.dart';
import 'package:unpub_aws/core/credentials_source.dart';
import 'package:unpub_aws/core/refreshing_credentials.dart';
import 'package:unpub_aws/core/web_identity_token.dart';
import 'package:unpub_aws/package_store/s3_sts_file_store.dart';

main(List<String> arguments) async {
  final environment = Platform.environment;
  ArgResults args = _parseArgs(arguments, environment);
  final host = args['host'] as String;
  final port = int.parse(args['port'] as String);
  final dbUri = args['database'] as String;
  final proxyOrigin = args['proxy-origin'] as String;
  final exitOnDbError = (args['exitOnDbError'] as String?) == 'true';
  final roleArn = args['roleArn'] as String?;
  final roleSessionName = args['roleSessionName'] as String?;
  final webIdentityToken = args['webIdentityToken'] as String?;
  final webIdentityTokenFile = args['webIdentityTokenFile'] as String?;
  final bucketName = args['bucketName'] as String?;
  final region = args['region'] as String?;
  final tlsCAFile = args['tlsCAFile'] as String?;
  final tlsCertificateKeyFile = args['tlsCertificateKeyFile'] as String?;
  final tlsCertificateKeyFilePassword = args['tlsCertificateKeyFilePassword'] as String?;

  final mongoDbStore = await _createAndInitMongoDbStore(
    dbUri,
    exitOnDbError,
    tlsCAFile: tlsCAFile,
    tlsCertificateKeyFile: tlsCertificateKeyFile,
    tlsCertificateKeyFilePassword: tlsCertificateKeyFilePassword,
  );
  final awsStore = await _createAndInitS3Store(
    roleArn: roleArn,
    roleSessionName: roleSessionName,
    webIdentityToken: webIdentityToken,
    webIdentityTokenFile: webIdentityTokenFile,
    region: region,
    bucketName: bucketName,
  );

  final app = unpub.App(
    metaStore: mongoDbStore,
    packageStore: awsStore,
    proxy_origin: proxyOrigin.trim().isEmpty ? null : Uri.parse(proxyOrigin),
  );
  final server = await app.serve(host, port);
  print('Serving at http://${server.address.host}:${server.port}');

  // As a container's PID 1 the server gets no default handling of SIGTERM,
  // so without this Kubernetes waits out the grace period and kills it.
  await ProcessSignal.sigterm.watch().first;
  print('SIGTERM received, closing the server');
  await Future.any([server.close(), Future.delayed(const Duration(seconds: 10))]);
  exit(0);
}

Future<unpub.MetaStore> _createAndInitMongoDbStore(
  String dbUri,
  bool exitOnDbError, {
  String? tlsCAFile,
  String? tlsCertificateKeyFile,
  String? tlsCertificateKeyFilePassword,
}) async {
  String modifiedUri = dbUri;
  final uri = Uri.parse(dbUri);
  if (!uri.queryParameters.containsKey('authMechanism')) {
    final queryParams = Map<String, String>.from(uri.queryParameters);
    queryParams['authMechanism'] = 'SCRAM-SHA-1';
    modifiedUri = uri.replace(queryParameters: queryParams).toString();
  }
  final db = Db(modifiedUri);

  final transport = switch (tlsCAFile) {
    null || '' => const unpub.PlainTransport(),
    final caFile => unpub.TlsTransport(
      caFile: caFile,
      certificateKeyFile: switch (tlsCertificateKeyFile) {
        null || '' => null,
        final file => file,
      },
      certificateKeyFilePassword: switch (tlsCertificateKeyFilePassword) {
        null || '' => null,
        final password => password,
      },
    ),
  };
  print(switch (transport) {
    unpub.PlainTransport() => 'Connecting to database using not secure connection',
    unpub.TlsTransport(:final caFile) => 'Connecting to database using CA file from path: $caFile',
  });
  final connection = unpub.DbConnection(db: db, transport: transport);
  await connection.open();

  final mongoStore = MongoStore(
    db,
    onDatabaseError: exitOnDbError
        ? (error) {
            print('Database error: $error Exiting...');
            exit(1);
          }
        : null,
  );
  try {
    await mongoStore.createIndexes();
  } catch (e) {
    // E.g. two documents with the same package name, from before the index.
    print('Could not create the database indexes, serving without them: $e');
  }

  return unpub.ReconnectingMetaStore(store: mongoStore, connection: connection);
}

ArgResults _parseArgs(List<String> args, Map<String, dynamic> environment) {
  final parser = ArgParser();
  parser.addOption('host', abbr: 'h', defaultsTo: '0.0.0.0');
  parser.addOption('port', abbr: 'p', defaultsTo: '4000');
  parser.addOption('database', abbr: 'd', defaultsTo: 'mongodb://localhost:27017/dart_pub');
  parser.addOption('proxy-origin', abbr: 'o', defaultsTo: '');
  parser.addOption('exitOnDbError', abbr: 'e', defaultsTo: 'false');
  parser.addOption('roleArn', defaultsTo: environment['AWS_ROLE_ARN']);
  parser.addOption('roleSessionName', defaultsTo: 'unpubConnection');
  parser.addOption('webIdentityToken', defaultsTo: environment['AWS_WEB_IDENTITY_TOKEN']);
  parser.addOption('webIdentityTokenFile', defaultsTo: environment['AWS_WEB_IDENTITY_TOKEN_FILE']);
  parser.addOption('bucketName', defaultsTo: environment['AWS_BUCKET_NAME']);
  parser.addOption('region', defaultsTo: environment['AWS_REGION']);
  parser.addOption('tlsCAFile');
  parser.addOption('tlsCertificateKeyFile');
  parser.addOption('tlsCertificateKeyFilePassword');

  final arguments = parser.parse(args);
  if (arguments.rest.isNotEmpty) {
    print('Got unexpected arguments: "${arguments.rest.join(' ')}".\n\nUsage:\n');
    print(parser.usage);
    exit(1);
  }
  return arguments;
}

Future<S3StoreIamStore> _createAndInitS3Store({
  required String? roleArn,
  required String? roleSessionName,
  required String? webIdentityToken,
  required String? webIdentityTokenFile,
  required String? region,
  required String? bucketName,
}) async {
  final awsWebIdentity = AwsWebIdentity(
    roleArn: switch (roleArn) {
      null || '' => throw ArgumentError('Pass --roleArn or set AWS_ROLE_ARN to the role to assume.'),
      final roleArn => roleArn,
    },
    roleSessionName: switch (roleSessionName) {
      null || '' => throw ArgumentError('--roleSessionName cannot be empty.'),
      final roleSessionName => roleSessionName,
    },
    token: switch ((webIdentityToken, webIdentityTokenFile)) {
      (final String token, _) when token.isNotEmpty => InlineWebIdentityToken(token),
      (_, final String path) when path.isNotEmpty => FileWebIdentityToken(File(path)),
      _ => throw ArgumentError(
        'Pass --webIdentityTokenFile or --webIdentityToken, or set '
        'AWS_WEB_IDENTITY_TOKEN_FILE or AWS_WEB_IDENTITY_TOKEN.',
      ),
    },
  );
  final awsRegion = switch (region) {
    null || '' => 'eu-west-1',
    final region => region,
  };
  final awsBucket = switch (bucketName) {
    null || '' => throw ArgumentError('Pass --bucketName or set AWS_BUCKET_NAME to the bucket for package archives.'),
    final bucketName => bucketName,
  };

  final source = StsWebIdentityCredentialsSource.inRegion(region: awsRegion, webIdentity: awsWebIdentity);
  switch (await source.fetch()) {
    case CredentialsRefused(:final reason):
      throw StateError('Could not get AWS credentials from STS: $reason');
    case CredentialsFetched(:final credentials):
      final refreshingCredentials = RefreshingCredentials(
        source: source,
        current: credentials,
        refreshMargin: const Duration(minutes: 5),
        retryDelay: const Duration(seconds: 30),
      );
      refreshingCredentials.keepFresh();
      return S3StoreIamStore(
        s3: AwsS3Worker.inRegion(region: awsRegion, bucket: awsBucket),
        credentials: refreshingCredentials,
      );
  }
}
