import 'package:mongo_dart/mongo_dart.dart';
import 'package:intl/intl.dart';
import 'package:unpub/src/models.dart';
import 'meta_store.dart';

final packageCollection = 'packages';
final statsCollection = 'stats';

class MongoStore extends MetaStore {
  Db db;
  Function(String)? onDatabaseError;

  MongoStore(this.db, {this.onDatabaseError});

  static SelectorBuilder _selectByName(String? name) => where.eq('name', name);

  Future<UnpubQueryResult> _queryPackagesBySelector(
      SelectorBuilder selector) async {
    try {
      final count = await db.collection(packageCollection).count(selector);
      final packages = await db
          .collection(packageCollection)
          .find(selector)
          .map((item) => UnpubPackage.fromJson(item))
          .toList();
      return UnpubQueryResult(count, packages);
    } catch (e) {
      onDatabaseError?.call(e.toString());
      return Future.error(e);
    }
  }

  @override
  queryPackage(name) async {
    try {
      var json =
          await db.collection(packageCollection).findOne(_selectByName(name));
      if (json == null) return null;
      return UnpubPackage.fromJson(json);
    } catch (e) {
      onDatabaseError?.call();
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
      onDatabaseError?.call();
      return Future.error(e);
    }
  }

  @override
  addUploader(name, email) async {
    try {
      await db
          .collection(packageCollection)
          .update(_selectByName(name), modify.push('uploaders', email));
    } catch (e) {
      onDatabaseError?.call();
      return Future.error(e);
    }
  }

  @override
  removeUploader(name, email) async {
    try {
      await db
          .collection(packageCollection)
          .update(_selectByName(name), modify.pull('uploaders', email));
    } catch (e) {
      onDatabaseError?.call();
      return Future.error(e);
    }
  }

  @override
  increaseDownloads(name, version) {
    try {
      var today = DateFormat('yyyyMMdd').format(DateTime.now());
      db
          .collection(packageCollection)
          .update(_selectByName(name), modify.inc('download', 1));
      db
          .collection(statsCollection)
          .update(_selectByName(name), modify.inc('d$today', 1));
    } catch (e) {
      onDatabaseError?.call();
      return;
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
  }) {
    try {
      var selector =
          where.sortBy(sort, descending: true).limit(size).skip(page * size);

      if (keyword != null) {
        selector = selector.match('name', '.*$keyword.*');
      }
      if (uploader != null) {
        selector = selector.eq('uploaders', uploader);
      }
      if (dependency != null) {
        selector = selector.raw({
          'versions': {
            r'$elemMatch': {
              'pubspec.dependencies.$dependency': {r'$exists': true}
            }
          }
        });
      }

      return _queryPackagesBySelector(selector);
    } catch (e) {
      onDatabaseError?.call();
      return Future.error(e);
    }
  }
}
