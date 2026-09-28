/// Why a plate advice request did not produce advice. Each case maps to a
/// localized message in the UI; raw exception text is never shown.
///
/// This mirrors `AnalysisFailure` (`features/recognition/domain/analysis.dart`)
/// rather than extending it: that hierarchy is sealed in another library, and
/// plate advice needs one case analysis does not (`invalidResponse` is a
/// distinct, retryable failure here, not folded into "unavailable").
sealed class PlateAdviceFailure implements Exception {
  const PlateAdviceFailure();
}

/// No connection to the backend.
class PlateAdviceOffline extends PlateAdviceFailure {
  const PlateAdviceOffline();
}

/// No backend address is configured.
class PlateAdviceServerNotConfigured extends PlateAdviceFailure {
  const PlateAdviceServerNotConfigured();
}

/// TLS to the backend failed because its certificate is not trusted.
class PlateAdviceCertificateUntrusted extends PlateAdviceFailure {
  const PlateAdviceCertificateUntrusted();
}

/// The plate advice rate limit was exceeded.
class PlateAdviceRateLimited extends PlateAdviceFailure {
  const PlateAdviceRateLimited();
}

/// The backend's AI answer was invalid (`AI_INVALID_RESPONSE`), or the
/// response body was malformed or had no acceptable suggestion.
class PlateAdviceInvalidResponse extends PlateAdviceFailure {
  const PlateAdviceInvalidResponse();
}

/// A timeout, a 5xx status or any other unexpected failure.
class PlateAdviceUnavailable extends PlateAdviceFailure {
  const PlateAdviceUnavailable();
}
