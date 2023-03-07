import 'dart:io';

import 'package:args/args.dart';
import 'package:unpub/unpub.dart' as unpub;
import 'package:unpub/unpub.dart';
import 'package:unpub_aws/core/aws_web_identity.dart';
import 'package:unpub_aws/meta_store/dynamodb_meta_store.dart';
import 'package:unpub_aws/package_store/s3_sts_file_store.dart';

main(List<String> args) async {
  print('${DateTime.now()} App start');
  var parser = ArgParser();
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

  var results = parser.parse(args);

  var host = results['host'] as String;
  var port = int.parse(results['port'] as String);
  var dbUri = results['database'] as String;
  var proxyOrigin = results['proxy-origin'] as String;
  var exitOnDbError = (results['exitOnDbError'] as String?) == 'true';
  var roleArn = results['roleArn'] as String?;
  var roleSessionName = results['roleSessionName'] as String?;
  var webIdentityToken = results['webIdentityToken'] as String?;
  var webIdentityTokenFile = results['webIdentityTokenFile'] as String?;
  var bucketName = results['bucketName'] as String?;
  var region = results['region'] as String?;
  var dynamoDbUrl = results['dynamoDbUrl'] as String?;
  var dynamoDbTableName = results['dynamoDbTableName'] as String?;

  if (results.rest.isNotEmpty) {
    print('Got unexpected arguments: "${results.rest.join(' ')}".\n\nUsage:\n');
    print(parser.usage);
    exit(1);
  }

  final environment = Platform.environment;

  // DEBUG PRINTS
  print('env variables:');
  var awsWebIdentitityTokenFileFromEnv = environment['AWS_WEB_IDENTITY_TOKEN_FILE'];
  var awsRoleArnFromEnv = environment['AWS_ROLE_ARN'];
  var awsRoleSessionNameEnv = environment['AWS_ROLE_SESSION_NAME'];
  var awsWebIdentitityTokenFromEnv = environment['AWS_WEB_IDENTITY_TOKEN'];
  print('AWS_WEB_IDENTITY_TOKEN_FILE: $awsWebIdentitityTokenFileFromEnv');
  print('AWS_ROLE_ARN: $awsRoleArnFromEnv');
  print('AWS_ROLE_SESSION_NAME: $awsRoleSessionNameEnv');
  print('AWS_WEB_IDENTITY_TOKEN: $awsWebIdentitityTokenFromEnv');
  print('---');

  print('args variables:');
  print('host: $host');
  print('port: $port');
  print('dbUri: $dbUri');
  print('proxyOrigin: $proxyOrigin');
  print('exitOnDbError: $exitOnDbError');
  print('roleArn: $roleArn');
  print('roleSessionName: $roleSessionName');
  print('webIdentityToken: $webIdentityToken');
  print('webIdentityTokenFile: $webIdentityTokenFile');
  print('bucketName: $bucketName');
  print('region: $region');
  print('dynamoDbUrl: $dynamoDbUrl');
  print('dynamoDbTableName: $dynamoDbTableName');
  print('---');
  // end of DEBUG PRINTS

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
  print('Log (app): created aws web identity: ${awsWebIdentity.roleArn}');

  print('Log (app): before db open');
  final dynamodbStore = DynamoDBMetaStore(endpointUrl: dynamoDbUrl!, tableName: dynamoDbTableName);
  print('Log (app): created DynamoDB store');

  print('Log (app): adding test version');
  await dynamodbStore.addVersion(
    'test',
    UnpubVersion('version', {}, 'pubspecYaml', 'uploader', 'readme', 'changelog', DateTime.now()),
  );
  print('Log (app): added test version to meta store');
  final packages = await dynamodbStore.queryPackages(size: 10, page: 0, sort: '');
  print('Log (app): packages: $packages');
  final s3storeIamStore = S3StoreIamStore(
    webIdentity: awsWebIdentity,
    region: region,
    bucketName: bucketName,
  );
  print('Log (app): created s3 store');

  var app = unpub.App(
    metaStore: dynamodbStore,
    packageStore: s3storeIamStore,
    proxy_origin: proxyOrigin.trim().isEmpty ? null : Uri.parse(proxyOrigin),
  );
  print('Log (app): created app');

  await s3storeIamStore.init();
  print('Log (app): initialized s3 store');

  print('Log (app): serving server...');
  var server = await app.serve(host, port);
  print('Serving at http://${server.address.host}:${server.port}');
}
