import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aws_common/aws_common.dart';
import 'package:aws_signature_v4/aws_signature_v4.dart';
import 'package:unpub_aws/core/aws_credentials.dart';

/// Reads and writes package archives in an S3 bucket.
final class AwsS3Worker {
  final AWSHttpClient _http;
  final String _region;
  final String _bucket;

  AwsS3Worker({required this._http, required this._region, required this._bucket});

  /// Sends its requests through one long-lived client, so connections to S3
  /// are reused.
  factory AwsS3Worker.inRegion({required String region, required String bucket}) =>
      AwsS3Worker(http: AWSHttpClient(), region: region, bucket: bucket);

  Future<void> upload({
    required String name,
    required String version,
    required List<int> content,
    required AwsCredentials credentials,
  }) async {
    final request = AWSStreamedHttpRequest.put(
      _objectUri(name, version),
      body: Stream.value(Uint8List.fromList(content)),
    );
    final signedRequest = await _signRequest(credentials: credentials, request: request);
    final response = await signedRequest.send(client: _http).response;
    if (response.statusCode != HttpStatus.ok) {
      throw Exception(
        'S3 file upload error. Status code ${response.statusCode}. \n'
        '${utf8.decode(await response.bodyBytes, allowMalformed: true)}',
      );
    }
  }

  Stream<List<int>> download({
    required String name,
    required String version,
    required AwsCredentials credentials,
  }) async* {
    final request = AWSStreamedHttpRequest.get(_objectUri(name, version));
    final signedRequest = await _signRequest(credentials: credentials, request: request);
    final response = await signedRequest.send(client: _http).response;
    // Without this check an S3 error (e.g. 403 for expired credentials) is
    // served to `dart pub` as the package archive.
    if (response.statusCode != HttpStatus.ok) {
      throw Exception(
        'S3 file download error. Status code ${response.statusCode}. \n'
        '${utf8.decode(await response.bodyBytes, allowMalformed: true)}',
      );
    }
    yield* response.body;
  }

  Future<AWSSignedRequest> _signRequest({
    required AwsCredentials credentials,
    required AWSBaseHttpRequest request,
  }) async {
    final signer = AWSSigV4Signer(
      credentialsProvider: AWSCredentialsProvider(
        AWSCredentials(credentials.accessKeyId, credentials.secretAccessKey, credentials.sessionToken),
      ),
    );
    final scope = AWSCredentialScope(region: _region, service: AWSService.s3);
    return signer.sign(request, credentialScope: scope);
  }

  Uri _objectUri(String name, String version) =>
      Uri.https('s3.$_region.amazonaws.com', '/$_bucket/${_getObjectKey(name, version)}');

  String _getObjectKey(String name, String version) => '$name-$version.tar.gz'.replaceAll('+', '.');
}
