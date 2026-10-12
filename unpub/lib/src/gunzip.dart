import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// What [BoundedGunzip.unpack] gave.
sealed class Gunzipped {
  const Gunzipped();
}

/// All of the unpacked bytes, within the limit.
final class GunzippedBytes extends Gunzipped {
  final Uint8List bytes;

  const GunzippedBytes(this.bytes);
}

/// The data unpacks to more than [limit] bytes. Unpacking stopped once the
/// output went past it, after [unpackedBytes].
final class GunzippedTooLarge extends Gunzipped {
  final int limit;
  final int unpackedBytes;

  const GunzippedTooLarge({required this.limit, required this.unpackedBytes});
}

/// Unpacks gzip data a slice at a time and stops as soon as the output goes
/// past a limit. dart:io's gzip decoder unpacks a whole chunk before anything
/// reads its output, so with it a small but highly compressed upload would
/// fill the memory before the limit is checked.
final class BoundedGunzip {
  static const _slice = 64 * 1024;

  final int _limit;

  const BoundedGunzip({required this._limit});

  /// Data that is not gzip throws, as with [gzip.decode].
  Gunzipped unpack(Uint8List gzipped) {
    final filter = RawZLibFilter.inflateFilter();
    final unpacked = BytesBuilder(copy: false);
    for (var start = 0; start < gzipped.length; start += _slice) {
      filter.process(gzipped, start, min(start + _slice, gzipped.length));
      if (!_drain(filter, unpacked, end: false)) {
        return GunzippedTooLarge(limit: _limit, unpackedBytes: unpacked.length);
      }
    }
    if (!_drain(filter, unpacked, end: true)) {
      return GunzippedTooLarge(limit: _limit, unpackedBytes: unpacked.length);
    }
    return GunzippedBytes(unpacked.takeBytes());
  }

  /// Adds what [filter] unpacked to [unpacked], taking it out as dart:io's
  /// own decoder does: without flushing while more input follows, and to the
  /// end once none does. False once [unpacked] went past the limit.
  bool _drain(RawZLibFilter filter, BytesBuilder unpacked, {required bool end}) {
    for (var chunk = _next(filter, end: end); chunk != null; chunk = _next(filter, end: end)) {
      unpacked.add(chunk);
      if (unpacked.length > _limit) return false;
    }
    return true;
  }

  List<int>? _next(RawZLibFilter filter, {required bool end}) =>
      end ? filter.processed(end: true) : filter.processed(flush: false);
}
