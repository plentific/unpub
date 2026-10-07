import 'dart:async';

import 'package:unpub_aws/core/aws_credentials.dart';
import 'package:unpub_aws/core/credentials_source.dart';

/// Credentials from a [CredentialsSource], fetched again `refreshMargin`
/// before they expire so requests are never signed with expired ones.
///
/// Refreshes run on a timer, outside any request, where an uncaught error
/// would terminate the server: a refused refresh is logged and tried again
/// after `retryDelay`, and the current credentials stay in use meanwhile.
final class RefreshingCredentials {
  final CredentialsSource _source;
  final Duration _refreshMargin;
  final Duration _retryDelay;
  AwsCredentials _current;
  Timer? _refreshTimer;

  RefreshingCredentials({
    required this._source,
    required this._current,
    required this._refreshMargin,
    required this._retryDelay,
  });

  AwsCredentials get current => _current;

  /// Starts refreshing the credentials before they expire.
  void keepFresh() {
    _scheduleRefresh(_untilRefresh());
  }

  /// Stops refreshing.
  void close() {
    _refreshTimer?.cancel();
  }

  Duration _untilRefresh() => _current.expiration.subtract(_refreshMargin).difference(DateTime.now());

  void _scheduleRefresh(Duration delay) {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(delay.isNegative ? Duration.zero : delay, _refresh);
  }

  Future<void> _refresh() async {
    switch (await _source.fetch()) {
      case CredentialsFetched(:final credentials):
        _current = credentials;
        _scheduleRefresh(_untilRefresh());
      case CredentialsRefused(:final reason):
        print('Refreshing AWS credentials failed, retrying in ${_retryDelay.inSeconds}s: $reason');
        _scheduleRefresh(_retryDelay);
    }
  }
}
