import 'dart:convert';
import 'dart:math' show max, min;

import 'package:pub_semver/pub_semver.dart' as semver;
import 'package:unpub/src/models.dart';
import 'package:unpub/src/utils.dart';
import 'package:unpub/src/version_docs.dart';
import 'package:unpub/src/web/markdown_renderer.dart';
import 'package:unpub/src/web/plentific_brand.dart';

/// The sections of a package page.
enum PackageTab { readme, changelog, versions }

/// The web UI's pages, rendered on the server in Plentific's look: its logo,
/// and the colours and font of the Plentific dashboard's design tokens. They
/// need no JavaScript, and every value that comes from a package is escaped,
/// or sanitized when it is Markdown.
final class WebPages {
  /// The logo's mark as the pages' icon, so browsers ask for no favicon.ico.
  static final _icon = Uri.dataFromString(plentificMark, mimeType: 'image/svg+xml').toString();

  final MarkdownRenderer _markdown;

  const WebPages({required this._markdown});

  /// The packages, most downloaded first, or those matching [query].
  String packageList({
    required UnpubQueryResult result,
    required String? query,
    required int page,
    required int pageSize,
  }) {
    final heading = switch (query) {
      null || '' => 'Packages',
      final query => 'Packages matching “${_text(query)}”',
    };
    final items = [for (final package in result.packages) _packageListItem(package)];
    return _layout(
      title: 'Packages',
      query: query,
      body:
          '<h1>$heading</h1>\n'
          '<p class="meta">${result.count} ${result.count == 1 ? 'package' : 'packages'}</p>\n'
          '${items.isEmpty ? '<p class="empty">No packages found.</p>' : '<ul class="packages">${items.join()}</ul>'}\n'
          '${_pagination(query: query, page: page, pages: (result.count / pageSize).ceil())}',
    );
  }

  /// A version of a package, with one of its tabs open. [server] is the URL
  /// that clients reach this server at, for the dependency snippet.
  String packagePage({
    required UnpubPackage package,
    required UnpubVersion version,
    required VersionDocs docs,
    required PackageTab tab,
    required Uri server,
  }) {
    final latest = latestVersion(package);
    final isLatest = version.version == latest.version;
    final path = isLatest ? _packagePath(package.name) : _versionPath(package.name, version.version);
    final tabs = [
      for (final candidate in PackageTab.values)
        '<a href="${_attr('$path?tab=${candidate.name}')}"${candidate == tab ? ' aria-current="page"' : ''}>'
            '${_tabLabel(candidate)}</a>',
    ];
    final content = switch (tab) {
      PackageTab.readme => _markdownSection(docs.readme, 'This version has no README.'),
      PackageTab.changelog => _markdownSection(docs.changelog, 'This version has no CHANGELOG.'),
      PackageTab.versions => _versionsTable(package),
    };
    final uploaders = switch (package.uploaders) {
      null => const <String>[],
      final uploaders => uploaders,
    };
    return _layout(
      title: '${package.name} ${version.version}',
      query: null,
      body:
          '''
<div class="package-header">
  <h1>${_text(package.name)} <span class="version">${_text(version.version)}</span>${_flutterTag(version.pubspec)}</h1>
  <p class="meta">Published ${_date(version.createdAt)} · ${_downloads(package.download)}</p>
  ${_versionNotice(package.name, version: version, latest: latest)}
</div>
<div class="package">
  <div class="package-main">
    <nav class="tabs" aria-label="Package">${tabs.join()}</nav>
    $content
  </div>
  <aside>
    <h2>Use it</h2>
    <pre><code>${_text(_dependencySnippet(package.name, version.version, server))}</code></pre>
    <h2>About</h2>
    ${_about(version.pubspec)}
    <h2>Uploaders</h2>
    ${_list([for (final uploader in uploaders) _text(uploader)])}
    <h2>Dependencies</h2>
    ${_dependencies(version.pubspec, server)}
  </aside>
</div>''',
    );
  }

  /// The page for a package or version this server does not have.
  String notFound(String message) => _layout(
    title: 'Not found',
    query: null,
    body: '<h1>Not found</h1>\n<p>${_text(message)}</p>\n<p><a href="/">All packages</a></p>',
  );

  String _packageListItem(UnpubPackage package) {
    final latest = latestVersion(package);
    final description = latest.pubspec['description'];
    return '<li>'
        '<h2><a href="${_attr(_packagePath(package.name))}">${_text(package.name)}</a> '
        '<span class="version">${_text(latest.version)}</span>${_flutterTag(latest.pubspec)}</h2>'
        '${description is String ? '<p>${_text(description)}</p>' : ''}'
        '<p class="meta">Updated ${_date(package.updatedAt)}</p>'
        '</li>';
  }

  /// Says when a page shows a version other than the one `dart pub add`
  /// picks: an older one, or a pre-release newer than the latest stable one.
  String _versionNotice(String name, {required UnpubVersion version, required UnpubVersion latest}) {
    if (version.version == latest.version) return '';
    final link = '<a href="${_attr(_packagePath(name))}">${_text(latest.version)}</a>';
    return semver.Version.parse(version.version) > semver.Version.parse(latest.version)
        ? '<p class="notice">This is a pre-release. The latest stable version is $link.</p>'
        : '<p class="notice">This is an older version. The latest is $link.</p>';
  }

  String _tabLabel(PackageTab tab) => switch (tab) {
    PackageTab.readme => 'README',
    PackageTab.changelog => 'Changelog',
    PackageTab.versions => 'Versions',
  };

  String _markdownSection(String? source, String empty) => switch (source) {
    null || '' => '<p class="empty">${_text(empty)}</p>',
    final source => '<article class="markdown">${_markdown.toHtml(source)}</article>',
  };

  String _versionsTable(UnpubPackage package) {
    final versions = List.of(package.versions);
    versions.sort((a, b) => semver.Version.parse(b.version).compareTo(semver.Version.parse(a.version)));
    final rows = [
      for (final version in versions)
        '<tr>'
            '<td><a href="${_attr(_versionPath(package.name, version.version))}">${_text(version.version)}</a></td>'
            '<td>${_date(version.createdAt)}</td>'
            '<td><a href="${_attr(_archivePath(package.name, version.version))}">Download</a></td>'
            '</tr>',
    ];
    return '<table class="versions"><thead><tr><th>Version</th><th>Published</th><th>Archive</th></tr></thead>'
        '<tbody>${rows.join()}</tbody></table>';
  }

  String _dependencySnippet(String name, String version, Uri server) =>
      'dependencies:\n  $name:\n    hosted: ${server.origin}\n    version: ^$version';

  String _about(Map<String, dynamic> pubspec) {
    final description = pubspec['description'];
    final links = [
      for (final (key, label) in [
        ('homepage', 'Homepage'),
        ('repository', 'Repository'),
        ('issue_tracker', 'Issues'),
        ('documentation', 'Documentation'),
      ])
        if (_webLink(pubspec[key]) case final url?) '<a href="${_attr(url)}" rel="noopener noreferrer">$label</a>',
    ];
    return '${description is String ? '<p>${_text(description)}</p>' : ''}'
        '${links.isEmpty ? '' : '<p class="links">${links.join(' · ')}</p>'}';
  }

  /// An http(s) URL from a pubspec. Anything else, a `javascript:` URL
  /// included, is not linked.
  String? _webLink(Object? value) {
    if (value is! String) return null;
    final uri = Uri.tryParse(value);
    return uri != null && (uri.isScheme('http') || uri.isScheme('https')) ? value : null;
  }

  String _dependencies(Map<String, dynamic> pubspec, Uri server) => switch (pubspec['dependencies']) {
    final Map dependencies when dependencies.isNotEmpty => _list([
      for (final MapEntry(:key, :value) in dependencies.entries) _dependencyLink('$key', value, server),
    ]),
    _ => '<p class="empty">None</p>',
  };

  /// A dependency hosted on this server links to its page here, and one from
  /// the default server to pub.dev. SDK, path and git dependencies, and those
  /// hosted elsewhere, are not linked.
  String _dependencyLink(String name, Object? source, Uri server) => switch (source) {
    {'hosted': final Object? hosted} when _isServer(hosted, server) =>
      '<a href="${_attr(_packagePath(name))}">${_text(name)}</a>',
    {'hosted': _} || {'sdk': _} || {'path': _} || {'git': _} => _text(name),
    null ||
    String() ||
    Map() => '<a href="${_attr('https://pub.dev/packages/${Uri.encodeComponent(name)}')}">${_text(name)}</a>',
    _ => _text(name),
  };

  /// Whether a `hosted` URL names this server's host. The scheme and port
  /// are not compared, as a proxy in front of the server may change them.
  bool _isServer(Object? hosted, Uri server) => switch (hosted) {
    final String url => Uri.tryParse(url)?.host == server.host,
    {'url': final String url} => Uri.tryParse(url)?.host == server.host,
    _ => false,
  };

  String _list(List<String> items) =>
      items.isEmpty ? '<p class="empty">None</p>' : '<ul>${[for (final item in items) '<li>$item</li>'].join()}</ul>';

  String _pagination({required String? query, required int page, required int pages}) {
    if (page == 0 && pages <= 1) return '';
    // A page past the end, from an edited address, leads back to the last one.
    final previous = page > 0
        ? '<a href="${_attr(_listPath(query, max(min(page, pages) - 1, 0)))}" rel="prev">Previous</a>'
        : '';
    final position = page < pages ? '<span>Page ${page + 1} of $pages</span>' : '';
    final next = page + 1 < pages ? '<a href="${_attr(_listPath(query, page + 1))}" rel="next">Next</a>' : '';
    return '<nav class="pagination" aria-label="Pages">$previous$position$next</nav>';
  }

  String _listPath(String? query, int page) {
    final parameters = {if (query != null && query.isNotEmpty) 'q': query, if (page > 0) 'page': '$page'};
    return Uri(path: '/packages', queryParameters: parameters.isEmpty ? null : parameters).toString();
  }

  String _packagePath(String name) => '/packages/$name';

  String _versionPath(String name, String version) => '/packages/$name/versions/$version';

  /// The same archive URL the pub API gives `dart pub`.
  String _archivePath(String name, String version) => '/packages/$name/versions/$version.tar.gz';

  String _flutterTag(Map<String, dynamic> pubspec) =>
      isFlutterPackage(pubspec) ? ' <span class="tag">Flutter</span>' : '';

  String _downloads(int? downloads) => switch (downloads) {
    null || 0 => 'no downloads yet',
    1 => '1 download',
    final downloads => '$downloads downloads',
  };

  String _date(DateTime time) {
    final utc = time.toUtc();
    return '${utc.year}-${'${utc.month}'.padLeft(2, '0')}-${'${utc.day}'.padLeft(2, '0')}';
  }

  String _text(String value) => const HtmlEscape(HtmlEscapeMode.element).convert(value);

  String _attr(String value) => const HtmlEscape(HtmlEscapeMode.attribute).convert(value);

  String _layout({required String title, required String? query, required String body}) {
    final search = switch (query) {
      null => '',
      final query => query,
    };
    return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${_text(title)} · unpub</title>
<link rel="icon" href="${_attr(_icon)}">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Figtree:wght@400..700&amp;display=swap">
<style>$_styles</style>
</head>
<body>
<header class="site">
  <div class="bar">
    <a class="brand" href="/">$plentificLogo<span>unpub</span></a>
    <form action="/packages" method="get" role="search">
      <input type="search" name="q" value="${_attr(search)}" placeholder="Search packages" aria-label="Search packages">
      <button type="submit">Search</button>
    </form>
  </div>
</header>
<main>
$body
</main>
<footer class="site"><a href="https://github.com/plentific/unpub">Source</a></footer>
</body>
</html>
''';
  }

  /// Colours from the neutral and client brand palettes of the Plentific
  /// dashboard's design tokens, light and dark, and its Figtree font.
  static const _styles = r'''
:root {
  color-scheme: light dark;
  --bg: #fff; --fg: #1c293b; --muted: #647287; --line: #e2e5ea; --panel: #f7f8f9; --code: #f0f2f4;
  --link: #0055cc; --brand-soft: #edf4fd; --brand-line: #bdd6f7; --button: #0055cc; --button-hover: #004bb2;
  --header: #0d1726; --header-line: #0d1726; --field: #fff; --field-fg: #1c293b; --field-line: #fff;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #0d1726; --fg: #f0f2f4; --muted: #9aa5b5; --line: #222f42; --panel: #131e2e; --code: #172334;
    --link: #4391ff; --brand-soft: #122643; --brand-line: #1d4784; --button: #2662b8; --button-hover: #2868c3;
    --header: #131e2e; --header-line: #222f42; --field: #172334; --field-fg: #f0f2f4; --field-line: #394960;
  }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--fg); font: 16px/1.5 Figtree, "open-sans", Arial, sans-serif; }
a { color: var(--link); text-decoration: none; }
a:hover { text-decoration: underline; }
header.site { background: var(--header); border-bottom: 1px solid var(--header-line); padding: 12px 16px; }
header.site .bar { max-width: 1120px; margin: 0 auto; display: flex; flex-wrap: wrap; gap: 12px 24px; align-items: center; }
.brand { display: flex; align-items: center; gap: 12px; color: #fff; font-size: 18px; font-weight: 600; }
.brand:hover { text-decoration: none; }
.brand .logo { display: block; width: 119px; height: 28px; }
.brand span { padding-left: 12px; border-left: 1px solid #ffffff4d; line-height: 24px; }
header.site form { flex: 1 1 320px; min-width: 0; display: flex; gap: 8px; }
header.site input { flex: 1; min-width: 0; padding: 8px 12px; border: 1px solid var(--field-line); border-radius: 8px; background: var(--field); color: var(--field-fg); font: inherit; }
button { padding: 8px 16px; border: 0; border-radius: 8px; background: var(--button); color: #fff; font: inherit; font-weight: 600; cursor: pointer; }
button:hover { background: var(--button-hover); }
main { max-width: 1152px; margin: 0 auto; padding: 32px 16px 48px; }
h1 { font-size: 28px; font-weight: 700; margin: 0 0 4px; overflow-wrap: anywhere; }
.meta { color: var(--muted); margin: 0 0 16px; font-size: 14px; }
.version { color: var(--muted); font-weight: 400; }
.tag { display: inline-block; font-size: 12px; font-weight: 600; padding: 2px 8px; border-radius: 999px; background: var(--brand-soft); color: var(--link); vertical-align: middle; }
.empty { color: var(--muted); }
.notice { background: var(--brand-soft); border: 1px solid var(--brand-line); border-radius: 8px; padding: 8px 12px; }
ul.packages { list-style: none; padding: 0; margin: 0; }
ul.packages li { padding: 16px 0; border-bottom: 1px solid var(--line); }
ul.packages h2 { font-size: 20px; font-weight: 600; margin: 0 0 4px; }
ul.packages p { margin: 0 0 4px; }
.pagination { display: flex; gap: 16px; align-items: center; justify-content: center; margin-top: 24px; }
.package { display: grid; grid-template-columns: minmax(0, 1fr) 300px; gap: 32px; margin-top: 16px; }
@media (max-width: 800px) { .package { grid-template-columns: minmax(0, 1fr); } }
.tabs { display: flex; gap: 4px; border-bottom: 1px solid var(--line); margin-bottom: 16px; }
.tabs a { padding: 8px 12px; color: var(--muted); font-weight: 600; border-bottom: 2px solid transparent; }
.tabs a:hover { color: var(--fg); text-decoration: none; }
.tabs a[aria-current="page"] { color: var(--fg); border-bottom-color: var(--link); }
aside h2 { font-size: 12px; font-weight: 700; text-transform: uppercase; letter-spacing: .05em; color: var(--muted); margin: 24px 0 8px; }
aside h2:first-child { margin-top: 0; }
aside ul { padding-left: 18px; margin: 0; overflow-wrap: anywhere; }
pre { background: var(--code); border: 1px solid var(--line); border-radius: 8px; padding: 12px; overflow-x: auto; font-size: 13px; }
code { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
:not(pre) > code { font-size: .875em; background: var(--code); border-radius: 4px; padding: .1em .3em; }
table.versions { width: 100%; border-collapse: collapse; }
table.versions th, table.versions td { text-align: left; padding: 8px; border-bottom: 1px solid var(--line); }
table.versions th { color: var(--muted); font-size: 14px; }
.markdown { overflow-wrap: anywhere; }
.markdown img { max-width: 100%; }
.markdown table { border-collapse: collapse; }
.markdown th, .markdown td { border: 1px solid var(--line); padding: 4px 8px; }
.markdown blockquote { margin: 0; padding: 0 16px; color: var(--muted); border-left: 4px solid var(--line); }
footer.site { text-align: center; padding: 24px; color: var(--muted); font-size: 14px; border-top: 1px solid var(--line); }
''';
}
