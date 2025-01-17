import 'dart:io';

class AwsWebIdentity {
  final String roleArn;
  final String roleSessionName;
  final String webIdentityToken;

  AwsWebIdentity({
    required this.roleArn,
    required this.roleSessionName,
    required this.webIdentityToken,
  });

  factory AwsWebIdentity.fromEnv(Map<String, String> env) {
    if (env['AWS_ROLE_ARN'] == null ||
        env['AWS_ROLE_SESSION_NAME'] == null ||
        env['AWS_WEB_IDENTITY_TOKEN'] == null) {
      throw ArgumentError('Web Identity Token path cannot be null.');
    }
    return AwsWebIdentity(
      roleArn: env['AWS_ROLE_ARN'] as String,
      roleSessionName: env['AWS_ROLE_SESSION_NAME'] as String,
      webIdentityToken: env['AWS_WEB_IDENTITY_TOKEN'] as String,
    );
  }

  static Future<AwsWebIdentity> fromEnvFile({
    required Map<String, String?> env,
    String? path,
    String? roleArn,
    String? roleSessionName,
  }) async {
    final tokenFilePath = path ?? env['AWS_WEB_IDENTITY_TOKEN_FILE'];
    if (tokenFilePath == null || tokenFilePath.isEmpty == true) {
      throw ArgumentError('Web Identity Token path cannot be null.');
    }
    final webIdentityToken = await File(tokenFilePath).readAsString();
    return AwsWebIdentity(
      roleArn: roleArn ?? env['AWS_ROLE_ARN'] as String,
      roleSessionName: roleSessionName ?? env['AWS_ROLE_SESSION_NAME'] as String,
      webIdentityToken: webIdentityToken,
    );
  }
}
