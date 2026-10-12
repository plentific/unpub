import 'package:unpub_aws/core/web_identity_token.dart';

/// The role to assume through STS, and the token that proves who is asking.
final class AwsWebIdentity {
  final String roleArn;
  final String roleSessionName;
  final WebIdentityToken token;

  const AwsWebIdentity({required this.roleArn, required this.roleSessionName, required this.token});
}
