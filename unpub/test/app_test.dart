import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';
import 'package:unpub/unpub.dart' as unpub;

import 'memory_meta_store.dart';

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
    final metaStore = MemoryMetaStore();
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
    final metaStore = MemoryMetaStore();
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
    final metaStore = MemoryMetaStore();
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

  test('rejects an archive larger than the upload limit', () async {
    final directory = await Directory.systemTemp.createTemp('unpub_app');
    addTearDown(() => directory.delete(recursive: true));
    final metaStore = MemoryMetaStore();
    final publisher = _Publisher(
      unpub.App(
        metaStore: metaStore,
        packageStore: unpub.FileStore(directory.path),
        overrideUploaderEmail: 'publisher@example.com',
        maxArchiveBytes: 4 * 1024,
      ),
    );
    final random = Random(42);
    final incompressible = List.generate(16 * 1024, (index) => random.nextInt(256));

    final response = await publisher.publish(
      _PackageArchive(pubspecYaml: 'name: unpub_fixture\nversion: 1.0.0\n', data: incompressible).bytes(),
    );

    expect(response.headers['location'], contains('error=package%20archive%20is%20larger%20than'));
    expect(metaStore.packages, isEmpty);
  });

  test('rejects an archive that unpacks to more than the limit', () async {
    final directory = await Directory.systemTemp.createTemp('unpub_app');
    addTearDown(() => directory.delete(recursive: true));
    final metaStore = MemoryMetaStore();
    final publisher = _Publisher(
      unpub.App(
        metaStore: metaStore,
        packageStore: unpub.FileStore(directory.path),
        overrideUploaderEmail: 'publisher@example.com',
        maxUnpackedBytes: 64 * 1024,
      ),
    );
    // A megabyte of zeros packs into about a kilobyte.
    final archive = _PackageArchive(
      pubspecYaml: 'name: unpub_fixture\nversion: 1.0.0\n',
      data: List.filled(1024 * 1024, 0),
    ).bytes();

    final response = await publisher.publish(archive);

    expect(archive.length, lessThan(16 * 1024));
    expect(response.headers['location'], contains('error=unpacked%20package%20is%20larger%20than'));
    expect(metaStore.packages, isEmpty);
  });

  test('shows the package page for authors with and without an email', () async {
    final metaStore = MemoryMetaStore();
    await metaStore.addVersion(
      'unpub_fixture',
      unpub.UnpubVersion(
        '1.0.0',
        {
          'name': 'unpub_fixture',
          'version': '1.0.0',
          'authors': ['Jane Doe', 'John Roe <john@example.com>'],
        },
        null,
        'publisher@example.com',
        null,
        null,
        DateTime.utc(2026, 10, 7),
      ),
    );
    final app = unpub.App(metaStore: metaStore, packageStore: unpub.FileStore(Directory.systemTemp.path));

    final response = await app.router.call(
      shelf.Request('GET', Uri.parse('http://localhost/webapi/package/unpub_fixture/latest')),
    );

    expect(response.statusCode, HttpStatus.ok);
    final data = (jsonDecode(await response.readAsString()) as Map<String, dynamic>)['data'];
    expect(data['authors'], ['Jane Doe', 'john@example.com']);
  });

  test('answers 404 for a package it does not have, instead of sending the client elsewhere', () async {
    final app = unpub.App(metaStore: MemoryMetaStore(), packageStore: unpub.FileStore(Directory.systemTemp.path));

    for (final path in [
      '/api/packages/http',
      '/api/packages/http/versions/1.6.0',
      '/packages/http/versions/1.6.0.tar.gz',
    ]) {
      final response = await app.router.call(shelf.Request('GET', Uri.parse('http://localhost$path')));

      expect(response.statusCode, HttpStatus.notFound, reason: path);
    }
  });

  test('finds a version as it is or percent-encoded, and answers 404 for one it does not have', () async {
    final metaStore = MemoryMetaStore();
    await metaStore.addVersion(
      'acme_ui',
      unpub.UnpubVersion(
        '1.0.0+1',
        {'name': 'acme_ui', 'version': '1.0.0+1'},
        null,
        'publisher@example.com',
        null,
        null,
        DateTime.utc(2026, 1, 2),
      ),
    );
    final app = unpub.App(metaStore: metaStore, packageStore: unpub.FileStore(Directory.systemTemp.path));

    for (final (path, status) in [
      ('/api/packages/acme_ui/versions/1.0.0+1', HttpStatus.ok),
      ('/api/packages/acme_ui/versions/1.0.0%2B1', HttpStatus.ok),
      ('/packages/acme_ui/versions/1.0.0%2B1', HttpStatus.ok),
      ('/api/packages/acme_ui/versions/9.9.9', HttpStatus.notFound),
      ('/packages/acme_ui/versions/9.9.9.tar.gz', HttpStatus.notFound),
    ]) {
      final response = await app.router.call(
        shelf.Request('GET', Uri.parse('http://localhost$path'), headers: {'user-agent': 'Dart pub 3.12.2'}),
      );

      expect(response.statusCode, status, reason: path);
    }
    expect(metaStore.downloads, isEmpty);
  });

  test('redirects a package it does not have to the upstream server when asked to', () async {
    final app = unpub.App(
      metaStore: MemoryMetaStore(),
      packageStore: unpub.FileStore(Directory.systemTemp.path),
      missingPackages: unpub.RedirectMissingPackages(Uri.parse('https://pub.dev')),
    );

    final response = await app.router.call(shelf.Request('GET', Uri.parse('http://localhost/api/packages/http')));

    expect(response.statusCode, HttpStatus.found);
    expect(response.headers['location'], 'https://pub.dev/api/packages/http');
  });

  test('changes no uploaders of a package that does not exist', () async {
    final app = unpub.App(
      metaStore: MemoryMetaStore(),
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
      metaStore: MemoryMetaStore(),
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
