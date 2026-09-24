import 'dart:io' show TlsException;
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../domain/analysis.dart';

/// Client of the CalSnap backend (`POST /v1/meals/analyze`, `GET /v1/config`).
class AnalysisApi {
  AnalysisApi(this._dio);

  final Dio _dio;

  /// Extra time on top of the server-provided analysis timeout.
  static const Duration timeoutMargin = Duration(seconds: 15);

  /// Uploads the prepared JPEG. Throws [AnalysisFailure] subtypes only;
  /// cancellation surfaces as a [DioException] of type cancel.
  Future<AnalysisResult> analyze({
    required Uint8List jpeg,
    required String locale,
    required String requestId,
    required RemoteConfig config,
    double? plateDiameterCm,
    CancelToken? cancelToken,
  }) async {
    final form = FormData.fromMap({
      'image': MultipartFile.fromBytes(
        jpeg,
        filename: 'meal.jpg',
        contentType: DioMediaType('image', 'jpeg'),
      ),
      'locale': locale,
      'plateDiameterCm': ?plateDiameterCm?.toString(),
    });
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/meals/analyze',
        data: form,
        cancelToken: cancelToken,
        options: Options(
          headers: {'X-Request-Id': requestId},
          receiveTimeout:
              Duration(seconds: config.analyzeTimeoutSeconds) + timeoutMargin,
        ),
      );
      final body = response.data;
      if (body == null) throw const UnknownFailure();
      final result = AnalysisResult.fromJson(body);
      if (result.items.isEmpty ||
          result.warnings.contains(WarningCode.noFoodDetected)) {
        throw const NotRecognizedFailure();
      }
      return result;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      throw mapFailure(e);
    } on FormatException {
      throw const UnknownFailure();
    }
  }

  /// Fetches client-safe tunables; falls back to defaults on any problem.
  Future<RemoteConfig> fetchConfig({CancelToken? cancelToken}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/v1/config',
      cancelToken: cancelToken,
      options: Options(
        receiveTimeout: const Duration(seconds: 8),
        sendTimeout: const Duration(seconds: 8),
      ),
    );
    return RemoteConfig.fromJson(response.data ?? const {});
  }

  /// Maps transport and API errors to a user-facing failure category.
  static AnalysisFailure mapFailure(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
        return const OfflineFailure();
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const TimeoutFailure();
      case DioExceptionType.badResponse:
        return _fromResponse(e.response);
      case DioExceptionType.badCertificate:
        return const CertificateFailure();
      case DioExceptionType.cancel:
        return const UnknownFailure();
      case DioExceptionType.unknown:
        // A rejected TLS handshake is not wrapped in a dedicated Dio type.
        return e.error is TlsException
            ? const CertificateFailure()
            : const UnknownFailure();
    }
  }

  static AnalysisFailure _fromResponse(Response<dynamic>? response) {
    final status = response?.statusCode;
    final data = response?.data;
    final code = data is Map<String, dynamic> ? data['code'] : null;
    switch (code) {
      case 'RATE_LIMITED':
        return const RateLimitedFailure();
      case 'INVALID_IMAGE':
      case 'IMAGE_TOO_LARGE':
      case 'UNSUPPORTED_IMAGE_FORMAT':
        return const BadImageFailure();
      case 'AI_PROVIDER_UNAVAILABLE':
      case 'AI_INVALID_RESPONSE':
      case 'IMAGE_ANALYSIS_FAILED':
      case 'NUTRITION_MATCH_FAILED':
      case 'INTERNAL_ERROR':
        return const UnavailableFailure();
    }
    if (status == 429) return const RateLimitedFailure();
    if (status == 413 || status == 415) return const BadImageFailure();
    if (status != null && status >= 500) return const UnavailableFailure();
    return const UnknownFailure();
  }
}
