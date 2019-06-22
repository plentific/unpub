import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:http/http.dart' as http;
import 'package:googleapis/oauth2/v2.dart';
import 'package:mime/mime.dart';
import 'package:http_parser/http_parser.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:pub_semver/pub_semver.dart' as semver;
import 'package:unpub/src/api/models.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:yaml/yaml.dart';
import 'package:archive/archive.dart';
import 'package:unpub/src/models.dart';
import 'package:unpub/src/meta_store.dart';
import 'package:unpub/src/package_store.dart';
import 'static/index.html.dart' as index_html;
import 'static/main.dart.js.dart' as main_dart_js;
import 'static/styles.css.dart' as styles_css;

part 'app.g.dart';

shelf.Response _ok(Map<String, dynamic> data, {int status = 200}) =>
    shelf.Response(status, body: json.encode(data), headers: {
      HttpHeaders.contentTypeHeader: ContentType.json.mimeType,
      'Access-Control-Allow-Origin': '*'
    });

shelf.Response _successMessage(String message, {int status = 200}) => _ok({
      'success': {'message': message}
    }, status: status);

shelf.Response _badRequest(String message, {int status = 400}) =>
    shelf.Response(status,
        body: json.encode({
          'error': {'message': message}
        }),
        headers: {HttpHeaders.contentTypeHeader: ContentType.json.mimeType});

class App {
  static var _httpClient = http.Client();

  final MetaStore metaStore;
  final PackageStore packageStore;
  final String proxyUrl;
  final Future<String> Function(String token) uploaderEmailGetter;
  final Future<void> Function(dynamic pubspecJson, String email)
      uploadValidator;

  static Future<String> defaultUploaderEmailGetter(String token) async {
    var info = await Oauth2Api(_httpClient).tokeninfo(accessToken: token);
    if (info == null) return null;
    return info.email;
  }

  static Future<void> defaultUploadValidator(_, __) async {}

  App({
    this.metaStore,
    this.packageStore,
    this.proxyUrl = 'https://pub.dev',
    this.uploaderEmailGetter = defaultUploaderEmailGetter,
    this.uploadValidator = defaultUploadValidator,
  });

  Future<HttpServer> serve([String host = '0.0.0.0', int port = 4000]) async {
    var handler = const shelf.Pipeline()
        .addMiddleware(shelf.logRequests())
        .addHandler((req) async {
      // Return 404 by default
      // https://github.com/google/dart-neats/issues/1
      var res = await router.handler(req);
      if (res == null) {
        return shelf.Response.notFound('Not found');
      } else {
        return res;
      }
    });
    var server = await shelf_io.serve(handler, host, port);
    return server;
  }

  Future<String> _getUploaderEmail(shelf.Request req) async {
    var authHeader = req.headers[HttpHeaders.authorizationHeader];
    if (authHeader == null) {
      throw 'No auth';
    }

    var token = authHeader.split(' ').last;
    var email = await uploaderEmailGetter(token);
    return email;
  }

  Map<String, dynamic> _versionToJson(UnpubVersion item, Uri baseUri) {
    var name = item.pubspec['name'] as String;
    var version = item.version;
    return {
      'archive_url': baseUri
          .resolve('/packages/$name/versions/$version.tar.gz')
          .toString(),
      'pubspec': item.pubspec,
      'version': version,
    };
  }

  bool isPubClient(shelf.Request req) {
    var ua = req.headers[HttpHeaders.userAgentHeader];
    return ua != null && ua.toLowerCase().contains('dart pub');
  }

  Router get router => _$AppRouter(this);

  @Route.get('/api/packages/<name>')
  Future<shelf.Response> getVersions(shelf.Request req, String name) async {
    var versions = await metaStore.getAllVersions(name).toList();

    if (versions.isEmpty) {
      var res = await _httpClient.send(http.Request(
          'GET', Uri.parse(proxyUrl).resolve('/api/packages/$name')));
      return shelf.Response(res.statusCode,
          headers: {HttpHeaders.contentTypeHeader: ContentType.json.mimeType},
          body: res.stream);
    }

    versions.sort((a, b) {
      return semver.Version.prioritize(
          semver.Version.parse(a.version), semver.Version.parse(b.version));
    });

    var versionMaps =
        versions.map((item) => _versionToJson(item, req.requestedUri)).toList();

    return _ok({
      'name': name,
      'latest': versionMaps.last,
      'versions': versionMaps,
    });
  }

  @Route.get('/api/packages/<name>/versions/<version>')
  Future<shelf.Response> getVersion(
      shelf.Request req, String name, String version) async {
    // Important: + -> %2B, should be decoded here
    try {
      version = Uri.decodeComponent(version);
    } catch (err) {
      print(err);
    }

    var item = await metaStore.getVersion(name, version);

    if (item == null) {
      var res = await _httpClient.send(http.Request(
          'GET',
          Uri.parse(proxyUrl)
              .resolve('/api/packages/$name/versions/$version')));
      return shelf.Response(res.statusCode,
          headers: {HttpHeaders.contentTypeHeader: ContentType.json.mimeType},
          body: res.stream);
    }

    return _ok(_versionToJson(item, req.requestedUri));
  }

  @Route.get('/packages/<name>/versions/<version>.tar.gz')
  Future<shelf.Response> download(
      shelf.Request req, String name, String version) async {
    var item = await metaStore.getVersion(name, version);

    Stream<List<int>> stream;

    if (item == null) {
      var res = await _httpClient.send(http.Request(
          'GET',
          Uri.parse(proxyUrl)
              .resolve('/packages/$name/versions/$version.tar.gz')));
      stream = res.stream;
    } else {
      if (isPubClient(req)) {
        metaStore.increaseDownloadCount(name);
      }
      stream = packageStore.download(name, version);
    }

    return shelf.Response(200,
        headers: {HttpHeaders.contentTypeHeader: ContentType.binary.mimeType},
        body: stream);
  }

  @Route.get('/api/packages/versions/new')
  Future<shelf.Response> getUploadUrl(shelf.Request req) async {
    return _ok({
      'url': req.requestedUri
          .resolve('/api/packages/versions/newUpload')
          .toString(),
      'fields': {},
    });
  }

  @Route.post('/api/packages/versions/newUpload')
  Future<shelf.Response> upload(shelf.Request req) async {
    try {
      var email = await _getUploaderEmail(req);

      var mediaType = MediaType.parse(req.headers['content-type']);

      var boundary = mediaType.parameters['boundary'];
      MimeMultipart fileData;

      await for (MimeMultipart part
          in req.read().transform(MimeMultipartTransformer(boundary))) {
        if (fileData != null) continue;
        fileData = part;
      }

      var bb = await fileData.fold(
          BytesBuilder(), (BytesBuilder byteBuilder, d) => byteBuilder..add(d));
      var tarballBytes = bb.takeBytes();
      var tarBytes = GZipDecoder().decodeBytes(tarballBytes);
      var archive = TarDecoder().decodeBytes(tarBytes);
      ArchiveFile pubspecArchiveFile;
      ArchiveFile readmeFile;
      ArchiveFile changelogFile;

      for (var file in archive.files) {
        if (file.name == 'pubspec.yaml') {
          pubspecArchiveFile = file;
          continue;
        }
        if (file.name.toLowerCase() == 'readme.md') {
          readmeFile = file;
          continue;
        }
        if (file.name.toLowerCase() == 'changelog.md') {
          changelogFile = file;
          continue;
        }
      }

      if (pubspecArchiveFile == null) {
        throw 'Did not find any pubspec.yaml file in upload. Aborting.';
      }

      var pubspecYaml = utf8.decode(pubspecArchiveFile.content);
      // TODO: Error handling.
      var pubspec = loadYaml(pubspecYaml);

      // Validator
      await uploadValidator(pubspec, email);

      var name = pubspec['name'] as String;
      var version = pubspec['version'] as String;

      var duplicatedVersion = await metaStore.getAllVersions(name).firstWhere(
            (item) => version == item.version,
            orElse: () => null,
          );

      if (duplicatedVersion != null) {
        throw 'version invalid: $name@$version already exists.';
      }

      var packageEmpty = await metaStore.getAllVersions(name).isEmpty;
      if (!packageEmpty) {
        var uploaders = await metaStore.getUploaders(name).toList();
        if (!uploaders.contains(email)) {
          throw 'UnauthorizedAccess';
        }
      }

      // Upload package tar to storage
      await packageStore.upload(name, version, tarballBytes);

      String readme;
      String changelog;
      if (readmeFile != null) {
        readme = utf8.decode(readmeFile.content);
      }
      if (changelogFile != null) {
        changelog = utf8.decode(changelogFile.content);
      }
      // Write package meta to database
      await metaStore.addVersion(name,
          UnpubVersion.fromTarball(pubspecYaml, readme, changelog), email);

      // TODO: Upload docs
      return shelf.Response.found(req.requestedUri
          .resolve('/api/packages/versions/newUploadFinish')
          .toString());
    } catch (err) {
      return shelf.Response.found(req.requestedUri
          .resolve('/api/packages/versions/newUploadFinish?error=$err'));
    }
  }

  @Route.get('/api/packages/versions/newUploadFinish')
  Future<shelf.Response> uploadFinish(shelf.Request req) async {
    var error = req.requestedUri.queryParameters['error'];
    if (error != null) {
      return _badRequest(error);
    }
    return _successMessage('Successfully uploaded package.');
  }

  @Route.post('/api/packages/<name>/uploaders')
  Future<shelf.Response> addUploader(shelf.Request req, String name) async {
    var body = await req.readAsString();
    var email = Uri.splitQueryString(body)['email'];
    var operatorEmail = await _getUploaderEmail(req);
    var uploaders = await metaStore.getUploaders(name).toList();

    if (!uploaders.contains(operatorEmail)) {
      return _badRequest('no permission', status: 403);
    }
    if (uploaders.contains(email)) {
      return _badRequest('email already exists');
    }

    await metaStore.addUploader(name, email);
    return _successMessage('uploader added');
  }

  @Route.delete('/api/packages/<name>/uploaders/<email>')
  Future<shelf.Response> removeUploader(
      shelf.Request req, String name, String email) async {
    email = Uri.decodeComponent(email);
    var operatorEmail = await _getUploaderEmail(req);
    var uploaders = await metaStore.getUploaders(name).toList();

    if (!uploaders.contains(operatorEmail)) {
      return _badRequest('no permission', status: 403);
    }
    if (!uploaders.contains(email)) {
      return _badRequest('email not uploader');
    }

    await metaStore.removeUploader(name, email);
    return _successMessage('uploader removed');
  }

  @Route.get('/webapi/top')
  Future<shelf.Response> getTopPackages(shelf.Request req) async {
    var packageNames = await metaStore.db
        .collection(statsCollection)
        .find(where.limit(15).sortBy('download', descending: true))
        .map((item) => item['name'] as String)
        .toList();

    var map = packageNames.asMap().map((key, value) => MapEntry(value, key));

    var packages = await metaStore.db.collection(packageCollection).find({
      '\$or': packageNames.map((name) => {'name': name}).toList()
    }).map((item) {
      var versions = item['versions'] as List;
      List<String> tags = ['flutter', 'web', 'other'];
      if (versions.last['pubspec']['flutter'] != null) {
        tags = ['flutter'];
      }

      return PackageView(
        item['name'] as String,
        versions.last['pubspec']['description'] as String,
        tags,
        versions.last['version'],
        versions.last['createAt'],
      );
    }).toList();

    packages.sort((a, b) => map[a.name].compareTo(map[b.name]));

    return _ok({
      'data': packages.map((item) => item.toJson()).toList(),
    });
  }

  @Route.get('/webapi/detail/<name>')
  Future<shelf.Response> getPackageDetail(
      shelf.Request req, String name) async {
    var version = req.requestedUri.queryParameters['version'];

    var package = await metaStore.db
        .collection(packageCollection)
        .findOne(where.eq('name', name));
    if (package == null) {
      return _ok({'error': 'package not exists'});
    }

    var versions = (package['versions'] as List);

    var packageVersion = version == null
        ? versions.last
        : versions.firstWhere((item) => item['version'] == version,
            orElse: () => null);

    if (packageVersion == null) {
      return _ok({'error': 'version not exists'});
    }

    var data = DetailView(
      package['name'] as String,
      packageVersion['version'] as String,
      packageVersion['createAt'] as DateTime,
      packageVersion['pubspec'],
      (package['uploaders'] as List).cast<String>(),
      packageVersion['readme'],
      packageVersion['changelog'],
      versions
          .map((item) => DetailViewVersion(
              item['version'] as String, item['createAt'] as DateTime))
          .toList(),
    );

    return _ok({'data': data.toJson()});
  }

  @Route.get('/webapi/search')
  Future<shelf.Response> search(shelf.Request req) async {
    var params = req.requestedUri.queryParameters;
    var q = params['q'];
    var page = int.tryParse(params['page'] ?? '') ?? 1;
    // var sort = params['sort'] ?? 'download';
    var size = int.tryParse(params['size'] ?? '') ?? 10;

    if (q == null || q.isEmpty) {
      return _badRequest('No search keyword provided');
    }

    var packages = await metaStore.db
        .collection(packageCollection)
        .find(where.match('name', '.*$q.*').skip(size * (page - 1)).limit(size)
            // .sortBy('download'),
            )
        .map((package) {
      package.remove('versions');
      return package;
    }).toList();

    return _ok({
      'data': packages,
    });
  }

  @Route.get('/')
  @Route.get('/packages')
  @Route.get('/packages/<name>')
  Future<shelf.Response> indexHtml(shelf.Request req) async {
    return shelf.Response(HttpStatus.ok,
        body: index_html.content,
        headers: {HttpHeaders.contentTypeHeader: ContentType.html.mimeType});
  }

  @Route.get('/main.dart.js')
  Future<shelf.Response> mainDartJs(shelf.Request req) async {
    return shelf.Response(HttpStatus.ok,
        body: main_dart_js.content,
        headers: {HttpHeaders.contentTypeHeader: 'text/javascript'});
  }

  @Route.get('/styles.css')
  Future<shelf.Response> stylesCss(shelf.Request req) async {
    return shelf.Response(HttpStatus.ok,
        body: styles_css.content,
        headers: {HttpHeaders.contentTypeHeader: 'text/css'});
  }
}
