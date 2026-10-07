import 'package:test/test.dart';
import 'package:unpub_aws/core/aws_credentials.dart';
import 'package:unpub_aws/core/credentials_source.dart';
import 'package:unpub_aws/core/refreshing_credentials.dart';

/// Answers the fetches with its replies, in order.
final class _ScriptedSource implements CredentialsSource {
  final List<CredentialsReply> _replies;
  int fetches = 0;

  _ScriptedSource(this._replies);

  @override
  Future<CredentialsReply> fetch() async => _replies[fetches++];
}

main() {
  test('fetches new credentials refreshMargin before the current ones expire', () async {
    final source = _ScriptedSource([
      CredentialsFetched(AwsCredentials(
        accessKeyId: 'second',
        secretAccessKey: 'secret',
        sessionToken: 'session',
        expiration: DateTime.now().add(Duration(hours: 1)),
      )),
    ]);
    final credentials = RefreshingCredentials(
      source: source,
      current: AwsCredentials(
        accessKeyId: 'first',
        secretAccessKey: 'secret',
        sessionToken: 'session',
        expiration: DateTime.now().add(Duration(milliseconds: 300)),
      ),
      refreshMargin: Duration(milliseconds: 200),
      retryDelay: Duration(seconds: 1),
    );
    addTearDown(credentials.close);

    credentials.keepFresh();

    await Future.delayed(Duration(milliseconds: 50));
    expect(credentials.current.accessKeyId, 'first');
    // The refresh is due at 100ms, well before the first credentials expire at 300ms.
    await Future.delayed(Duration(milliseconds: 150));
    expect(credentials.current.accessKeyId, 'second');
    expect(source.fetches, 1);
  });

  test('keeps the current credentials and retries when a refresh is refused', () async {
    final source = _ScriptedSource([
      CredentialsRefused('STS unavailable'),
      CredentialsFetched(AwsCredentials(
        accessKeyId: 'second',
        secretAccessKey: 'secret',
        sessionToken: 'session',
        expiration: DateTime.now().add(Duration(hours: 1)),
      )),
    ]);
    final credentials = RefreshingCredentials(
      source: source,
      current: AwsCredentials(
        accessKeyId: 'first',
        secretAccessKey: 'secret',
        sessionToken: 'session',
        expiration: DateTime.now().add(Duration(milliseconds: 100)),
      ),
      refreshMargin: Duration(milliseconds: 20),
      retryDelay: Duration(milliseconds: 60),
    );
    addTearDown(credentials.close);

    credentials.keepFresh();

    // Refused at 80ms, retried at 140ms.
    await Future.delayed(Duration(milliseconds: 110));
    expect(credentials.current.accessKeyId, 'first');
    await Future.delayed(Duration(milliseconds: 140));
    expect(credentials.current.accessKeyId, 'second');
    expect(source.fetches, 2);
  });
}
