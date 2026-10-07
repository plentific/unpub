import 'dart:io';
import 'package:http_multi_server/http_multi_server.dart';
import 'package:path/path.dart' as path;

class Utils {
  static final credentialsFilePath = path.join(Utils.dartConfigDir, r'unpub-credentials.json');

  /// The location for dart-specific configuration.
  static final String dartConfigDir = () {
    String? configDir;
    if (Platform.isLinux) {
      configDir = Platform.environment['XDG_CONFIG_HOME'] ?? path.join(Platform.environment['HOME']!, '.config');
    } else if (Platform.isWindows) {
      configDir = Platform.environment['APPDATA']!;
    } else if (Platform.isMacOS) {
      configDir = path.join(Platform.environment['HOME']!, 'Library', 'Application Support');
    } else {
      configDir = path.join(Platform.environment['HOME'] ?? '', '.config');
    }
    final p = path.join(configDir, r'unpub-auth');
    Directory(p).createSync();
    return p;
  }();

  static Future<HttpServer> bindServer(String host, int port) async {
    var server = host == 'localhost' ? await HttpMultiServer.loopback(port) : await HttpServer.bind(host, port);
    server.autoCompress = true;
    return server;
  }

  static Map<String, String> queryToMap(String queryList) {
    var map = <String, String>{};
    for (var pair in queryList.split('&')) {
      var split = _split(pair, '=');
      if (split.isEmpty) continue;
      var key = _urlDecode(split[0]);
      var value = split.length > 1 ? _urlDecode(split[1]) : '';
      map[key] = value;
    }
    return map;
  }

  static String _urlDecode(String encoded) => Uri.decodeComponent(encoded.replaceAll('+', ' '));

  static List<String> _split(String toSplit, String pattern) {
    if (toSplit.isEmpty) return <String>[];

    var index = toSplit.indexOf(pattern);
    if (index == -1) return [toSplit];
    return [toSplit.substring(0, index), toSplit.substring(index + pattern.length)];
  }

  static void stdoutPrint(Object? object) => stdout.write(object);
}
