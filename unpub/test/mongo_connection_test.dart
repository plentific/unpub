import 'dart:io';
import 'dart:typed_data';

import 'package:mongo_dart/mongo_dart.dart';
import 'package:test/test.dart';
import 'package:unpub/unpub.dart' as unpub;

/// A server that answers as Amazon DocumentDB 3.6 did, which has no sessions:
/// its hello reply leaves logicalSessionTimeoutMinutes out.
final class _SessionlessServer {
  final ServerSocket _socket;

  _SessionlessServer(this._socket);

  int get port => _socket.port;

  /// Answers the first client until it disconnects: hello as a primary
  /// without sessions, every other command with ok.
  Future<void> serve() async {
    final client = await _socket.first;
    final received = BytesBuilder();
    await for (final chunk in client) {
      received.add(chunk);
      var bytes = received.takeBytes();
      while (bytes.length >= 16 && bytes.length >= _length(bytes)) {
        client.add(_answer(Uint8List.sublistView(bytes, 0, _length(bytes))));
        bytes = Uint8List.sublistView(bytes, _length(bytes));
      }
      received.add(bytes);
    }
  }

  int _length(Uint8List message) => ByteData.sublistView(message).getInt32(0, Endian.little);

  /// An OP_MSG answer to an OP_MSG request: header, flag bits, then one body
  /// section.
  List<int> _answer(Uint8List request) {
    final command = BsonCodec.deserialize(BsonBinary.from(request.sublist(21))).keys.first;
    final body = BsonCodec.serialize(switch (command) {
      'hello' => {
        'isWritablePrimary': true,
        'maxBsonObjectSize': 16777216,
        'maxMessageSizeBytes': 48000000,
        'maxWriteBatchSize': 100000,
        'localTime': DateTime.now().toUtc(),
        'minWireVersion': 0,
        'maxWireVersion': 6,
        'ok': 1.0,
      },
      _ => {'ok': 1.0},
    }).byteList;
    final header = ByteData(21);
    header.setInt32(0, 21 + body.length, Endian.little); // message length
    header.setInt32(4, 1, Endian.little); // request id
    header.setInt32(8, ByteData.sublistView(request).getInt32(4, Endian.little), Endian.little); // response to
    header.setInt32(12, 2013, Endian.little); // OP_MSG
    header.setUint32(16, 0, Endian.little); // flag bits
    header.setUint8(20, 0); // body section
    return [...header.buffer.asUint8List(), ...body];
  }

  Future<void> close() => _socket.close();
}

void main() {
  // mongo_dart from pub.dev fails this with a type error until a release
  // includes mongo-dart/mongo_dart#408; the Plentific fork has it.
  test('connects to a server that leaves logicalSessionTimeoutMinutes out of its hello', () async {
    final server = _SessionlessServer(await ServerSocket.bind('127.0.0.1', 0));
    addTearDown(server.close);
    final connection = unpub.DbConnection(
      db: Db('mongodb://127.0.0.1:${server.port}/unpub'),
      transport: const unpub.PlainTransport(),
    );
    final serving = server.serve();

    await connection.open();

    expect(connection.isConnected, isTrue);
    await connection.close();
    await serving;
  });
}
