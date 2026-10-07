import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:unpub/unpub.dart' as unpub;
import 'package:mongo_dart/mongo_dart.dart';

final notExistingPacakge = 'not_existing_package';
final baseDir = path.absolute('unpub-packages');
final pubHostedUrl = 'http://localhost:4000';
final baseUri = Uri.parse(pubHostedUrl);

final package0 = 'package_0';
final package1 = 'package_1';
final email0 = 'email0@example.com';
final email1 = 'email1@example.com';
final email2 = 'email2@example.com';
final email3 = 'email3@example.com';

createServer(String opEmail) async {
  final db = Db('mongodb://localhost:27017/dart_pub_test');
  await db.open();
  var mongoStore = unpub.MongoStore(db);
  await mongoStore.createIndexes();

  var app = unpub.App(metaStore: mongoStore, packageStore: unpub.FileStore(baseDir), overrideUploaderEmail: opEmail);

  var server = await app.serve('0.0.0.0', 4000);
  return server;
}

Future<http.Response> getVersions(String package) {
  package = Uri.encodeComponent(package);
  return http.get(baseUri.resolve('/api/packages/$package'));
}

Future<http.Response> getSpecificVersion(String package, String version) {
  package = Uri.encodeComponent(package);
  version = Uri.encodeComponent(version);
  return http.get(baseUri.resolve('/api/packages/$package/versions/$version'));
}

Future<ProcessResult> pubPublish(String name, String version) {
  return Process.run(
    'dart',
    ['pub', 'publish', '--force'],
    workingDirectory: path.absolute('test/fixtures', name, version),
    environment: {'PUB_HOSTED_URL': pubHostedUrl},
  );
}

/// Adds or removes an uploader through the API, as `dart pub uploader` did
/// before pub stopped managing uploaders from the command line.
Future<http.Response> changeUploader(String name, String operation, String email) {
  assert(['add', 'remove'].contains(operation), 'operation error');
  final package = Uri.encodeComponent(name);
  if (operation == 'add') {
    return http.post(baseUri.resolve('/api/packages/$package/uploaders'), body: {'email': email});
  }
  return http.delete(baseUri.resolve('/api/packages/$package/uploaders/${Uri.encodeComponent(email)}'));
}
