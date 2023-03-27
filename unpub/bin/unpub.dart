import 'dart:io';

import 'package:args/args.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:unpub/src/mongo_store.dart';
import 'package:unpub/unpub.dart' as unpub;
import 'package:unpub_aws/core/aws_web_identity.dart';
import 'package:unpub_aws/package_store/s3_sts_file_store.dart';

main(List<String> arguments) async {
  final environment = Platform.environment;
  ArgResults args = _parseArgs(arguments);
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

  final mongoDbStore = await _createAndInitMongoDbStore(dbUri, exitOnDbError);
  final awsStore = await _createAndInitS3Store(
    roleArn: roleArn,
    roleSessionName: roleSessionName,
    webIdentityToken: webIdentityToken,
    webIdentityTokenFile: webIdentityTokenFile,
    environment: environment,
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
}

Future<MongoStore> _createAndInitMongoDbStore(String dbUri, bool exitOnDbError) async {
  final mongoDbStore = MongoStore(
    Db(dbUri),
    onDatabaseError: exitOnDbError
        ? (error) {
            print('Database error: $error Exiting...');
            exit(1);
          }
        : null,
  );
  await mongoDbStore.db.open(
    secure: true,
    tlsAllowInvalidCertificates: true,
  );
  return mongoDbStore;
}

ArgResults _parseArgs(List<String> args) {
  final parser = ArgParser();
  parser.addOption('host', abbr: 'h', defaultsTo: '0.0.0.0');
  parser.addOption('port', abbr: 'p', defaultsTo: '4000');
  parser.addOption('database', abbr: 'd', defaultsTo: 'mongodb://localhost:27017/dart_pub');
  parser.addOption('proxy-origin', abbr: 'o', defaultsTo: '');
  parser.addOption('exitOnDbError', abbr: 'e', defaultsTo: 'false');
  parser.addOption('roleArn', defaultsTo: '');
  parser.addOption('roleSessionName', defaultsTo: '');
  parser.addOption('webIdentityToken', defaultsTo: '');
  parser.addOption('webIdentityTokenFile', defaultsTo: '');
  parser.addOption('bucketName', defaultsTo: '');
  parser.addOption('region', defaultsTo: '');
  parser.addOption('dynamoDbUrl', defaultsTo: '');
  parser.addOption('dynamoDbTableName', defaultsTo: '');

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
  required Map<String, String> environment,
  required String? region,
  required String? bucketName,
}) async {
  late AwsWebIdentity awsWebIdentity;
  if (roleArn?.isNotEmpty == true &&
      roleSessionName?.isNotEmpty == true &&
      webIdentityToken?.isNotEmpty == true) {
    awsWebIdentity = AwsWebIdentity(
      roleArn: roleArn!,
      roleSessionName: roleSessionName!,
      webIdentityToken: webIdentityToken!,
    );
  } else if (webIdentityTokenFile?.isNotEmpty == true ||
      environment['AWS_WEB_IDENTITY_TOKEN_FILE']?.isNotEmpty == true) {
    awsWebIdentity = await AwsWebIdentity.fromEnvFile(
      env: environment,
      path: webIdentityTokenFile,
      roleSessionName: roleSessionName,
      roleArn: roleArn,
    );
  } else {
    awsWebIdentity = AwsWebIdentity.fromEnv(environment);
  }

  final s3storeIamStore = S3StoreIamStore(
    webIdentity: awsWebIdentity,
    region: region,
    bucketName: bucketName,
  );
  await s3storeIamStore.init();

  return s3storeIamStore;
}
