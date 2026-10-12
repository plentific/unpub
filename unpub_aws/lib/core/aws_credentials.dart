/// Temporary AWS credentials, valid until [expiration].
final class AwsCredentials {
  final String accessKeyId;
  final String secretAccessKey;
  final String sessionToken;
  final DateTime expiration;

  const AwsCredentials({
    required this.accessKeyId,
    required this.secretAccessKey,
    required this.sessionToken,
    required this.expiration,
  });
}
