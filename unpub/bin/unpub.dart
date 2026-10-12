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
  final args = _parseArgs(arguments, Platform.environment);
  final host = args['host'] as String;
  final port = int.parse(args['port'] as String);
  final proxyOrigin = args['proxy-origin'] as String;

  // Every option is checked before anything is connected, so a missing one is
  // reported at once instead of after connecting to the database and to STS.
  final databaseUri = _databaseUri(args['database'] as String);
  final transport = _transport(
    caFile: args['tlsCAFile'] as String?,
    certificateKeyFile: args['tlsCertificateKeyFile'] as String?,
    certificateKeyFilePassword: args['tlsCertificateKeyFilePassword'] as String?,
  );
  final webIdentity = _webIdentity(
    roleArn: args['roleArn'] as String?,
    roleSessionName: args['roleSessionName'] as String?,
    webIdentityToken: args['webIdentityToken'] as String?,
    webIdentityTokenFile: args['webIdentityTokenFile'] as String?,
  );
  final region = switch (args['region'] as String?) {
    null || '' => 'eu-west-1',
    final region => region,
  };
  final bucket = switch (args['bucketName'] as String?) {
    null || '' => throw ArgumentError('Pass --bucketName or set AWS_BUCKET_NAME to the bucket for package archives.'),
    final bucket => bucket,
  };

  final metaStore = await _connectMetaStore(databaseUri, transport);
  final packageStore = await _connectPackageStore(webIdentity, region: region, bucket: bucket);

  final app = unpub.App(
    metaStore: metaStore,
    packageStore: packageStore,
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

/// Amazon DocumentDB only authenticates with SCRAM-SHA-1, so that is the
/// mechanism unless the URI names one.
String _databaseUri(String uri) {
  final parsed = Uri.parse(uri);
  if (parsed.queryParameters.containsKey('authMechanism')) return uri;
  return parsed.replace(queryParameters: {...parsed.queryParameters, 'authMechanism': 'SCRAM-SHA-1'}).toString();
}

unpub.MongoTransport _transport({
  required String? caFile,
  required String? certificateKeyFile,
  required String? certificateKeyFilePassword,
}) => switch (caFile) {
  null || '' => const unpub.PlainTransport(),
  final caFile => unpub.TlsTransport(
    caFile: caFile,
    certificateKeyFile: switch (certificateKeyFile) {
      null || '' => null,
      final file => file,
    },
    certificateKeyFilePassword: switch (certificateKeyFilePassword) {
      null || '' => null,
      final password => password,
    },
  ),
};

AwsWebIdentity _webIdentity({
  required String? roleArn,
  required String? roleSessionName,
  required String? webIdentityToken,
  required String? webIdentityTokenFile,
}) => AwsWebIdentity(
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

Future<unpub.MetaStore> _connectMetaStore(String uri, unpub.MongoTransport transport) async {
  final db = Db(uri);
  print(switch (transport) {
    unpub.PlainTransport() => 'Connecting to database using not secure connection',
    unpub.TlsTransport(:final caFile) => 'Connecting to database using CA file from path: $caFile',
  });
  final connection = unpub.DbConnection(db: db, transport: transport);
  await connection.open();

  final mongoStore = MongoStore(db);
  try {
    await mongoStore.createIndexes();
  } catch (e) {
    // E.g. two documents with the same package name, from before the index.
    print('Could not create the database indexes, serving without them: $e');
  }

  return unpub.ReconnectingMetaStore(store: mongoStore, connection: connection);
}

Future<S3StoreIamStore> _connectPackageStore(
  AwsWebIdentity webIdentity, {
  required String region,
  required String bucket,
}) async {
  final source = StsWebIdentityCredentialsSource.inRegion(region: region, webIdentity: webIdentity);
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
        s3: AwsS3Worker.inRegion(region: region, bucket: bucket),
        credentials: refreshingCredentials,
      );
  }
}

ArgResults _parseArgs(List<String> args, Map<String, dynamic> environment) {
  final parser = ArgParser();
  parser.addOption('host', abbr: 'h', defaultsTo: '0.0.0.0');
  parser.addOption('port', abbr: 'p', defaultsTo: '4000');
  parser.addOption('database', abbr: 'd', defaultsTo: 'mongodb://localhost:27017/dart_pub');
  parser.addOption('proxy-origin', abbr: 'o', defaultsTo: '');
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
