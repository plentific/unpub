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

/// [version] as a semantic version, or null when it is not one.
semver.Version? parseVersion(String version) {
  try {
    return semver.Version.parse(version);
  } on FormatException {
    return null;
  }
}

/// The newest version of a package, preferring stable releases to
/// pre-releases. A version that is not semantic, which only data from before
/// uploads were checked could hold, is passed over rather than failing the
/// page; a package with no other gives its last version.
UnpubVersion latestVersion(UnpubPackage package) {
  final parsed = [
    for (final version in package.versions)
      if (parseVersion(version.version) case final number?) (number: number, version: version),
  ];
  if (parsed.isEmpty) return package.versions.last;
  final latest = semver.Version.primary([for (final entry in parsed) entry.number]);
  return parsed.lastWhere((entry) => entry.number == latest).version;
}
