import 'package:mongo_dart/mongo_dart.dart';
import 'package:unpub/src/models.dart';
import 'package:unpub/src/version_docs.dart';

import 'meta_store.dart';

final packageCollection = 'packages';

/// The readme, changelog and pubspec text of each version. Versions kept them
/// in the package document before, which made a package that publishes often
/// grow towards the 16 MB document limit, and every lookup read them.
final docsCollection = 'version_docs';

class MongoStore extends MetaStore {
  Db db;
  Function(String)? onDatabaseError;

  MongoStore(this.db, {this.onDatabaseError});

  static SelectorBuilder _selectByName(String? name) => where.eq('name', name);

  static SelectorBuilder _selectVersion(String name, String version) => where.eq('name', name).eq('version', version);

  /// Leaves out the version fields that are kept in [docsCollection], for
  /// packages that still have them in their document.
  static SelectorBuilder _withoutDocs(SelectorBuilder selector) =>
      selector.excludeFields(['versions.readme', 'versions.changelog', 'versions.pubspecYaml']);

  @override
  queryPackage(name) async {
    try {
      var json = await db.collection(packageCollection).findOne(_withoutDocs(_selectByName(name)));
      if (json == null) return null;
      return UnpubPackage.fromJson(json);
    } catch (e) {
      onDatabaseError?.call(e.toString());
      return Future.error(e);
    }
  }

  @override
  Future<VersionDocs> queryVersionDocs(String name, String version) async {
    try {
      var docs = await db.collection(docsCollection).findOne(_selectVersion(name, version));
      if (docs != null) {
        return VersionDocs(readme: docs['readme'] as String?, changelog: docs['changelog'] as String?);
      }
      // A version of a package whose docs were not moved out of its document yet.
      var package = await db.collection(packageCollection).findOne(_selectByName(name));
      for (var stored in package == null ? const [] : package['versions'] as List) {
        if (stored is Map && stored['version'] == version) {
          return VersionDocs(readme: stored['readme'] as String?, changelog: stored['changelog'] as String?);
        }
      }
      return const VersionDocs(readme: null, changelog: null);
    } catch (e) {
      onDatabaseError?.call(e.toString());
      return Future.error(e);
    }
  }

  @override
  addVersion(name, version) async {
    try {
      await _storeDocs(name, version.version, version.readme, version.changelog, version.pubspecYaml);
      var withoutDocs = UnpubVersion(
        version.version,
        version.pubspec,
        null,
        version.uploader,
        null,
        null,
        version.createdAt,
      );
      await db
          .collection(packageCollection)
          .update(
            _selectByName(name),
            modify
                .push('versions', withoutDocs.toJson())
                .addToSet('uploaders', version.uploader)
                .setOnInsert('createdAt', version.createdAt)
                .setOnInsert('private', true)
                .setOnInsert('download', 0)
                .set('updatedAt', version.createdAt),
            upsert: true,
          );
      await _moveDocsOutOfPackage(name);
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
      await db.collection(packageCollection).update(_selectByName(name), modify.inc('download', 1));
    } catch (e) {
      print('Failed to count the download of $name $version: $e');
      onDatabaseError?.call(e.toString());
    }
  }

  Future<void> _storeDocs(String name, String version, Object? readme, Object? changelog, Object? pubspecYaml) => db
      .collection(docsCollection)
      .update(
        _selectVersion(name, version),
        modify.set('readme', readme).set('changelog', changelog).set('pubspecYaml', pubspecYaml),
        upsert: true,
      );

  /// Moves the docs of the versions published before [docsCollection] out of
  /// the package document, so the package's next publish shrinks it. Copying
  /// before removing makes it safe to repeat after a failure.
  Future<void> _moveDocsOutOfPackage(String name) async {
    var package = await db.collection(packageCollection).findOne(_selectByName(name));
    var versions = package == null ? const [] : package['versions'] as List;
    var withDocs = [
      for (var stored in versions)
        if (stored is Map &&
            (stored.containsKey('readme') || stored.containsKey('changelog') || stored.containsKey('pubspecYaml')))
          stored,
    ];
    if (withDocs.isEmpty) return;
    for (var stored in withDocs) {
      await _storeDocs(name, stored['version'] as String, stored['readme'], stored['changelog'], stored['pubspecYaml']);
    }
    await db
        .collection(packageCollection)
        .update(
          _selectByName(name),
          modify.unset(r'versions.$[].readme').unset(r'versions.$[].changelog').unset(r'versions.$[].pubspecYaml'),
        );
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
      // Only the ids: a package document holds every version with its readme
      // and changelog, and only their number is needed here.
      final count = await db
          .collection(packageCollection)
          .find(_packagesMatching(keyword, uploader, dependency).fields(['_id']))
          .length;
      final packages = await db
          .collection(packageCollection)
          .find(
            _withoutDocs(
              _packagesMatching(keyword, uploader, dependency),
            ).sortBy(sort, descending: true).limit(size).skip(page * size),
          )
          .map((item) => UnpubPackage.fromJson(item))
          .toList();

      return UnpubQueryResult(count, packages);
    } catch (e) {
      onDatabaseError?.call(e.toString());
      return Future.error(e);
    }
  }

  /// A new selector for every query: projecting, sorting and paging change
  /// the selector they are called on.
  SelectorBuilder _packagesMatching(String? keyword, String? uploader, String? dependency) {
    var selector = where;
    if (keyword != null) {
      selector = selector.match('name', '.*${RegExp.escape(keyword)}.*');
    }
    if (uploader != null) {
      selector = selector.eq('uploaders', uploader);
    }
    if (dependency != null) {
      selector = selector.raw({
        'versions': {
          r'$elemMatch': {
            'pubspec.dependencies.$dependency': {r'$exists': true},
          },
        },
      });
    }
    return selector;
  }
}
