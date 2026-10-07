/// What the server answers for a package it does not have.
sealed class MissingPackages {
  const MissingPackages();
}

/// Answer 404. A client that asks this server for a private package it does
/// not (yet) have then fails, instead of being sent to a public package that
/// happens to have the same name (dependency confusion).
final class RejectMissingPackages extends MissingPackages {
  const RejectMissingPackages();
}

/// Redirect to another pub server, e.g. https://pub.dev, so that clients can
/// use this server as their only hosted URL.
final class RedirectMissingPackages extends MissingPackages {
  final Uri upstream;

  const RedirectMissingPackages(this.upstream);
}
