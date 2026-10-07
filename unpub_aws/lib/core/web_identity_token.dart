import 'dart:io';

/// Where the web identity token for STS comes from.
sealed class WebIdentityToken {
  const WebIdentityToken();
}

/// A token given as a value, e.g. through AWS_WEB_IDENTITY_TOKEN.
final class InlineWebIdentityToken extends WebIdentityToken {
  final String token;

  const InlineWebIdentityToken(this.token);
}

/// A token in a file that is rotated in place, like the projected service
/// account token on EKS (IRSA): the kubelet rewrites the file and the old
/// token expires after 24h, so the file is read again for every STS call.
final class FileWebIdentityToken extends WebIdentityToken {
  final File file;

  const FileWebIdentityToken(this.file);
}
