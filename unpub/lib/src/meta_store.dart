import 'package:unpub/src/models.dart';
import 'package:unpub/src/version_docs.dart';

abstract class MetaStore {
  /// The package without the readmes and changelogs of its versions.
  Future<UnpubPackage?> queryPackage(String name);

  /// The readme and changelog of a version, both null when it has none.
  Future<VersionDocs> queryVersionDocs(String name, String version);

  Future<void> addVersion(String name, UnpubVersion version);

  Future<void> addUploader(String name, String email);

  Future<void> removeUploader(String name, String email);

  void increaseDownloads(String name, String version);

  Future<UnpubQueryResult> queryPackages({
    required int size,
    required int page,
    required String sort,
    String? keyword,
    String? uploader,
    String? dependency,
  });
}
