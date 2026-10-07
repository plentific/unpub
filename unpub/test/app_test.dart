import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
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
  }) async => unpub.UnpubQueryResult(packages.length, packages.values.toList());
}

/// A package archive built in memory, with a pubspec and one data file.
final class _PackageArchive {
  final String pubspecYaml;
  final List<int> data;

  _PackageArchive({required this.pubspecYaml, required this.data});

  List<int> bytes() {
    final archive = Archive();
    archive.addFile(ArchiveFile.string('pubspec.yaml', pubspecYaml));
    archive.addFile(ArchiveFile.bytes('lib/data.bin', data));
    return GZipEncoder().encodeBytes(TarEncoder().encodeBytes(archive));
  }
}

/// Posts package archives to the upload endpoint, as `dart pub publish` does.
final class _Publisher {
  final unpub.App _app;

  _Publisher(this._app);

  Future<shelf.Response> publish(List<int> archive) async {
    final upload = http.MultipartRequest('POST', Uri.parse('http://localhost/api/packages/versions/newUpload'));
    upload.files.add(http.MultipartFile.fromBytes('file', archive, filename: 'package.tar.gz'));
    final body = await upload.finalize().toBytes();
    return _app.router.call(shelf.Request('POST', upload.url, headers: upload.headers, body: body));
  }
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

    final uploaded = await _Publisher(app).publish(archive);

    expect(uploaded.statusCode, HttpStatus.found);
    expect(uploaded.headers['location'], 'http://localhost/api/packages/versions/newUploadFinish');
    final version = metaStore.packages['unpub_fixture']!.versions.single;
    expect(version.uploader, 'publisher@example.com');
    expect(version.pubspec['description'], 'A package that unpub tests publish and download.');
    expect(version.readme, contains('Published by the unpub tests.'));
    expect(version.changelog, contains('Fixture release.'));

    final versions = await app.router.call(
      shelf.Request('GET', Uri.parse('http://localhost/api/packages/unpub_fixture')),
    );
    final latest = (jsonDecode(await versions.readAsString()) as Map<String, dynamic>)['latest'];

    expect(latest['version'], '1.2.3');
    expect(latest['archive_url'], 'http://localhost/packages/unpub_fixture/versions/1.2.3.tar.gz');

    final download = await app.router.call(
      shelf.Request(
        'GET',
        Uri.parse('http://localhost/packages/unpub_fixture/versions/1.2.3.tar.gz'),
        headers: {'user-agent': 'Dart pub 3.12.2'},
      ),
    );

    expect(download.statusCode, HttpStatus.ok);
    expect(await download.read().expand((chunk) => chunk).toList(), archive);
    expect(metaStore.downloads, ['unpub_fixture 1.2.3']);
  });

  test('rejects an upload whose name is not a Dart package name', () async {
    final directory = await Directory.systemTemp.createTemp('unpub_app');
    addTearDown(() => directory.delete(recursive: true));
    final metaStore = _MemoryMetaStore();
    final publisher = _Publisher(
      unpub.App(
        metaStore: metaStore,
        packageStore: unpub.FileStore(directory.path),
        overrideUploaderEmail: 'publisher@example.com',
      ),
    );

    final response = await publisher.publish(
      _PackageArchive(pubspecYaml: 'name: ../escape\nversion: 1.0.0\n', data: [1, 2, 3]).bytes(),
    );

    expect(response.headers['location'], contains('error=invalid%20package%20name'));
    expect(metaStore.packages, isEmpty);
    expect(directory.listSync(recursive: true), isEmpty);
  });

  test('rejects an upload whose version is not a semantic version', () async {
    final directory = await Directory.systemTemp.createTemp('unpub_app');
    addTearDown(() => directory.delete(recursive: true));
    final metaStore = _MemoryMetaStore();
    final publisher = _Publisher(
      unpub.App(
        metaStore: metaStore,
        packageStore: unpub.FileStore(directory.path),
        overrideUploaderEmail: 'publisher@example.com',
      ),
    );

    final response = await publisher.publish(
      _PackageArchive(pubspecYaml: 'name: unpub_fixture\nversion: one\n', data: [1, 2, 3]).bytes(),
    );

    expect(response.headers['location'], contains('error=version%20invalid'));
    expect(metaStore.packages, isEmpty);
    expect(directory.listSync(recursive: true), isEmpty);
  });

  test('answers 404 for a package it does not have, instead of sending the client elsewhere', () async {
    final app = unpub.App(metaStore: _MemoryMetaStore(), packageStore: unpub.FileStore(Directory.systemTemp.path));

    for (final path in [
      '/api/packages/http',
      '/api/packages/http/versions/1.6.0',
      '/packages/http/versions/1.6.0.tar.gz',
    ]) {
      final response = await app.router.call(shelf.Request('GET', Uri.parse('http://localhost$path')));

      expect(response.statusCode, HttpStatus.notFound, reason: path);
    }
  });

  test('redirects a package it does not have to the upstream server when asked to', () async {
    final app = unpub.App(
      metaStore: _MemoryMetaStore(),
      packageStore: unpub.FileStore(Directory.systemTemp.path),
      missingPackages: unpub.RedirectMissingPackages(Uri.parse('https://pub.dev')),
    );

    final response = await app.router.call(shelf.Request('GET', Uri.parse('http://localhost/api/packages/http')));

    expect(response.statusCode, HttpStatus.found);
    expect(response.headers['location'], 'https://pub.dev/api/packages/http');
  });

  test('changes no uploaders of a package that does not exist', () async {
    final app = unpub.App(
      metaStore: _MemoryMetaStore(),
      packageStore: unpub.FileStore(Directory.systemTemp.path),
      overrideUploaderEmail: 'publisher@example.com',
    );

    final added = await app.router.call(
      shelf.Request(
        'POST',
        Uri.parse('http://localhost/api/packages/missing/uploaders'),
        headers: {'content-type': 'application/x-www-form-urlencoded'},
        body: 'email=someone%40example.com',
      ),
    );
    final removed = await app.router.call(
      shelf.Request('DELETE', Uri.parse('http://localhost/api/packages/missing/uploaders/someone%40example.com')),
    );

    expect(added.statusCode, HttpStatus.notFound);
    expect(removed.statusCode, HttpStatus.notFound);
  });

  test('asks for the email of the uploader to add', () async {
    final app = unpub.App(
      metaStore: _MemoryMetaStore(),
      packageStore: unpub.FileStore(Directory.systemTemp.path),
      overrideUploaderEmail: 'publisher@example.com',
    );

    final added = await app.router.call(
      shelf.Request(
        'POST',
        Uri.parse('http://localhost/api/packages/unpub_fixture/uploaders'),
        headers: {'content-type': 'application/x-www-form-urlencoded'},
        body: '',
      ),
    );

    expect(added.statusCode, HttpStatus.badRequest);
  });
}
