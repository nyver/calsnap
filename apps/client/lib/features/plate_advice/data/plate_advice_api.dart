import 'dart:async';

import 'package:dio/dio.dart';

import '../../recognition/data/analysis_api.dart';
import '../../recognition/data/remote_config_repository.dart';
import '../../recognition/domain/analysis.dart';
import '../domain/plate_advice.dart';
import '../domain/plate_advice_failure.dart';
import '../domain/plate_advice_repository.dart';
import '../domain/plate_advice_request.dart';

/// Client of `POST /v1/plate-advice`. See design.md Decision 12.
class PlateAdviceApi implements PlateAdviceRepository {
  PlateAdviceApi(this._dio, this._remoteConfig, {required this.newRequestId});

  final Dio _dio;
  final RemoteConfigRepository _remoteConfig;

  /// A fresh correlation id per request.
  final String Function() newRequestId;

  @override
  Future<PlateAdvice> getAdvice(
    PlateAdviceRequest request, {
    Future<void>? cancel,
  }) async {
    final config = await _remoteConfig.current();
    final cancelToken = CancelToken();
    // A one-shot signal; cancelling after completion is a harmless no-op.
    unawaited(cancel?.then((_) => cancelToken.cancel()));

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/plate-advice',
        data: request.toJson(),
        cancelToken: cancelToken,
        options: Options(
          contentType: 'application/json',
          headers: {'X-Request-Id': newRequestId()},
          receiveTimeout:
              Duration(seconds: config.analyzeTimeoutSeconds) +
              AnalysisApi.timeoutMargin,
        ),
      );
      final body = response.data;
      if (body == null) throw const PlateAdviceInvalidResponse();
      final advice = PlateAdvice.fromJson(body);
      if (advice.suggestions.isEmpty) throw const PlateAdviceInvalidResponse();
      return advice;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      if (_codeOf(e) == 'AI_INVALID_RESPONSE') {
        throw const PlateAdviceInvalidResponse();
      }
      // Dio wraps a response transformer failure (malformed JSON) in a
      // DioException instead of letting the FormatException propagate.
      if (e.error is FormatException || e.error is TypeError) {
        throw const PlateAdviceInvalidResponse();
      }
      throw _translate(AnalysisApi.mapFailure(e));
    } on TypeError {
      // A response that parses as JSON but has the wrong shape.
      throw const PlateAdviceInvalidResponse();
    } on FormatException {
      throw const PlateAdviceInvalidResponse();
    }
  }

  static String? _codeOf(DioException e) {
    final data = e.response?.data;
    return data is Map<String, dynamic> ? data['code'] as String? : null;
  }

  /// Translates the shared [AnalysisFailure] categories into the plate
  /// advice hierarchy. `AI_INVALID_RESPONSE` is handled before this is
  /// reached, since [AnalysisApi.mapFailure] folds it into "unavailable".
  static PlateAdviceFailure _translate(AnalysisFailure f) => switch (f) {
    OfflineFailure() => const PlateAdviceOffline(),
    ServerNotConfiguredFailure() => const PlateAdviceServerNotConfigured(),
    CertificateFailure() => const PlateAdviceCertificateUntrusted(),
    RateLimitedFailure() => const PlateAdviceRateLimited(),
    TimeoutFailure() ||
    UnavailableFailure() ||
    BadImageFailure() ||
    NotRecognizedFailure() ||
    UnknownFailure() => const PlateAdviceUnavailable(),
  };
}
