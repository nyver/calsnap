/// Why a backend address entered by the user was rejected.
enum ApiBaseUrlProblem {
  /// Not an absolute http(s) URL with a host, or it carries credentials, a
  /// query or a fragment.
  invalid,

  /// A cleartext `http://` URL where only HTTPS is allowed.
  insecure,
}

/// Result of [parseApiBaseUrl]: exactly one of [url] and [problem] is set.
typedef ApiBaseUrlResult = ({String? url, ApiBaseUrlProblem? problem});

/// Validates and normalizes a backend address (trimmed, no trailing slash).
///
/// A path prefix is allowed so that the backend can live behind a reverse
/// proxy at `https://example.com/calsnap`. Credentials in the URL are refused:
/// they would end up in logs and in the stored settings.
ApiBaseUrlResult parseApiBaseUrl(String raw, {required bool requireHttps}) {
  const invalid = (url: null, problem: ApiBaseUrlProblem.invalid);
  final text = raw.trim();
  final uri = Uri.tryParse(text);
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    return invalid;
  }
  if (requireHttps && uri.scheme != 'https') {
    return (url: null, problem: ApiBaseUrlProblem.insecure);
  }
  return (url: text.replaceFirst(RegExp(r'/+$'), ''), problem: null);
}
