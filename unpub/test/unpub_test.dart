// Needs a MongoDB server on localhost:27017.
@Tags(['mongodb'])
library;

import 'dart:io';
import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:unpub/src/utils.dart';
import 'package:test/test.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:mongo_dart/mongo_dart.dart';
import 'utils.dart';
import 'package:unpub/unpub.dart';

main() {
  Db _db = Db('mongodb://localhost:27017/dart_pub_test');
  late HttpServer _server;

  setUpAll(() async {
    await _db.open();
  });

  Future<Map<String, dynamic>> _readMeta(String name) async {
    var res = await _db.collection(packageCollection).findOne(where.eq('name', name));
    res!.remove('_id'); // TODO: null
    return res;
  }

  Future<Map<String, dynamic>?> _readDocs(String name, String version) async {
    var res = await _db.collection(docsCollection).findOne(where.eq('name', name).eq('version', version));
    res?.remove('_id');
    return res;
  }

  Map<String, String> _pubspecCache = {};

  Future<String?> _readFile(String package, String version, String filename) async {
    var key = package + version + filename;
    if (_pubspecCache[key] == null) {
      var filePath = path.absolute('test/fixtures', package, version, filename);
      _pubspecCache[key] = await File(filePath).readAsString();
    }
    return _pubspecCache[key];
  }

  _cleanUpDb() async {
    await _db.dropCollection(packageCollection);
    await _db.dropCollection(docsCollection);
  }

  tearDownAll(() async {
    await _db.close();
  });

  group('publish', () {
    setUpAll(() async {
      await _cleanUpDb();
      _server = await createServer(email0);
    });

    tearDownAll(() async {
      await _server.close();
    });

    test('fresh', () async {
      var version = '0.0.1';

      var result = await pubPublish(package0, version);
      expect(result.stderr, '');

      var meta = await _readMeta(package0);

      expect(meta['name'], package0);
      expect(meta['uploaders'], [email0]);
      expect(meta['private'], true);
      expect(meta['createdAt'], isA<DateTime>());
      expect(meta['updatedAt'], isA<DateTime>());
      expect(meta['versions'], isList);
      expect(meta['versions'], hasLength(1));

      var item = meta['versions'][0];
      expect(item['createdAt'], isA<DateTime>());
      item.remove('createdAt');
      expect(
        DeepCollectionEquality().equals(item, {
          'version': version,
          'pubspec': loadYamlAsMap(await _readFile(package0, version, 'pubspec.yaml')),
          'uploader': email0,
        }),
        true,
      );
      expect(
        DeepCollectionEquality().equals(await _readDocs(package0, version), {
          'name': package0,
          'version': version,
          'pubspecYaml': await _readFile(package0, version, 'pubspec.yaml'),
          'readme': await _readFile(package0, version, 'README.md'),
          'changelog': await _readFile(package0, version, 'CHANGELOG.md'),
        }),
        true,
      );
    });

    test('existing package', () async {
      var version = '0.0.3';

      var result = await pubPublish(package0, version);
      expect(result.stderr, '');

      var meta = await _readMeta(package0);

      expect(meta['name'], package0);
      expect(meta['uploaders'], [email0]);
      expect(meta['versions'], isList);
      expect(meta['versions'], hasLength(2));
      expect(meta['versions'][0]['version'], '0.0.1');
      expect(meta['versions'][1]['version'], version);
    });

    test('duplicated version', () async {
      var result = await pubPublish(package0, '0.0.3');
      expect(result.stderr, contains('version invalid'));
    });

    test('no readme and changelog', () async {
      var version = '1.0.0-noreadme';
      // Not checking stderr: pub prints suggestions for a package without a readme.
      await pubPublish(package0, version);

      var meta = await _readMeta(package0);

      expect(meta['name'], package0);
      expect(meta['uploaders'], [email0]);
      expect(meta['versions'], isList);
      expect(meta['versions'], hasLength(3));
      expect(meta['versions'][0]['version'], '0.0.1');
      expect(meta['versions'][1]['version'], '0.0.3');

      var item = meta['versions'][2];
      expect(item['createdAt'], isA<DateTime>());
      item.remove('createdAt');
      expect(
        DeepCollectionEquality().equals(item, {
          'version': version,
          'pubspec': loadYamlAsMap(await _readFile(package0, version, 'pubspec.yaml')),
          'uploader': email0,
        }),
        true,
      );
      expect(
        DeepCollectionEquality().equals(await _readDocs(package0, version), {
          'name': package0,
          'version': version,
          'pubspecYaml': await _readFile(package0, version, 'pubspec.yaml'),
          'readme': null,
          'changelog': null,
        }),
        true,
      );
    });
  });

  group('version docs', () {
    setUpAll(() async {
      await _cleanUpDb();
      _server = await createServer(email0);
      // A package published before the docs moved out of package documents.
      await _db.collection(packageCollection).insertOne({
        'name': package0,
        'versions': [
          {
            'version': '0.0.1',
            'pubspec': loadYamlAsMap(await _readFile(package0, '0.0.1', 'pubspec.yaml')),
            'pubspecYaml': await _readFile(package0, '0.0.1', 'pubspec.yaml'),
            'uploader': email0,
            'readme': 'legacy readme',
            'changelog': 'legacy changelog',
            'createdAt': DateTime.utc(2025, 1, 1),
          },
        ],
        'uploaders': [email0],
        'private': true,
        'download': 0,
        'createdAt': DateTime.utc(2025, 1, 1),
        'updatedAt': DateTime.utc(2025, 1, 1),
      });
    });

    tearDownAll(() async {
      await _server.close();
    });

    Future<Map<String, dynamic>> readPage(String version) async {
      var res = await http.get(baseUri.resolve('/webapi/package/$package0/$version'));
      return json.decode(res.body)['data'] as Map<String, dynamic>;
    }

    test('are read from the package document until it is published again', () async {
      var page = await readPage('0.0.1');

      expect(page['readme'], 'legacy readme');
      expect(page['changelog'], 'legacy changelog');
    });

    test('move out of the package document on its next publish', () async {
      var result = await pubPublish(package0, '0.0.2');
      expect(result.stderr, '');

      var meta = await _readMeta(package0);
      for (var version in meta['versions'] as List) {
        expect(version, isNot(contains('readme')));
        expect(version, isNot(contains('changelog')));
        expect(version, isNot(contains('pubspecYaml')));
      }
      expect((await _readDocs(package0, '0.0.1'))!['readme'], 'legacy readme');
      expect((await readPage('0.0.1'))['readme'], 'legacy readme');
      expect((await readPage('0.0.2'))['readme'], await _readFile(package0, '0.0.2', 'README.md'));
    });
  });

  group('get versions', () {
    setUpAll(() async {
      await _cleanUpDb();
      _server = await createServer(email0);
      await pubPublish(package0, '0.0.1');
      await pubPublish(package0, '0.0.2');
    });

    tearDownAll(() async {
      await _server.close();
    });

    test('existing at local', () async {
      var res = await getVersions(package0);
      expect(res.statusCode, HttpStatus.ok);

      var body = json.decode(res.body);
      expect(
        DeepCollectionEquality().equals(body, {
          "name": "package_0",
          "latest": {
            "archive_url": "$pubHostedUrl/packages/package_0/versions/0.0.2.tar.gz",
            "pubspec": loadYamlAsMap(await _readFile('package_0', '0.0.2', 'pubspec.yaml')),
            "version": "0.0.2",
          },
          "versions": [
            {
              "archive_url": "$pubHostedUrl/packages/package_0/versions/0.0.1.tar.gz",
              "pubspec": loadYamlAsMap(await _readFile('package_0', '0.0.1', 'pubspec.yaml')),
              "version": "0.0.1",
            },
            {
              "archive_url": "$pubHostedUrl/packages/package_0/versions/0.0.2.tar.gz",
              "pubspec": loadYamlAsMap(await _readFile('package_0', '0.0.2', 'pubspec.yaml')),
              "version": "0.0.2",
            },
          ],
        }),
        true,
      );
    });

    test('only on pub.dev', () async {
      var res = await getVersions('http');
      expect(res.statusCode, HttpStatus.notFound);
    });

    test('not existing', () async {
      var res = await getVersions(notExistingPacakge);
      expect(res.statusCode, HttpStatus.notFound);
    });
  });

  group('get specific version', () {
    setUpAll(() async {
      await _cleanUpDb();
      _server = await createServer(email0);
      await pubPublish(package0, '0.0.1');
      await pubPublish(package0, '0.0.3+1');
    });

    tearDownAll(() async {
      await _server.close();
    });

    test('existing at local', () async {
      var res = await getSpecificVersion(package0, '0.0.1');
      expect(res.statusCode, HttpStatus.ok);

      var body = json.decode(res.body);
      expect(
        DeepCollectionEquality().equals(body, {
          "archive_url": "$pubHostedUrl/packages/package_0/versions/0.0.1.tar.gz",
          "pubspec": loadYamlAsMap(await _readFile('package_0', '0.0.1', 'pubspec.yaml')),
          "version": '0.0.1',
        }),
        true,
      );
    });

    test('decode version correctly', () async {
      var res = await getSpecificVersion(package0, '0.0.3+1');
      expect(res.statusCode, HttpStatus.ok);

      var body = json.decode(res.body);
      expect(
        DeepCollectionEquality().equals(body, {
          "archive_url": "$pubHostedUrl/packages/package_0/versions/0.0.3+1.tar.gz",
          "pubspec": loadYamlAsMap(await _readFile('package_0', '0.0.3+1', 'pubspec.yaml')),
          "version": '0.0.3+1',
        }),
        true,
      );
    });

    test('not existing version at local', () async {
      var res = await getSpecificVersion(package0, '0.0.2');
      expect(res.statusCode, HttpStatus.notFound);
    });

    test('only on pub.dev', () async {
      var res = await getSpecificVersion('http', '0.12.0+2');
      expect(res.statusCode, HttpStatus.notFound);
    });

    test('not existing', () async {
      var res = await getSpecificVersion(notExistingPacakge, '0.0.1');
      expect(res.statusCode, HttpStatus.notFound);
    });
  });

  group('uploader', () {
    setUpAll(() async {
      await _cleanUpDb();
      _server = await createServer(email0);
      await pubPublish(package0, '0.0.1');
    });

    tearDownAll(() async {
      await _server.close();
    });

    group('add', () {
      test('already exists', () async {
        var response = await changeUploader(package0, 'add', email0);
        expect(response.body, contains('email already exists'));

        var meta = await _readMeta(package0);
        expect(meta['uploaders'], unorderedEquals([email0]));
      });

      test('success', () async {
        var response = await changeUploader(package0, 'add', email1);
        expect(response.statusCode, HttpStatus.ok);

        var meta = await _readMeta(package0);
        expect(meta['uploaders'], unorderedEquals([email0, email1]));

        response = await changeUploader(package0, 'add', email2);
        expect(response.statusCode, HttpStatus.ok);

        meta = await _readMeta(package0);
        expect(meta['uploaders'], unorderedEquals([email0, email1, email2]));
      });
    });

    group('remove', () {
      test('not in uploader', () async {
        var response = await changeUploader(package0, 'remove', email3);
        expect(response.body, contains('email not uploader'));

        var meta = await _readMeta(package0);
        expect(meta['uploaders'], unorderedEquals([email0, email1, email2]));
      });

      test('success', () async {
        var response = await changeUploader(package0, 'remove', email2);
        expect(response.statusCode, HttpStatus.ok);

        var meta = await _readMeta(package0);
        expect(meta['uploaders'], unorderedEquals([email0, email1]));

        response = await changeUploader(package0, 'remove', email1);
        expect(response.statusCode, HttpStatus.ok);

        meta = await _readMeta(package0);
        expect(meta['uploaders'], unorderedEquals([email0]));
      });
    });

    group('permission', () {
      setUpAll(() async {
        await _server.close();
        _server = await createServer(email1);
      });

      tearDownAll(() async {
        await _server.close();
      });

      test('add', () async {
        var response = await changeUploader(package0, 'add', email0);
        expect(response.statusCode, HttpStatus.forbidden);
        expect(response.body, contains('no permission'));
      });

      test('remove', () async {
        var response = await changeUploader(package0, 'remove', email0);
        expect(response.statusCode, HttpStatus.forbidden);
        expect(response.body, contains('no permission'));
      });
    });
  });

  group('badge', () {
    setUpAll(() async {
      await _cleanUpDb();
      _server = await createServer(email0);
      await pubPublish(package0, '0.0.1');
    });

    tearDownAll(() async {
      await _server.close();
    });

    group('v', () {
      test('<1.0.0', () async {
        var res = await http.Client().send(
          http.Request('GET', baseUri.resolve('/badge/v/$package0'))..followRedirects = false,
        );
        expect(res.statusCode, HttpStatus.found);
        expect(
          res.headers[HttpHeaders.locationHeader],
          'https://img.shields.io/static/v1?label=unpub&message=0.0.1&color=orange',
        );
      });

      test('>=1.0.0', () async {
        await pubPublish(package0, '1.0.0');

        var res = await http.Client().send(
          http.Request('GET', baseUri.resolve('/badge/v/$package0'))..followRedirects = false,
        );
        expect(res.statusCode, HttpStatus.found);
        expect(
          res.headers[HttpHeaders.locationHeader],
          'https://img.shields.io/static/v1?label=unpub&message=1.0.0&color=blue',
        );
      });

      test('package not exists', () async {
        var res = await http.get(baseUri.resolve('/badge/v/$notExistingPacakge'));
        expect(res.statusCode, HttpStatus.notFound);
      });
    });

    group('d', () {
      test('correct download count', () async {
        var res = await http.Client().send(
          http.Request('GET', baseUri.resolve('/badge/d/$package0'))..followRedirects = false,
        );
        expect(res.statusCode, HttpStatus.found);
        expect(
          res.headers[HttpHeaders.locationHeader],
          'https://img.shields.io/static/v1?label=downloads&message=0&color=blue',
        );
      });

      test('package not exists', () async {
        var res = await http.get(baseUri.resolve('/badge/d/$notExistingPacakge'));
        expect(res.statusCode, HttpStatus.notFound);
      });
    });
  });
}
