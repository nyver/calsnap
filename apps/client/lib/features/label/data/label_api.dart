import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../recognition/data/analysis_api.dart';
import '../../recognition/domain/analysis.dart';
import '../domain/label_reading.dart';

/// Client of `POST /v1/labels/analyze`. The photo goes to the CalSnap backend
/// like a meal photo and is not stored there.
class LabelApi implements LabelSource {
  LabelApi(this._dio, {required this.newRequestId});

  final Dio _dio;

  /// A fresh correlation id per reading.
  final String Function() newRequestId;

  @override
  Future<LabelReading> read(
    Uint8List jpeg, {
    required String locale,
    required RemoteConfig config,
  }) async {
    final form = FormData.fromMap({
      'image': MultipartFile.fromBytes(
        jpeg,
        filename: 'label.jpg',
        contentType: DioMediaType('image', 'jpeg'),
      ),
      'locale': locale,
    });
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/labels/analyze',
        data: form,
        options: Options(
          headers: {'X-Request-Id': newRequestId()},
          receiveTimeout:
              Duration(seconds: config.analyzeTimeoutSeconds) +
              AnalysisApi.timeoutMargin,
        ),
      );
      final body = response.data;
      if (body == null) throw const UnknownFailure();
      return LabelReading.fromJson(body);
    } on DioException catch (e) {
      final data = e.response?.data;
      final code = data is Map<String, dynamic> ? data['code'] : null;
      if (e.response?.statusCode == 422 && code == 'LABEL_NOT_RECOGNIZED') {
        throw const LabelNotRecognizedException();
      }
      throw AnalysisApi.mapFailure(e);
    } on FormatException {
      throw const UnknownFailure();
    }
  }
}
