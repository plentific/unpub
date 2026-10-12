import 'package:unpub/unpub.dart' as unpub;

/// Keeps package metadata in memory instead of MongoDB.
final class MemoryMetaStore implements unpub.MetaStore {
  final packages = <String, unpub.UnpubPackage>{};
  final downloads = <String>[];

  @override
  Future<unpub.UnpubPackage?> queryPackage(String name) async => packages[name];

  @override
  Future<unpub.VersionDocs> queryVersionDocs(String name, String version) async {
    for (final stored in [...?packages[name]?.versions]) {
      if (stored.version == version) {
        return unpub.VersionDocs(readme: stored.readme, changelog: stored.changelog);
      }
    }
    return const unpub.VersionDocs(readme: null, changelog: null);
  }

  @override
  Future<void> addVersion(String name, unpub.UnpubVersion version) async {
    packages[name] = unpub.UnpubPackage(
      name,
      [...?packages[name]?.versions, version],
      true,
      [?version.uploader],
      version.createdAt,
      version.createdAt,
      0,
    );
  }

  @override
  Future<void> addUploader(String name, String email) => throw UnimplementedError();

  @override
  Future<void> removeUploader(String name, String email) => throw UnimplementedError();

  @override
  void increaseDownloads(String name, String version) {
    downloads.add('$name $version');
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
    final matching = [
      for (final package in packages.values)
        if (keyword == null || package.name.contains(keyword)) package,
    ];
    matching.sort((a, b) => a.name.compareTo(b.name));
    return unpub.UnpubQueryResult(matching.length, matching.skip(page * size).take(size).toList());
  }
}
