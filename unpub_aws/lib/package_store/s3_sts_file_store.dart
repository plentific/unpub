import 'dart:async';
import 'dart:io';

import 'package:aws_sts_api/sts-2011-06-15.dart';
import 'package:unpub/unpub.dart';
import 'package:unpub_aws/core/aws_s3_worker.dart';
import 'package:unpub_aws/core/aws_web_identity.dart';

/// Use an AWS S3 Bucket using IAM as a package store
class S3StoreIamStore extends PackageStore {
  final AwsWebIdentity webIdentity;
  String Function(String name, String version)? getObjectPath;

  final Map<String, String> _env;
  late final String _bucketName;
  late final String _region;

  Credentials? _credentials;

  final _credentialsRefreshStreamController = StreamController<DateTime>();
  StreamSubscription? _credentialsRefreshStreamSubscription;

  S3StoreIamStore({
    required this.webIdentity,
    this.getObjectPath,
    String? bucketName,
    String? region,
    Map<String, String>? environment,
  }) : _env = environment ?? Platform.environment {
    _region = region ?? _env['AWS_REGION'] ?? 'eu-west-1';
    _bucketName = bucketName ?? _env['AWS_BUCKET_NAME'] ?? '';

    if (webIdentity.roleArn.isEmpty ||
        webIdentity.webIdentityToken.isEmpty ||
        webIdentity.roleSessionName.isEmpty) {
      throw ArgumentError('All STS credentials must be passed on AWS.');
    }
    if (_bucketName.isEmpty == true) {
      throw ArgumentError('AWS bucket name cannot be null.');
    }
    if (_region.isEmpty == true) {
      throw ArgumentError('Could not determine a default region for AWS.');
    }
  }

  Future<void> init() async {
    _credentialsRefreshStreamSubscription = _credentialsRefreshStreamController.stream.listen(
      (event) async {
        final now = DateTime.now();
        final timeDifferenceInSeconds = event.difference(now);
        await Future.delayed(timeDifferenceInSeconds);
        await _getAwsCredentialsFromStsAndInitClient();
      },
    );
    await _getAwsCredentialsFromStsAndInitClient();
  }

  Future<void> close() async {
    await _credentialsRefreshStreamSubscription?.cancel();
  }

  Future<void> _getAwsCredentialsFromStsAndInitClient() async {
    var sts = STS(region: _region);

    try {
      final stsResponse = await sts.assumeRoleWithWebIdentity(
        roleArn: webIdentity.roleArn,
        roleSessionName: webIdentity.roleSessionName,
        webIdentityToken: webIdentity.webIdentityToken,
      );
      final credentials = stsResponse.credentials;
      if (credentials == null) {
        throw Exception('Got empty AWS credentials. Cannot initialize AWS client.');
      }
      _credentials = Credentials(
        accessKeyId: credentials.accessKeyId,
        secretAccessKey: credentials.secretAccessKey,
        sessionToken: credentials.sessionToken,
        expiration: credentials.expiration,
      );
      _credentialsRefreshStreamController.add(credentials.expiration);
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<void> upload(String name, String version, List<int> content) async {
    final s3 = AwsS3Worker(region: _region, bucket: _bucketName);
    s3.credentials = _credentials!;
    await s3.upload(name: name, version: version, content: content);
    return;
  }

  @override
  Stream<List<int>> download(String name, String version) async* {
    final s3 = AwsS3Worker(region: _region, bucket: _bucketName);
    s3.credentials = _credentials!;
    yield* s3.download(name: name, version: version);
  }
}
