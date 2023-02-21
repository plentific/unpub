import 'dart:io';

import 'package:args/args.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:path/path.dart' as path;
import 'package:unpub/unpub.dart' as unpub;
import 'package:unpub_aws/unpub_aws.dart';

main(List<String> args) async {
  var parser = ArgParser();
  parser.addOption('host', abbr: 'h', defaultsTo: '0.0.0.0');
  parser.addOption('port', abbr: 'p', defaultsTo: '4000');
  parser.addOption('database', abbr: 'd', defaultsTo: 'mongodb://localhost:27017/dart_pub');
  parser.addOption('proxy-origin', abbr: 'o', defaultsTo: '');
  parser.addOption('exitOnDbError', abbr: 'e', defaultsTo: 'false');
  parser.addOption('s3bucket', abbr: 'b', defaultsTo: '');
  parser.addOption('s3accessKey', abbr: 'a', defaultsTo: '');
  parser.addOption('s3secretKey', abbr: 's', defaultsTo: '');
  parser.addOption('s3region', abbr: 'r', defaultsTo: '');

  var results = parser.parse(args);

  var host = results['host'] as String;
  var port = int.parse(results['port'] as String);
  var dbUri = results['database'] as String;
  var proxy_origin = results['proxy-origin'] as String;
  var exitOnDbError = (results['exitOnDbError'] as String?) == 'true';
  var s3Bucket = results['s3bucket'] as String;
  var s3access = results['s3accessKey'] as String;
  var s3secret = results['s3secretKey'] as String;
  var s3region = results['s3region'] as String;

  if (results.rest.isNotEmpty) {
    print('Got unexpected arguments: "${results.rest.join(' ')}".\n\nUsage:\n');
    print(parser.usage);
    exit(1);
  }

  final db = Db(dbUri);
  await db.open();

  var app = unpub.App(
      metaStore: unpub.MongoStore(db, onDatabaseError: exitOnDbError ? () => exit(1) : null),
      packageStore: S3Store(
        s3Bucket,
        region: s3region,
        credentials: AwsCredentials(awsAccessKeyId: s3access, awsSecretAccessKey: s3secret),
      ),
      proxy_origin: proxy_origin.trim().isEmpty ? null : Uri.parse(proxy_origin));

  var server = await app.serve(host, port);
  print('Serving at http://${server.address.host}:${server.port}');
}
