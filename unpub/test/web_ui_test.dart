import 'dart:io';

import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';
import 'package:unpub/unpub.dart' as unpub;

import 'memory_meta_store.dart';

/// Opens the web UI's pages as a browser would.
final class _Browser {
  final unpub.App _app;

  _Browser(this._app);

  Future<shelf.Response> open(String path) =>
      _app.router.call(shelf.Request('GET', Uri.parse('http://localhost$path')));

  Future<String> read(String path) async => (await open(path)).readAsString();
}

void main() {
  test('lists the packages with their latest version, escaping what their pubspecs say', () async {
    final metaStore = MemoryMetaStore();
    for (final version in ['1.0.0', '1.1.0']) {
      await metaStore.addVersion(
        'acme_ui',
        unpub.UnpubVersion(
          version,
          {'name': 'acme_ui', 'version': version, 'description': 'Widgets <script>alert(1)</script> & more'},
          null,
          'publisher@example.com',
          null,
          null,
          DateTime.utc(2026, 1, 2),
        ),
      );
    }
    final browser = _Browser(unpub.App(metaStore: metaStore, packageStore: unpub.FileStore(Directory.systemTemp.path)));

    final response = await browser.open('/');
    final page = await response.readAsString();

    expect(response.statusCode, HttpStatus.ok);
    expect(response.headers['content-type'], 'text/html; charset=utf-8');
    expect(response.headers['content-security-policy'], contains("default-src 'none'"));
    expect(page, contains('<a class="brand" href="/"><svg class="logo"'));
    expect(page, contains('<a href="/packages/acme_ui">acme_ui</a> <span class="version">1.1.0</span>'));
    expect(page, contains('Widgets &lt;script&gt;alert(1)&lt;/script&gt; &amp; more'));
    expect(page, isNot(contains('<script')));
  });

  test('shows a package with its readme rendered, without anything that runs', () async {
    final metaStore = MemoryMetaStore();
    await metaStore.addVersion(
      'acme_ui',
      unpub.UnpubVersion(
        '1.1.0',
        {'name': 'acme_ui', 'version': '1.1.0'},
        null,
        'publisher@example.com',
        '# Acme UI\n\nWidgets for **Acme**.\n\n<script>alert(1)</script>\n\n'
            '<img src="https://example.com/logo.png" onerror="alert(2)">\n\n[Docs](javascript:alert(3))\n',
        null,
        DateTime.utc(2026, 1, 2),
      ),
    );
    final browser = _Browser(unpub.App(metaStore: metaStore, packageStore: unpub.FileStore(Directory.systemTemp.path)));

    final page = await browser.read('/packages/acme_ui');

    expect(page, contains('Acme UI</h1>'));
    expect(page, contains('Widgets for <strong>Acme</strong>.'));
    expect(page, contains('<img src="https://example.com/logo.png"'));
    expect(page, isNot(contains('<script')));
    expect(page, isNot(contains('onerror')));
    expect(page, isNot(contains('javascript:')));
    expect(page, contains('dependencies:\n  acme_ui:\n    hosted: http://localhost\n    version: ^1.1.0'));
  });

  test('shows the changelog and the versions of a package, newest first', () async {
    final metaStore = MemoryMetaStore();
    for (final version in ['1.0.0', '1.1.0', '2.0.0-dev.1']) {
      await metaStore.addVersion(
        'acme_ui',
        unpub.UnpubVersion(
          version,
          {'name': 'acme_ui', 'version': version},
          null,
          'publisher@example.com',
          'Readme of $version',
          '## $version\n\n- Changelog of $version',
          DateTime.utc(2026, 1, 2),
        ),
      );
    }
    final browser = _Browser(unpub.App(metaStore: metaStore, packageStore: unpub.FileStore(Directory.systemTemp.path)));

    final changelog = await browser.read('/packages/acme_ui?tab=changelog');
    final versions = await browser.read('/packages/acme_ui?tab=versions');
    final older = await browser.read('/packages/acme_ui/versions/1.0.0');
    final preRelease = await browser.read('/packages/acme_ui/versions/2.0.0-dev.1');

    expect(changelog, contains('Changelog of 1.1.0'));
    expect(versions, contains('<a href="/packages/acme_ui/versions/1.0.0.tar.gz">Download</a>'));
    expect(versions.indexOf('>2.0.0-dev.1</a>'), lessThan(versions.indexOf('>1.1.0</a>')));
    expect(versions.indexOf('>1.1.0</a>'), lessThan(versions.indexOf('>1.0.0</a>')));
    expect(older, contains('This is an older version. The latest is <a href="/packages/acme_ui">1.1.0</a>.'));
    expect(older, contains('Readme of 1.0.0'));
    expect(preRelease, contains('This is a pre-release. The latest stable version is <a href="/packages/acme_ui">'));
  });

  test('answers 404 for a package or a version it does not have', () async {
    final metaStore = MemoryMetaStore();
    await metaStore.addVersion(
      'acme_ui',
      unpub.UnpubVersion(
        '1.0.0',
        {'name': 'acme_ui', 'version': '1.0.0'},
        null,
        'publisher@example.com',
        null,
        null,
        DateTime.utc(2026, 1, 2),
      ),
    );
    final browser = _Browser(unpub.App(metaStore: metaStore, packageStore: unpub.FileStore(Directory.systemTemp.path)));

    final missingPackage = await browser.open('/packages/nothing');
    final missingVersion = await browser.open('/packages/acme_ui/versions/9.9.9');

    expect(missingPackage.statusCode, HttpStatus.notFound);
    expect(await missingPackage.readAsString(), contains('This server has no package named nothing.'));
    expect(missingVersion.statusCode, HttpStatus.notFound);
    expect(await missingVersion.readAsString(), contains('acme_ui has no version 9.9.9.'));
  });

  test('links web addresses from the pubspec only, and dependencies where they live', () async {
    final metaStore = MemoryMetaStore();
    await metaStore.addVersion(
      'acme_ui',
      unpub.UnpubVersion(
        '1.0.0',
        {
          'name': 'acme_ui',
          'version': '1.0.0',
          'homepage': 'javascript:alert(1)',
          'repository': 'https://github.com/acme/acme_ui',
          'dependencies': {
            'acme_core': {'hosted': 'http://localhost', 'version': '^1.0.0'},
            'http': '^1.6.0',
            'yaml': {'version': '^3.1.0'},
            'acme_tools': {'path': '../acme_tools'},
            'flutter': {'sdk': 'flutter'},
          },
        },
        null,
        'publisher@example.com',
        null,
        null,
        DateTime.utc(2026, 1, 2),
      ),
    );
    final browser = _Browser(unpub.App(metaStore: metaStore, packageStore: unpub.FileStore(Directory.systemTemp.path)));

    final page = await browser.read('/packages/acme_ui');

    expect(page, contains('<a href="https://github.com/acme/acme_ui" rel="noopener noreferrer">Repository</a>'));
    expect(page, isNot(contains('javascript:')));
    expect(page, contains('<li><a href="/packages/acme_core">acme_core</a></li>'));
    expect(page, contains('<li><a href="https://pub.dev/packages/http">http</a></li>'));
    expect(page, contains('<li><a href="https://pub.dev/packages/yaml">yaml</a></li>'));
    expect(page, contains('<li>acme_tools</li>'));
    expect(page, contains('<li>flutter</li>'));
    expect(page, contains('<span class="tag">Flutter</span>'));
  });

  test('pages through the packages and searches them by name', () async {
    final metaStore = MemoryMetaStore();
    for (var index = 0; index < 25; index++) {
      final name = 'package_${'$index'.padLeft(2, '0')}';
      await metaStore.addVersion(
        name,
        unpub.UnpubVersion(
          '1.0.0',
          {'name': name, 'version': '1.0.0'},
          null,
          'publisher@example.com',
          null,
          null,
          DateTime.utc(2026, 1, 2),
        ),
      );
    }
    final browser = _Browser(unpub.App(metaStore: metaStore, packageStore: unpub.FileStore(Directory.systemTemp.path)));

    final second = await browser.read('/packages?page=1');
    final pastTheEnd = await browser.read('/packages?page=7');
    final search = await browser.read('/packages?q=package_2');

    expect(second, contains('Page 2 of 3'));
    expect(second, contains('<a href="/packages" rel="prev">'));
    expect(second, contains('<a href="/packages?page=2" rel="next">'));
    expect(second, contains('>package_10</a>'));
    expect(second, isNot(contains('>package_00</a>')));
    expect(pastTheEnd, contains('No packages found.'));
    expect(pastTheEnd, contains('<a href="/packages?page=2" rel="prev">'));
    expect(pastTheEnd, isNot(contains('Page 8')));
    expect(search, contains('Packages matching “package_2”'));
    expect(search, contains('>package_24</a>'));
    expect(search, isNot(contains('>package_10</a>')));
  });
}
