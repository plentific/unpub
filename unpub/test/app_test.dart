import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';
import 'package:unpub/unpub.dart' as unpub;

/// Keeps package metadata in memory instead of MongoDB.
final class _MemoryMetaStore implements unpub.MetaStore {
  final packages = <String, unpub.UnpubPackage>{};
  final downloads = <String>[];

  @override
  Future<unpub.UnpubPackage?> queryPackage(String name) async => packages[name];

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
  }) async =>
      unpub.UnpubQueryResult(packages.length, packages.values.toList());
}

main() {
  test('publishes a package archive and serves it back to dart pub', () async {
    final directory = await Directory.systemTemp.createTemp('unpub_app');
    addTearDown(() => directory.delete(recursive: true));
    final metaStore = _MemoryMetaStore();
    final app = unpub.App(
      metaStore: metaStore,
      packageStore: unpub.FileStore(directory.path),
      overrideUploaderEmail: 'publisher@example.com',
    );
    // Made with tar like `dart pub publish` makes them: ustar, files at the root.
    final archive = await File('test/fixtures/upload/unpub_fixture-1.2.3.tar.gz').readAsBytes();

    final upload = http.MultipartRequest('POST', Uri.parse('http://localhost/api/packages/versions/newUpload'));
    upload.files.add(http.MultipartFile.fromBytes('file', archive, filename: 'package.tar.gz'));
    final uploadBody = await upload.finalize().toBytes();
    final uploaded = await app.router.call(shelf.Request('POST', upload.url, headers: upload.headers, body: uploadBody));

    expect(uploaded.statusCode, HttpStatus.found);
    expect(uploaded.headers['location'], 'http://localhost/api/packages/versions/newUploadFinish');
    final version = metaStore.packages['unpub_fixture']!.versions.single;
    expect(version.uploader, 'publisher@example.com');
    expect(version.pubspec['description'], 'A package that unpub tests publish and download.');
    expect(version.readme, contains('Published by the unpub tests.'));
    expect(version.changelog, contains('Fixture release.'));

    final versions = await app.router.call(shelf.Request('GET', Uri.parse('http://localhost/api/packages/unpub_fixture')));
    final latest = (jsonDecode(await versions.readAsString()) as Map<String, dynamic>)['latest'];

    expect(latest['version'], '1.2.3');
    expect(latest['archive_url'], 'http://localhost/packages/unpub_fixture/versions/1.2.3.tar.gz');

    final download = await app.router.call(shelf.Request(
      'GET',
      Uri.parse('http://localhost/packages/unpub_fixture/versions/1.2.3.tar.gz'),
      headers: {'user-agent': 'Dart pub 3.12.2'},
    ));

    expect(download.statusCode, HttpStatus.ok);
    expect(await download.read().expand((chunk) => chunk).toList(), archive);
    expect(metaStore.downloads, ['unpub_fixture 1.2.3']);
  });
}
