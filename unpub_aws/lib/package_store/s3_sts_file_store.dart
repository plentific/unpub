import 'dart:async';

import 'package:unpub/unpub.dart';
import 'package:unpub_aws/core/aws_s3_worker.dart';
import 'package:unpub_aws/core/refreshing_credentials.dart';

/// Keeps package archives in S3, signing requests with credentials refreshed
/// through STS (IAM roles for service accounts on EKS).
final class S3StoreIamStore implements PackageStore {
  final AwsS3Worker _s3;
  final RefreshingCredentials _credentials;

  S3StoreIamStore({required this._s3, required this._credentials});

  @override
  bool supportsDownloadUrl = false;

  @override
  FutureOr<String> downloadUrl(String name, String version) =>
      throw UnsupportedError('S3StoreIamStore serves package archives through download');

  @override
  Future<void> upload(String name, String version, List<int> content) async {
    await _s3.upload(name: name, version: version, content: content, credentials: _credentials.current).first;
  }

  @override
  Stream<List<int>> download(String name, String version) =>
      _s3.download(name: name, version: version, credentials: _credentials.current);
}
