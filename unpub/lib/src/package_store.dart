/// What a [PackageStore] gave for a package archive.
sealed class StoredArchive {
  const StoredArchive();
}

/// The archive, to send on as it is read.
final class ArchiveFound extends StoredArchive {
  final Stream<List<int>> bytes;

  const ArchiveFound(this.bytes);
}

/// The store has no archive of the version.
final class ArchiveMissing extends StoredArchive {
  const ArchiveMissing();
}

/// The store did not give the archive: it refused, failed or did not answer.
final class ArchiveUnavailable extends StoredArchive {
  final String reason;

  const ArchiveUnavailable(this.reason);
}

/// Where package archives are kept.
abstract interface class PackageStore {
  /// The archive of [version] of [name] once the store has answered, so that
  /// what went wrong can still be told to the client as a status.
  Future<StoredArchive> download(String name, String version);

  Future<void> upload(String name, String version, List<int> content);
}
