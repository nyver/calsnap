import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'retry_interceptor.dart';
import 'server_certificate.dart';

/// Creates the HTTP client for the CalSnap backend. [trusted] is a certificate
/// the user confirmed; it is accepted for its own host and port only, on top of
/// the normal system trust store.
Dio createDio({
  required String baseUrl,
  HttpClientAdapter? adapter,
  TrustedCertificate? trusted,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 75),
      responseType: ResponseType.json,
      headers: const {'Accept': 'application/json'},
    ),
  );
  if (adapter != null) {
    dio.httpClientAdapter = adapter;
  } else if (trusted != null) {
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => createPinnedHttpClient(trusted),
    );
  }
  dio.interceptors.add(RetryInterceptor(dio));
  return dio;
}
