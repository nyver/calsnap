import 'dart:async';

import 'package:dio/dio.dart';

/// Retries a request after connection errors and HTTP 502/503/504, at most
/// [delays].length times, reusing the original request (including its
/// `X-Request-Id` header). Other failures, cancellations and 4xx responses are
/// never retried automatically.
class RetryInterceptor extends Interceptor {
  RetryInterceptor(
    this._dio, {
    this.delays = const [Duration(seconds: 1), Duration(seconds: 3)],
    Future<void> Function(Duration)? sleep,
  }) : _sleep = sleep ?? Future<void>.delayed;

  static const String attemptKey = 'retryAttempt';

  final Dio _dio;
  final List<Duration> delays;
  final Future<void> Function(Duration) _sleep;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final attempt = (err.requestOptions.extra[attemptKey] as int?) ?? 0;
    if (!_isRetryable(err) || attempt >= delays.length) {
      return handler.next(err);
    }
    await _sleep(delays[attempt]);
    if (err.requestOptions.cancelToken?.isCancelled ?? false) {
      return handler.next(err);
    }

    final options = err.requestOptions;
    options.extra[attemptKey] = attempt + 1;
    final data = options.data;
    if (data is FormData) {
      // A FormData stream can only be consumed once.
      options.data = data.clone();
    }
    try {
      handler.resolve(await _dio.fetch<dynamic>(options));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  static bool _isRetryable(DioException err) {
    switch (err.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
        return true;
      case DioExceptionType.badResponse:
        final status = err.response?.statusCode;
        return status == 502 || status == 503 || status == 504;
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.badCertificate:
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
        return false;
    }
  }
}
