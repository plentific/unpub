import 'package:test/test.dart';
import 'package:unpub/unpub.dart' as unpub;

/// A connection that is down until it is opened, refusing its first
/// [failingOpens] attempts. Closing it fails, as closing a dropped
/// connection can.
final class _FakeConnection implements unpub.MongoConnection {
  final int failingOpens;
  bool connected;
  int opens = 0;
  int closes = 0;

  _FakeConnection({required this.connected, required this.failingOpens});

  @override
  bool get isConnected => connected;

  @override
  Future<void> open() async {
    opens++;
    await Future.delayed(Duration(milliseconds: 10));
    if (opens <= failingOpens) throw Exception('Could not connect');
    connected = true;
  }

  @override
  Future<void> close() async {
    closes++;
    throw Exception('connection closed');
  }
}

/// Records the operations that reach it.
final class _RecordingStore implements unpub.MetaStore {
  final operations = <String>[];

  @override
  Future<unpub.UnpubPackage?> queryPackage(String name) async {
    operations.add('queryPackage $name');
    return null;
  }

  @override
  Future<unpub.VersionDocs> queryVersionDocs(String name, String version) async {
    operations.add('queryVersionDocs $name');
    return const unpub.VersionDocs(readme: null, changelog: null);
  }

  @override
  Future<void> addVersion(String name, unpub.UnpubVersion version) async {
    operations.add('addVersion $name');
  }

  @override
  Future<void> addUploader(String name, String email) async {
    operations.add('addUploader $name');
  }

  @override
  Future<void> removeUploader(String name, String email) async {
    operations.add('removeUploader $name');
  }

  @override
  void increaseDownloads(String name, String version) {
    operations.add('increaseDownloads $name');
  }

  @override
  Future<unpub.UnpubQueryResult> queryPackages({
    required int size,
    required int page,
    required String sort,
    String? keyword,
    String? uploader,
    String? dependency,
  }) async {
    operations.add('queryPackages');
    return unpub.UnpubQueryResult(0, []);
  }
}

main() {
  test('reopens a dropped connection once for concurrent operations', () async {
    final connection = _FakeConnection(connected: false, failingOpens: 0);
    final store = _RecordingStore();
    final metaStore = unpub.ReconnectingMetaStore(store: store, connection: connection);

    await Future.wait([
      metaStore.queryPackage('a'),
      metaStore.queryPackage('b'),
      metaStore.addUploader('c', 'someone@example.com'),
    ]);

    expect(connection.closes, 1);
    expect(connection.opens, 1);
    expect(store.operations, ['queryPackage a', 'queryPackage b', 'addUploader c']);
  });

  test('leaves a live connection alone', () async {
    final connection = _FakeConnection(connected: true, failingOpens: 0);
    final store = _RecordingStore();
    final metaStore = unpub.ReconnectingMetaStore(store: store, connection: connection);

    await metaStore.queryPackages(size: 10, page: 0, sort: 'download');

    expect(connection.closes, 0);
    expect(connection.opens, 0);
    expect(store.operations, ['queryPackages']);
  });

  test('fails the operation when reopening fails, and tries again on the next one', () async {
    final connection = _FakeConnection(connected: false, failingOpens: 1);
    final store = _RecordingStore();
    final metaStore = unpub.ReconnectingMetaStore(store: store, connection: connection);

    await expectLater(metaStore.queryPackage('a'), throwsException);
    await metaStore.queryPackage('b');

    expect(connection.opens, 2);
    expect(store.operations, ['queryPackage b']);
  });

  test('counts a download once the connection is back', () async {
    final connection = _FakeConnection(connected: false, failingOpens: 0);
    final store = _RecordingStore();
    final metaStore = unpub.ReconnectingMetaStore(store: store, connection: connection);

    metaStore.increaseDownloads('a', '1.0.0');
    await Future.delayed(Duration(milliseconds: 50));

    expect(connection.opens, 1);
    expect(store.operations, ['increaseDownloads a']);
  });

  test('drops a download count, without an unhandled error, while the database stays down', () async {
    final connection = _FakeConnection(connected: false, failingOpens: 1);
    final store = _RecordingStore();
    final metaStore = unpub.ReconnectingMetaStore(store: store, connection: connection);

    metaStore.increaseDownloads('a', '1.0.0');
    await Future.delayed(Duration(milliseconds: 50));

    expect(connection.opens, 1);
    expect(store.operations, isEmpty);
  });
}
