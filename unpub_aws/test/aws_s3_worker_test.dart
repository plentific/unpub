import 'dart:async';

import 'package:aws_common/aws_common.dart';
import 'package:aws_common/testing.dart';
import 'package:test/test.dart';
import 'package:unpub/unpub.dart';
import 'package:unpub_aws/core/aws_credentials.dart';
import 'package:unpub_aws/core/aws_s3_worker.dart';

final _credentials = AwsCredentials(
  accessKeyId: 'AKIDEXAMPLE',
  secretAccessKey: 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY',
  sessionToken: 'session-token',
  expiration: DateTime.utc(2030),
);

void main() {
  test('gives the archive S3 has, from a signed request for its object', () async {
    final requests = <AWSHttpRequest>[];
    final worker = AwsS3Worker(
      http: MockAWSHttpClient((request, isCancelled) {
        requests.add(request);
        return AWSHttpResponse(statusCode: 200, body: [1, 2, 3]);
      }),
      region: 'eu-west-1',
      bucket: 'packages',
      timeout: const Duration(seconds: 30),
    );

    final archive = await worker.download(name: 'acme_ui', version: '1.0.0+1', credentials: _credentials);

    expect(archive, isA<ArchiveFound>());
    expect(await (archive as ArchiveFound).bytes.expand((chunk) => chunk).toList(), [1, 2, 3]);
    expect(requests.single.method, AWSHttpMethod.get);
    expect(requests.single.uri, Uri.parse('https://s3.eu-west-1.amazonaws.com/packages/acme_ui-1.0.0.1.tar.gz'));
    expect(requests.single.headers['authorization'], startsWith('AWS4-HMAC-SHA256 '));
  });

  test('answers missing when S3 does not have the archive', () async {
    final worker = AwsS3Worker(
      http: MockAWSHttpClient((request, isCancelled) => AWSHttpResponse(statusCode: 404)),
      region: 'eu-west-1',
      bucket: 'packages',
      timeout: const Duration(seconds: 30),
    );

    expect(await worker.download(name: 'acme_ui', version: '1.0.0', credentials: _credentials), isA<ArchiveMissing>());
  });

  test('answers unavailable with what S3 said when it refuses', () async {
    final worker = AwsS3Worker(
      http: MockAWSHttpClient(
        (request, isCancelled) => AWSHttpResponse(statusCode: 403, body: '<Code>AccessDenied</Code>'.codeUnits),
      ),
      region: 'eu-west-1',
      bucket: 'packages',
      timeout: const Duration(seconds: 30),
    );

    expect(
      await worker.download(name: 'acme_ui', version: '1.0.0', credentials: _credentials),
      isA<ArchiveUnavailable>().having(
        (archive) => archive.reason,
        'reason',
        allOf(contains('403'), contains('AccessDenied')),
      ),
    );
  });

  test('answers unavailable and cancels the request when S3 does not answer in time', () async {
    final cancelled = <bool Function()>[];
    final worker = AwsS3Worker(
      http: MockAWSHttpClient((request, isCancelled) {
        cancelled.add(isCancelled);
        return Completer<AWSBaseHttpResponse>().future;
      }),
      region: 'eu-west-1',
      bucket: 'packages',
      timeout: const Duration(milliseconds: 10),
    );

    final archive = await worker.download(name: 'acme_ui', version: '1.0.0', credentials: _credentials);

    expect(
      archive,
      isA<ArchiveUnavailable>().having((archive) => archive.reason, 'reason', contains('did not answer')),
    );
    expect(cancelled.single(), isTrue);
  });
}
