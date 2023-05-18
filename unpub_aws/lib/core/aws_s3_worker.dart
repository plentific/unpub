import 'dart:io';

import 'package:aws_common/aws_common.dart';
import 'package:aws_signature_v4/aws_signature_v4.dart';
import 'package:aws_sts_api/sts-2011-06-15.dart';

class AwsS3Worker {
  AwsS3Worker({
    required this.region,
    required this.bucket,
  });

  final String region;
  final String bucket;

  Stream<List<int>> upload({
    required String name,
    required String version,
    required List<int> content,
    required Credentials? credentials,
  }) async* {
    try {
      final request = AWSStreamedHttpRequest.put(
        Uri.https('s3.$region.amazonaws.com', '/$bucket/${_getObjectKey(name, version)}'),
        body: Stream.value(content),
      );
      final signedRequest = await _signRequest(credentials: credentials, request: request);
      final response = await signedRequest.send().response;
      if (response.statusCode == HttpStatus.ok) {
        yield 'File uploaded'.codeUnits;
      } else {
        throw Exception(
            'S3 file upload error. Status code ${response.statusCode}. \n${await response.bodyBytes}');
      }
    } catch (e, s) {
      throw Exception('S3 file upload error. Error: $e. \n$s');
    }
  }

  Stream<List<int>> download({
    required String name,
    required String version,
    required Credentials? credentials,
  }) async* {
    final request = AWSStreamedHttpRequest.get(
      Uri.https('s3.$region.amazonaws.com', '/$bucket/${_getObjectKey(name, version)}'),
    );
    final signedRequest = await _signRequest(credentials: credentials, request: request);
    final response = await signedRequest.send().response;
    yield* response.body;
  }

  Future<AWSSignedRequest> _signRequest({
    required Credentials? credentials,
    required AWSBaseHttpRequest request,
  }) async {
    if (credentials == null) {
      throw Exception('Empty AWS credentials');
    }
    final signer = AWSSigV4Signer(
      credentialsProvider: AWSCredentialsProvider(
        AWSCredentials(
          credentials.accessKeyId,
          credentials.secretAccessKey,
          credentials.sessionToken,
        ),
      ),
    );
    final scope = AWSCredentialScope(
      region: region,
      service: AWSService.s3,
    );
    return signer.sign(request, credentialScope: scope);
  }

  String _getObjectKey(String name, String version) => '$name-$version.tar.gz'.replaceAll('+', '.');
}
