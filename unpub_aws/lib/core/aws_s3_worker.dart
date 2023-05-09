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

  Credentials? _credentials;

  void set credentials(Credentials credentials) {
    _credentials = credentials;
  }

  Stream<List<int>> upload({
    required String name,
    required String version,
    required List<int> content,
  }) async* {
    final request = AWSStreamedHttpRequest.put(
      Uri.https('s3.$region.amazonaws.com', '/$bucket/${_getObjectKey(name, version)}'),
      body: Stream.value(content),
    );
    final signedRequest = await _signRequest(credentials: _credentials, request: request);
    final response = await signedRequest.send().response;
    yield* response.body;
  }

  Stream<List<int>> download({
    required String name,
    required String version,
  }) async* {
    final request = AWSStreamedHttpRequest.get(
      Uri.https('s3.$region.amazonaws.com', '/$bucket/${_getObjectKey(name, version)}'),
    );
    final signedRequest = await _signRequest(credentials: _credentials, request: request);
    final response = await signedRequest.send().response;
    yield* response.body;
  }

  Future<AWSSignedRequest> _signRequest({
    required Credentials? credentials,
    required AWSBaseHttpRequest request,
  }) async {
    if (_credentials == null) {
      throw Exception();
    }

    final signer = AWSSigV4Signer(
      credentialsProvider: AWSCredentialsProvider(
        AWSCredentials(
          _credentials!.accessKeyId,
          _credentials!.secretAccessKey,
          _credentials!.sessionToken,
        ),
      ),
    );
    final scope = AWSCredentialScope(
      region: region,
      service: AWSService.s3,
    );
    return signer.sign(request, credentialScope: scope);
  }

  String _getObjectKey(String name, String version) => '$name/$name-$version.tar.gz';
}
