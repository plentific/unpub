import 'package:http/http.dart' as http;
import 'package:unpub_aws/core/aws_credentials.dart';
import 'package:unpub_aws/core/aws_web_identity.dart';
import 'package:unpub_aws/core/web_identity_token.dart';
import 'package:xml/xml.dart';

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

/// Credentials for a role, assumed with a web identity token through the STS
/// query API. AssumeRoleWithWebIdentity is not signed: the token is the proof
/// of identity, so no AWS SDK or credentials are needed to call it.
final class StsWebIdentityCredentialsSource implements CredentialsSource {
  final http.Client _http;
  final Uri _endpoint;
  final AwsWebIdentity _webIdentity;

  StsWebIdentityCredentialsSource({
    required this._http,
    required this._endpoint,
    required this._webIdentity,
  });

  /// Calls the regional STS endpoint of [region].
  factory StsWebIdentityCredentialsSource.inRegion({
    required String region,
    required AwsWebIdentity webIdentity,
  }) =>
      StsWebIdentityCredentialsSource(
        http: http.Client(),
        endpoint: Uri.https('sts.$region.amazonaws.com', '/'),
        webIdentity: webIdentity,
      );

  @override
  Future<CredentialsReply> fetch() async {
    try {
      final response = await _http.post(_endpoint, body: {
        'Action': 'AssumeRoleWithWebIdentity',
        'Version': '2011-06-15',
        'RoleArn': _webIdentity.roleArn,
        'RoleSessionName': _webIdentity.roleSessionName,
        'WebIdentityToken': switch (_webIdentity.token) {
          InlineWebIdentityToken(:final token) => token,
          FileWebIdentityToken(:final file) => await file.readAsString(),
        },
      });
      if (response.statusCode != 200) {
        return CredentialsRefused('STS answered ${response.statusCode}: ${response.body}');
      }
      final document = XmlDocument.parse(response.body);
      return CredentialsFetched(AwsCredentials(
        accessKeyId: _text(document, 'AccessKeyId'),
        secretAccessKey: _text(document, 'SecretAccessKey'),
        sessionToken: _text(document, 'SessionToken'),
        expiration: DateTime.parse(_text(document, 'Expiration')),
      ));
    } catch (e) {
      return CredentialsRefused('$e');
    }
  }

  String _text(XmlDocument document, String element) => document.findAllElements(element).single.innerText;
}
