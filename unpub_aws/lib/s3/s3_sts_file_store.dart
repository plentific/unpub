import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:aws_sts_api/sts-2011-06-15.dart';
import 'package:minio/minio.dart';
import 'package:unpub/unpub.dart';
import 'package:unpub_aws/core/aws_web_identity.dart';

/// Use an AWS S3 Bucket using IAM as a package store
class S3StoreIamStore extends PackageStore {
  final AwsWebIdentity webIdentity;
  String Function(String name, String version)? getObjectPath;

  Minio? _minio;
  final Map<String, String> _env;
  late final String _bucketName;
  late final String? _region;
  late final String _endpoint;

  final _credentialsRefreshStreamController = StreamController<DateTime>();
  StreamSubscription? _credentialsRefreshStreamSubscription;

  S3StoreIamStore({
    required this.webIdentity,
    this.getObjectPath,
    String? bucketName,
    String? region,
    String? endpoint,
    Map<String, String>? environment,
  }) : _env = environment ?? Platform.environment {
    _region = region ?? _env['AWS_REGION'];
    _endpoint = endpoint ?? _env['AWS_S3_ENDPOINT'] ?? 's3.amazonaws.com';
    _bucketName = bucketName ?? _env['AWS_BUCKET_NAME'] ?? '';

    if (webIdentity.roleArn.isEmpty ||
        webIdentity.webIdentityToken.isEmpty ||
        webIdentity.roleSessionName.isEmpty) {
      throw ArgumentError('All STS credentials must be passed on AWS.');
    }
    if (_bucketName.isEmpty == true) {
      throw ArgumentError('AWS bucket name cannot be null.');
    }
    if (_region == null || _region?.isEmpty == true) {
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
    final stsResponse = await STS().assumeRoleWithWebIdentity(
      roleArn: webIdentity.roleArn,
      roleSessionName: webIdentity.roleSessionName,
      webIdentityToken: webIdentity.webIdentityToken,
    );
    final credentials = stsResponse.credentials;
    if (credentials == null) {
      throw Exception('Got empty AWS credentials. Cannot initialize AWS client.');
    }
    _minio = Minio(
      endPoint: _endpoint,
      region: _region,
      accessKey: credentials.accessKeyId,
      secretKey: credentials.secretAccessKey,
    );
    _credentialsRefreshStreamController.add(credentials.expiration);
  }

  @override
  Future<void> upload(String name, String version, List<int> content) async {
    _checkMinioClientInitialized();
    await _minio!.putObject(
      _bucketName,
      _getObjectKey(name, version),
      Stream.value(Uint8List.fromList(content)),
    );
  }

  @override
  Stream<List<int>> download(String name, String version) async* {
    _checkMinioClientInitialized();
    final getObjectStream = await _minio!.getObject(
      _bucketName,
      _getObjectKey(name, version),
    );
    yield* getObjectStream.map((event) => Uint8List.fromList(event));
  }

  String _getObjectKey(String name, String version) {
    return getObjectPath?.call(name, version) ?? '$name/$name-$version.tar.gz';
  }

  void _checkMinioClientInitialized() {
    if (_minio == null) {
      throw Exception('AWS client is not initialized');
    }
  }
}