import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:unpub/unpub.dart' as unpub;

void main() {
  test('keeps an uploaded archive as a file and gives it back', () async {
    final directory = await Directory.systemTemp.createTemp('unpub_file_store');
    addTearDown(() => directory.delete(recursive: true));
    final store = unpub.FileStore(directory.path);
    final archive = [0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03];

    await store.upload('test_package', '1.0.0', archive);
    final downloaded = await store.download('test_package', '1.0.0');

    expect(File(path.join(directory.path, 'test_package-1.0.0.tar.gz')).existsSync(), isTrue);
    expect(downloaded, isA<unpub.ArchiveFound>());
    expect(await (downloaded as unpub.ArchiveFound).bytes.expand((chunk) => chunk).toList(), archive);
  });

  test('answers missing for an archive it does not have', () async {
    final directory = await Directory.systemTemp.createTemp('unpub_file_store');
    addTearDown(() => directory.delete(recursive: true));

    final downloaded = await unpub.FileStore(directory.path).download('test_package', '1.0.0');

    expect(downloaded, isA<unpub.ArchiveMissing>());
  });
}
