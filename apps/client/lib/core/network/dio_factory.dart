import 'package:dio/dio.dart';

import 'retry_interceptor.dart';

/// Creates the HTTP client for the CalSnap backend.
Dio createDio({required String baseUrl, HttpClientAdapter? adapter}) {
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
  if (adapter != null) dio.httpClientAdapter = adapter;
  dio.interceptors.add(RetryInterceptor(dio));
  return dio;
}
