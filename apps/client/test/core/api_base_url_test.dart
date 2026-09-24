import 'package:calsnap/core/config/api_base_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseApiBaseUrl', () {
    test('accepts http(s) URLs and normalizes them', () {
      const cases = {
        'https://calsnap.example.com': 'https://calsnap.example.com',
        '  https://calsnap.example.com/  ': 'https://calsnap.example.com',
        'https://calsnap.example.com///': 'https://calsnap.example.com',
        'https://example.com/calsnap/': 'https://example.com/calsnap',
        'http://10.0.2.2:8080': 'http://10.0.2.2:8080',
        'HTTPS://Example.com:8443': 'HTTPS://Example.com:8443',
      };
      for (final entry in cases.entries) {
        final r = parseApiBaseUrl(entry.key, requireHttps: false);
        expect(r.problem, isNull, reason: entry.key);
        expect(r.url, entry.value, reason: entry.key);
      }
    });

    test('rejects anything that is not a plain http(s) address', () {
      const bad = [
        '',
        '   ',
        'calsnap.example.com',
        '192.168.1.5:8080',
        'ftp://example.com',
        'file:///etc/passwd',
        'https://',
        'https://user:secret@example.com',
        'https://example.com?key=1',
        'https://example.com/#frag',
        'not a url',
      ];
      for (final input in bad) {
        final r = parseApiBaseUrl(input, requireHttps: false);
        expect(r.url, isNull, reason: input);
        expect(r.problem, ApiBaseUrlProblem.invalid, reason: input);
      }
    });

    test('cleartext is refused when HTTPS is required', () {
      final r = parseApiBaseUrl('http://example.com', requireHttps: true);
      expect(r.url, isNull);
      expect(r.problem, ApiBaseUrlProblem.insecure);
      expect(
        parseApiBaseUrl('https://example.com', requireHttps: true).url,
        'https://example.com',
      );
    });
  });
}
