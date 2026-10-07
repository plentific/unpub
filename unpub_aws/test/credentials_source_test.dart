import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:unpub_aws/core/aws_web_identity.dart';
import 'package:unpub_aws/core/credentials_source.dart';
import 'package:unpub_aws/core/web_identity_token.dart';

const _roleAssumed = '''
<AssumeRoleWithWebIdentityResponse xmlns="https://sts.amazonaws.com/doc/2011-06-15/">
  <AssumeRoleWithWebIdentityResult>
    <Credentials>
      <SessionToken>session-token</SessionToken>
      <SecretAccessKey>secret-key</SecretAccessKey>
      <Expiration>2026-10-07T13:00:00Z</Expiration>
      <AccessKeyId>ASIA0000000000000000</AccessKeyId>
    </Credentials>
  </AssumeRoleWithWebIdentityResult>
</AssumeRoleWithWebIdentityResponse>
''';

const _invalidIdentityToken = '''
<ErrorResponse xmlns="https://sts.amazonaws.com/doc/2011-06-15/">
  <Error>
    <Type>Sender</Type>
    <Code>InvalidIdentityToken</Code>
    <Message>Token expired</Message>
  </Error>
</ErrorResponse>
''';

main() {
  final endpoint = Uri.https('sts.eu-west-1.amazonaws.com', '/');

  test('assumes the role with the token read from its file for each call', () async {
    final directory = await Directory.systemTemp.createTemp('sts');
    addTearDown(() => directory.delete(recursive: true));
    final tokenFile = File('${directory.path}/token');
    final requests = <http.Request>[];
    final source = StsWebIdentityCredentialsSource(
      http: MockClient((request) async {
        requests.add(request);
        return http.Response(_roleAssumed, 200);
      }),
      endpoint: endpoint,
      webIdentity: AwsWebIdentity(
        roleArn: 'arn:aws:iam::000000000000:role/unpub',
        roleSessionName: 'unpubConnection',
        token: FileWebIdentityToken(tokenFile),
      ),
    );

    await tokenFile.writeAsString('token issued at startup');
    final reply = await source.fetch();
    await tokenFile.writeAsString('token rotated by the kubelet');
    await source.fetch();

    expect(requests.map((request) => request.bodyFields['WebIdentityToken']),
        ['token issued at startup', 'token rotated by the kubelet']);
    expect(requests.first.method, 'POST');
    expect(requests.first.url, endpoint);
    expect(requests.first.headers.containsKey('authorization'), isFalse);
    expect(requests.first.bodyFields, {
      'Action': 'AssumeRoleWithWebIdentity',
      'Version': '2011-06-15',
      'RoleArn': 'arn:aws:iam::000000000000:role/unpub',
      'RoleSessionName': 'unpubConnection',
      'WebIdentityToken': 'token issued at startup',
    });
    switch (reply) {
      case CredentialsFetched(:final credentials):
        expect(credentials.accessKeyId, 'ASIA0000000000000000');
        expect(credentials.secretAccessKey, 'secret-key');
        expect(credentials.sessionToken, 'session-token');
        expect(credentials.expiration, DateTime.utc(2026, 10, 7, 13));
      case CredentialsRefused(:final reason):
        fail('Refused: $reason');
    }
  });

  test('answers refused with the error STS gave', () async {
    final source = StsWebIdentityCredentialsSource(
      http: MockClient((request) async => http.Response(_invalidIdentityToken, 400)),
      endpoint: endpoint,
      webIdentity: AwsWebIdentity(
        roleArn: 'arn:aws:iam::000000000000:role/unpub',
        roleSessionName: 'unpubConnection',
        token: InlineWebIdentityToken('expired token'),
      ),
    );

    final reply = await source.fetch();

    expect(reply, isA<CredentialsRefused>().having((refused) => refused.reason, 'reason', contains('InvalidIdentityToken')));
  });

  test('answers refused without calling STS when the token file cannot be read', () async {
    final requests = <http.Request>[];
    final source = StsWebIdentityCredentialsSource(
      http: MockClient((request) async {
        requests.add(request);
        return http.Response(_roleAssumed, 200);
      }),
      endpoint: endpoint,
      webIdentity: AwsWebIdentity(
        roleArn: 'arn:aws:iam::000000000000:role/unpub',
        roleSessionName: 'unpubConnection',
        token: FileWebIdentityToken(File('${Directory.systemTemp.path}/no-such-token')),
      ),
    );

    final reply = await source.fetch();

    expect(reply, isA<CredentialsRefused>());
    expect(requests, isEmpty);
  });
}
