import 'dart:io';
import 'dart:typed_data';

import 'package:mongo_dart/mongo_dart.dart';
import 'package:test/test.dart';
import 'package:unpub/unpub.dart' as unpub;

/// A server that answers the driver's hello as Amazon DocumentDB 3.6 did:
/// a primary, but without logicalSessionTimeoutMinutes, as it has no sessions.
final class _SessionlessServer {
  final ServerSocket _socket;

  _SessionlessServer(this._socket);

  int get port => _socket.port;

  Future<void> answerHello() async {
    final client = await _socket.first;
    final request = BytesBuilder();
    await for (final chunk in client) {
      request.add(chunk);
      final bytes = request.toBytes();
      if (bytes.length >= 16 && bytes.length >= ByteData.sublistView(bytes).getInt32(0, Endian.little)) {
        client.add(_reply(to: ByteData.sublistView(bytes).getInt32(4, Endian.little)));
        await client.flush();
        break;
      }
    }
  }

  /// An OP_MSG reply: header, flag bits, then one body section.
  List<int> _reply({required int to}) {
    final body = BsonCodec.serialize({
      'isWritablePrimary': true,
      'maxBsonObjectSize': 16777216,
      'maxMessageSizeBytes': 48000000,
      'maxWriteBatchSize': 100000,
      'localTime': DateTime.now().toUtc(),
      'minWireVersion': 0,
      'maxWireVersion': 6,
      'ok': 1.0,
    }).byteList;
    final header = ByteData(21);
    header.setInt32(0, 21 + body.length, Endian.little); // message length
    header.setInt32(4, 1, Endian.little); // request id
    header.setInt32(8, to, Endian.little); // response to
    header.setInt32(12, 2013, Endian.little); // OP_MSG
    header.setUint32(16, 0, Endian.little); // flag bits
    header.setUint8(20, 0); // body section
    return [...header.buffer.asUint8List(), ...body];
  }

  Future<void> close() => _socket.close();
}

void main() {
  test('says what is missing when the server leaves logicalSessionTimeoutMinutes out of its hello', () async {
    final server = _SessionlessServer(await ServerSocket.bind('127.0.0.1', 0));
    addTearDown(server.close);
    final connection = unpub.DbConnection(
      db: Db('mongodb://127.0.0.1:${server.port}/unpub'),
      transport: const unpub.PlainTransport(),
    );

    final opened = connection.open();
    await server.answerHello();

    await expectLater(
      opened,
      throwsA(isA<StateError>().having((error) => error.message, 'message', contains('logicalSessionTimeoutMinutes'))),
    );
  });
}
