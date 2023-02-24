import 'dart:io';

import 'package:args/args.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:unpub/unpub.dart' as unpub;
import 'package:unpub_aws/core/aws_web_identity.dart';
import 'package:unpub_aws/s3/s3_sts_file_store.dart' as s3;

main(List<String> args) async {
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

  if (results.rest.isNotEmpty) {
    print('Got unexpected arguments: "${results.rest.join(' ')}".\n\nUsage:\n');
    print(parser.usage);
    exit(1);
  }

  final environment = Platform.environment;
  final db = Db(dbUri);
  await db.open();

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

  final s3storeIamStore = s3.S3StoreIamStore(
    webIdentity: awsWebIdentity,
    region: region,
    bucketName: bucketName,
  );

  var app = unpub.App(
      metaStore: unpub.MongoStore(db, onDatabaseError: exitOnDbError ? () => exit(1) : null),
      packageStore: s3storeIamStore,
      proxy_origin: proxyOrigin.trim().isEmpty ? null : Uri.parse(proxyOrigin));

  await s3storeIamStore.init();

  var server = await app.serve(host, port);
  print('Serving at http://${server.address.host}:${server.port}');
}
