import 'package:pub_semver/pub_semver.dart' as semver;
import 'package:unpub/src/models.dart';
import 'package:yaml/yaml.dart';

convertYaml(dynamic value) {
  if (value is YamlMap) {
    return value.cast<String, dynamic>().map((k, v) => MapEntry(k, convertYaml(v)));
  }
  if (value is YamlList) {
    return value.map((e) => convertYaml(e)).toList();
  }
  return value;
}

Map<String, dynamic>? loadYamlAsMap(dynamic value) {
  var yamlMap = loadYaml(value) as YamlMap?;
  return convertYaml(yamlMap).cast<String, dynamic>();
}

/// Whether a package is for Flutter: it has a `flutter` section or depends
/// on the Flutter SDK.
bool isFlutterPackage(Map<String, dynamic> pubspec) =>
    pubspec['flutter'] != null ||
    switch (pubspec['dependencies']) {
      {'flutter': final Object? _} => true,
      _ => false,
    };

/// The tag shown with a package: "flutter" for a Flutter package, "dart"
/// otherwise.
List<String> getPackageTags(Map<String, dynamic> pubspec) => isFlutterPackage(pubspec) ? ['flutter'] : ['dart'];

/// The newest version of a package, preferring stable releases to
/// pre-releases.
UnpubVersion latestVersion(UnpubPackage package) {
  var latest = semver.Version.primary([for (var version in package.versions) semver.Version.parse(version.version)]);
  return package.versions.lastWhere((version) => semver.Version.parse(version.version) == latest);
}
