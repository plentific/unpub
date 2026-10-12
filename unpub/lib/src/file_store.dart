import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:unpub/src/package_store.dart';

/// Keeps package archives as files in a directory.
final class FileStore implements PackageStore {
  final String _directory;

  FileStore(this._directory);

  @override
  Future<void> upload(String name, String version, List<int> content) async {
    final file = _archive(name, version);
    await file.create(recursive: true);
    await file.writeAsBytes(content);
  }

  @override
  Future<StoredArchive> download(String name, String version) async {
    final file = _archive(name, version);
    return await file.exists() ? ArchiveFound(file.openRead()) : const ArchiveMissing();
  }

  File _archive(String name, String version) => File(path.join(_directory, '$name-$version.tar.gz'));
}
