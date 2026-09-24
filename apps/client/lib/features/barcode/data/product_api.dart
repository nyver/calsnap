import 'package:dio/dio.dart';

import '../../recognition/data/analysis_api.dart';
import '../../recognition/domain/analysis.dart';
import '../domain/packaged_product.dart';
import '../domain/product_lookup.dart';

/// Client of `GET /v1/products/{barcode}`. The backend asks Open Food Facts,
/// so the device never contacts a third party.
class ProductApi implements ProductSource {
  ProductApi(this._dio);

  final Dio _dio;

  @override
  Future<PackagedProduct> fetch(
    String barcode, {
    required String locale,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/v1/products/$barcode',
        queryParameters: {'locale': locale},
        options: Options(
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
        ),
      );
      final body = response.data;
      if (body == null) throw const UnknownFailure();
      return PackagedProduct.fromJson(body);
    } on DioException catch (e) {
      final data = e.response?.data;
      final code = data is Map<String, dynamic> ? data['code'] : null;
      if (e.response?.statusCode == 404 && code == 'PRODUCT_NOT_FOUND') {
        throw const ProductNotFoundException();
      }
      if (code == 'PRODUCT_SOURCE_UNAVAILABLE') {
        throw const UnavailableFailure();
      }
      throw AnalysisApi.mapFailure(e);
    } on FormatException {
      throw const UnknownFailure();
    }
  }
}
