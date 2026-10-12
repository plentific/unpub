import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:unpub/unpub.dart' as unpub;

void main() {
  test('unpacks data that fits in the limit', () {
    final data = Uint8List.fromList([for (var i = 0; i < 300000; i++) i * 7 % 251]);

    final unpacked = unpub.BoundedGunzip(limit: data.length).unpack(Uint8List.fromList(gzip.encode(data)));

    expect(unpacked, isA<unpub.GunzippedBytes>().having((unpacked) => unpacked.bytes, 'bytes', data));
  });

  test('stops unpacking soon after the output goes past the limit', () {
    // 64 MB of zeros packs into about 64 KB. dart:io's gzip decoder would
    // unpack all of it before a check on its output could stop it.
    final bomb = Uint8List.fromList(gzip.encode(Uint8List(64 * 1024 * 1024)));
    const limit = 1024 * 1024;

    final unpacked = const unpub.BoundedGunzip(limit: limit).unpack(bomb);

    expect(
      unpacked,
      isA<unpub.GunzippedTooLarge>()
          .having((unpacked) => unpacked.limit, 'limit', limit)
          .having((unpacked) => unpacked.unpackedBytes, 'unpackedBytes', lessThan(2 * limit)),
    );
  });

  test('throws for data that is not gzip', () {
    expect(
      () => const unpub.BoundedGunzip(limit: 1024).unpack(Uint8List.fromList('name: not_an_archive\n'.codeUnits)),
      throwsA(anything),
    );
  });
}
