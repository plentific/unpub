import 'package:mongo_dart/mongo_dart.dart';
import 'package:test/test.dart';
import 'package:unpub/unpub.dart' as unpub;

main() {
  test('does not leave a failed download count unhandled', () async {
    // Never opened, so both count updates fail.
    final store = unpub.MongoStore(Db('mongodb://localhost:27017/dart_pub_test'));

    store.increaseDownloads('a', '1.0.0');

    // An unhandled error from the updates would fail this test.
    await Future.delayed(Duration(milliseconds: 50));
  });
}
