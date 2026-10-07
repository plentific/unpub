import 'package:unpub/src/meta_store.dart';
import 'package:unpub/src/models.dart';
import 'package:unpub/src/mongo_connection.dart';
import 'package:unpub/src/version_docs.dart';

/// A [MetaStore] that reopens the database connection before an operation
/// when the server closed it, e.g. during a failover or maintenance.
///
/// mongo_dart does not reconnect by itself: once the connection drops, every
/// query fails with "No master connection" until the process restarts.
final class ReconnectingMetaStore implements MetaStore {
  final MetaStore _store;
  final MongoConnection _connection;
  Future<void>? _reopening;

  ReconnectingMetaStore({required this._store, required this._connection});

  @override
  Future<UnpubPackage?> queryPackage(String name) async {
    await _connected();
    return _store.queryPackage(name);
  }

  @override
  Future<VersionDocs> queryVersionDocs(String name, String version) async {
    await _connected();
    return _store.queryVersionDocs(name, version);
  }

  @override
  Future<void> addVersion(String name, UnpubVersion version) async {
    await _connected();
    await _store.addVersion(name, version);
  }

  @override
  Future<void> addUploader(String name, String email) async {
    await _connected();
    await _store.addUploader(name, email);
  }

  @override
  Future<void> removeUploader(String name, String email) async {
    await _connected();
    await _store.removeUploader(name, email);
  }

  @override
  void increaseDownloads(String name, String version) {
    // Not awaited, so counting never delays the download.
    _increaseDownloads(name, version);
  }

  @override
  Future<UnpubQueryResult> queryPackages({
    required int size,
    required int page,
    required String sort,
    String? keyword,
    String? uploader,
    String? dependency,
  }) async {
    await _connected();
    return _store.queryPackages(
      size: size,
      page: page,
      sort: sort,
      keyword: keyword,
      uploader: uploader,
      dependency: dependency,
    );
  }

  Future<void> _increaseDownloads(String name, String version) async {
    try {
      await _connected();
      _store.increaseDownloads(name, version);
    } catch (e) {
      print('Not counting the download of $name $version: $e');
    }
  }

  /// Reopens the connection if it dropped. Concurrent operations share one
  /// reopen; when it fails, so do they, and the next operation tries again.
  Future<void> _connected() {
    if (_connection.isConnected) return Future.value();
    switch (_reopening) {
      case final Future<void> reopening:
        return reopening;
      case null:
        final reopening = _reopen().whenComplete(_forgetReopening);
        _reopening = reopening;
        return reopening;
    }
  }

  Future<void> _reopen() async {
    print('Database connection lost, reconnecting');
    try {
      await _connection.close();
    } catch (e) {
      // The old connection is already broken, there is nothing left to close.
    }
    await _connection.open();
    print('Database reconnected');
  }

  void _forgetReopening() {
    _reopening = null;
  }
}
