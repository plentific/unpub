import 'package:intl/intl.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:unpub/src/models.dart';

import 'meta_store.dart';

final packageCollection = 'packages';
final statsCollection = 'stats';

class MongoStore extends MetaStore {
  Db db;
  Function(String)? onDatabaseError;

  MongoStore(this.db, {this.onDatabaseError});

  static SelectorBuilder _selectByName(String? name) => where.eq('name', name);

  @override
  queryPackage(name) async {
    try {
      var json = await db.collection(packageCollection).findOne(_selectByName(name));
      if (json == null) return null;
      return UnpubPackage.fromJson(json);
    } catch (e) {
      onDatabaseError?.call(e.toString());
      return Future.error(e);
    }
  }

  @override
  addVersion(name, version) async {
    try {
      await db.collection(packageCollection).update(
          _selectByName(name),
          modify
              .push('versions', version.toJson())
              .addToSet('uploaders', version.uploader)
              .setOnInsert('createdAt', version.createdAt)
              .setOnInsert('private', true)
              .setOnInsert('download', 0)
              .set('updatedAt', version.createdAt),
          upsert: true);
    } catch (e) {
      onDatabaseError?.call(e.toString());
      return Future.error(e);
    }
  }

  @override
  addUploader(name, email) async {
    try {
      await db.collection(packageCollection).update(_selectByName(name), modify.push('uploaders', email));
    } catch (e) {
      onDatabaseError?.call(e.toString());
      return Future.error(e);
    }
  }

  @override
  removeUploader(name, email) async {
    try {
      await db.collection(packageCollection).update(_selectByName(name), modify.pull('uploaders', email));
    } catch (e) {
      onDatabaseError?.call(e.toString());
      return Future.error(e);
    }
  }

  @override
  increaseDownloads(name, version) {
    // Not awaited, so counting never delays the download.
    _countDownload(name, version);
  }

  Future<void> _countDownload(String name, String version) async {
    try {
      var today = DateFormat('yyyyMMdd').format(DateTime.now());
      await Future.wait([
        db.collection(packageCollection).update(_selectByName(name), modify.inc('download', 1)),
        db.collection(statsCollection).update(_selectByName(name), modify.inc('d$today', 1)),
      ]);
    } catch (e) {
      print('Failed to count the download of $name $version: $e');
      onDatabaseError?.call(e.toString());
    }
  }

  @override
  Future<UnpubQueryResult> queryPackages({
    required size,
    required page,
    required sort,
    keyword,
    uploader,
    dependency,
  }) async {
    try {
      // Build base selector for filtering
      SelectorBuilder baseSelector = where;

      if (keyword != null) {
        baseSelector = baseSelector.match('name', '.*${RegExp.escape(keyword)}.*');
      }
      if (uploader != null) {
        baseSelector = baseSelector.eq('uploaders', uploader);
      }
      if (dependency != null) {
        baseSelector = baseSelector.raw({
          'versions': {
            r'$elemMatch': {
              'pubspec.dependencies.$dependency': {r'$exists': true}
            }
          }
        });
      }

      // MongoDB 5.0 compatibility: count() method is deprecated.
      // MongoDB added countDocuments() and estimatedDocumentCount() as replacements,
      // but mongo_dart doesn't expose these methods yet. Use manual counting instead.
      final allDocsForCount = await db.collection(packageCollection).find(baseSelector).toList();
      final count = allDocsForCount.length;

      // Build selector with pagination and sorting for fetching results
      final dataSelector = baseSelector.sortBy(sort, descending: true).limit(size).skip(page * size);

      // Fetch paginated results
      final packages = await db
          .collection(packageCollection)
          .find(dataSelector)
          .map((item) => UnpubPackage.fromJson(item))
          .toList();

      return UnpubQueryResult(count, packages);
    } catch (e) {
      onDatabaseError?.call(e.toString());
      return Future.error(e);
    }
  }
}
