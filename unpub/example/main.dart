import 'package:mongo_dart/mongo_dart.dart';
import 'package:unpub/unpub.dart' as unpub;

main(List<String> args) async {
  String dbUri = 'mongodb://localhost:27017/dart_pub';
  final uri = Uri.parse(dbUri);
  if (!uri.queryParameters.containsKey('authMechanism')) {
    final queryParams = Map<String, String>.from(uri.queryParameters);
    queryParams['authMechanism'] = 'SCRAM-SHA-1';
    dbUri = uri.replace(queryParameters: queryParams).toString();
  }

  final db = Db(dbUri);
  await db.open(); // make sure the MongoDB connection opened

  final app = unpub.App(metaStore: unpub.MongoStore(db), packageStore: unpub.FileStore('./unpub-packages'));

  final server = await app.serve('0.0.0.0', 4000);
  print('Serving at http://${server.address.host}:${server.port}');
}
