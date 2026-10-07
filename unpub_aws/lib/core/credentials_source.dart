import 'package:aws_sts_api/sts-2011-06-15.dart';
import 'package:unpub_aws/core/aws_credentials.dart';
import 'package:unpub_aws/core/aws_web_identity.dart';

/// What a [CredentialsSource] answered.
sealed class CredentialsReply {
  const CredentialsReply();
}

final class CredentialsFetched extends CredentialsReply {
  final AwsCredentials credentials;

  const CredentialsFetched(this.credentials);
}

final class CredentialsRefused extends CredentialsReply {
  final String reason;

  const CredentialsRefused(this.reason);
}

/// Hands out temporary AWS credentials.
abstract interface class CredentialsSource {
  Future<CredentialsReply> fetch();
}

/// Credentials for a role, assumed with a web identity token through STS.
final class StsWebIdentityCredentialsSource implements CredentialsSource {
  final STS _sts;
  final AwsWebIdentity _webIdentity;

  StsWebIdentityCredentialsSource({required this._sts, required this._webIdentity});

  factory StsWebIdentityCredentialsSource.inRegion({
    required String region,
    required AwsWebIdentity webIdentity,
  }) =>
      StsWebIdentityCredentialsSource(sts: STS(region: region), webIdentity: webIdentity);

  @override
  Future<CredentialsReply> fetch() async {
    try {
      final response = await _sts.assumeRoleWithWebIdentity(
        roleArn: _webIdentity.roleArn,
        roleSessionName: _webIdentity.roleSessionName,
        webIdentityToken: _webIdentity.webIdentityToken,
      );
      final credentials = response.credentials;
      if (credentials == null) return const CredentialsRefused('STS answered without credentials');
      return CredentialsFetched(AwsCredentials(
        accessKeyId: credentials.accessKeyId,
        secretAccessKey: credentials.secretAccessKey,
        sessionToken: credentials.sessionToken,
        expiration: credentials.expiration,
      ));
    } catch (e) {
      return CredentialsRefused('$e');
    }
  }
}
