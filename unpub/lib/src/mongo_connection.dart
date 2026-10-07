import 'package:mongo_dart/mongo_dart.dart';

/// How the connection to the database is made.
sealed class MongoTransport {
  const MongoTransport();
}

/// An unencrypted connection, e.g. to a local MongoDB.
final class PlainTransport extends MongoTransport {
  const PlainTransport();
}

/// TLS, trusting the certificate authorities in [caFile] (e.g. the Amazon
/// DocumentDB bundle), with a client certificate when [certificateKeyFile]
/// is given.
final class TlsTransport extends MongoTransport {
  final String caFile;
  final String? certificateKeyFile;
  final String? certificateKeyFilePassword;

  const TlsTransport({
    required this.caFile,
    required this.certificateKeyFile,
    required this.certificateKeyFilePassword,
  });
}

/// A database client's connection to its server.
abstract interface class MongoConnection {
  /// Whether the connection is open; false once the server closed it.
  bool get isConnected;

  Future<void> open();

  Future<void> close();
}

/// The [MongoConnection] of a mongo_dart [Db].
final class DbConnection implements MongoConnection {
  final Db _db;
  final MongoTransport _transport;

  DbConnection({required this._db, required this._transport});

  @override
  bool get isConnected => _db.isConnected;

  @override
  Future<void> open() => switch (_transport) {
        PlainTransport() => _db.open(secure: false),
        TlsTransport(:final caFile, :final certificateKeyFile, :final certificateKeyFilePassword) => _db.open(
            secure: true,
            tlsCAFile: caFile,
            tlsCertificateKeyFile: certificateKeyFile,
            tlsCertificateKeyFilePassword: certificateKeyFilePassword,
          ),
      };

  @override
  Future<void> close() => _db.close();
}
