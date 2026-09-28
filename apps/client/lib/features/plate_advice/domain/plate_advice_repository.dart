import 'plate_advice.dart';
import 'plate_advice_request.dart';

/// Where plate advice comes from; the backend in production, a fake in tests.
/// Cancellation is a plain future so the domain has no Dio dependency
/// (design.md Decision 11).
abstract interface class PlateAdviceRepository {
  /// Throws a [PlateAdviceFailure] subtype (see `plate_advice_failure.dart`)
  /// for every problem. Completing [cancel] aborts the request without
  /// throwing.
  Future<PlateAdvice> getAdvice(
    PlateAdviceRequest request, {
    Future<void>? cancel,
  });
}
