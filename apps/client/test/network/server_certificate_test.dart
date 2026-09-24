import 'dart:convert';
import 'dart:io';

import 'package:calsnap/core/network/dio_factory.dart';
import 'package:calsnap/core/network/server_certificate.dart';
import 'package:calsnap/features/recognition/data/analysis_api.dart';
import 'package:calsnap/features/recognition/domain/analysis.dart';
import 'package:calsnap/features/settings/domain/server_address_check.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

// The certificate and key are a throwaway pair made only for these tests
// (protocol/fixtures/tls-selfsigned.*); they protect nothing.
final _fixtureFingerprint = protocolFile(
  'fixtures/tls-selfsigned.fingerprint.txt',
).readAsStringSync().trim();

List<int> _fixtureDer() {
  final pem = protocolFile('fixtures/tls-selfsigned.crt').readAsStringSync();
  final body = pem
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('-----'))
      .join();
  return base64.decode(body);
}

/// A local HTTPS backend presenting the fixture certificate.
Future<HttpServer> _startTlsServer() async {
  final context = SecurityContext()
    ..useCertificateChain(protocolFile('fixtures/tls-selfsigned.crt').path)
    ..usePrivateKey(protocolFile('fixtures/tls-selfsigned.key').path);
  final server = await HttpServer.bindSecure(
    InternetAddress.loopbackIPv4,
    0,
    context,
  );
  server.listen((request) {
    request.response
      ..headers.contentType = ContentType.json
      ..write(
        '{"imageMaxLongSidePx":1024,"imageJpegQuality":80,'
        '"maxUploadBytes":4194304,"analyzeTimeoutSeconds":60}',
      )
      ..close();
  });
  return server;
}

void main() {
  group('certificateFingerprint', () {
    test('formats SHA-256 as colon-separated upper-case hex', () {
      expect(
        certificateFingerprint(const []),
        'E3:B0:C4:42:98:FC:1C:14:9A:FB:F4:C8:99:6F:B9:24:'
        '27:AE:41:E4:64:9B:93:4C:A4:95:99:1B:78:52:B8:55',
      );
    });

    test('matches the value the server side computes for the same file', () {
      expect(certificateFingerprint(_fixtureDer()), _fixtureFingerprint);
    });
  });

  group('TrustedCertificate', () {
    final fp = _fixtureFingerprint;

    test('round-trips through its stored form', () {
      final pin = TrustedCertificate.forUrl('https://Example.COM:9443', fp);
      expect(pin.stored, 'example.com:9443|$fp');
      expect(TrustedCertificate.tryParse(pin.stored), pin);
    });

    test('parses IPv6 hosts and lower-case fingerprints', () {
      final pin = TrustedCertificate.tryParse('::1:8445|${fp.toLowerCase()}');
      expect(pin?.host, '::1');
      expect(pin?.port, 8445);
      expect(pin?.fingerprint, fp);
    });

    test('malformed values mean "not trusted"', () {
      for (final bad in [
        null,
        '',
        'example.com|$fp',
        'example.com:0|$fp',
        'example.com:70000|$fp',
        'example.com:443|AB:CD',
        'example.com:443|${fp.replaceAll(':', '')}',
      ]) {
        expect(TrustedCertificate.tryParse(bad), isNull, reason: '$bad');
      }
    });

    test('applies to its own host and port only', () {
      final pin = TrustedCertificate.forUrl('https://calsnap.lan:8445', fp);
      expect(pin.isFor('https://calsnap.lan:8445'), isTrue);
      expect(pin.isFor('https://CALSNAP.lan:8445/api'), isTrue);
      expect(pin.isFor('https://calsnap.lan:9000'), isFalse);
      expect(pin.isFor('https://other.lan:8445'), isFalse);
      expect(pin.isFor('http://calsnap.lan:8445'), isFalse);
    });
  });

  group('against a real TLS server', () {
    late HttpServer server;
    late String baseUrl;
    late int port;

    setUp(() async {
      server = await _startTlsServer();
      port = server.port;
      baseUrl = 'https://127.0.0.1:$port';
    });

    tearDown(() => server.close(force: true));

    test(
      'the probe reports the untrusted certificate with its fingerprint',
      () async {
        final result = await probeServerCertificate('127.0.0.1', port);
        expect(result, isA<CertificateUntrusted>());
        final info = (result as CertificateUntrusted).info;
        expect(info.fingerprint, _fixtureFingerprint);
        expect(info.subject, contains('CalSnap test self-signed'));
        expect(info.validTo.isAfter(DateTime.utc(2100)), isTrue);
      },
    );

    test('the probe reports an unreachable server', () async {
      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final closedPort = closed.port;
      await closed.close();
      expect(
        await probeServerCertificate('127.0.0.1', closedPort),
        isA<CertificateProbeFailed>(),
      );
    });

    test('without a pin the app refuses the certificate', () async {
      final api = AnalysisApi(createDio(baseUrl: baseUrl));
      await expectLater(api.fetchConfig(), throwsA(isA<DioException>()));
      try {
        await api.fetchConfig();
      } on DioException catch (e) {
        expect(AnalysisApi.mapFailure(e), isA<CertificateFailure>());
      }
    });

    test('with the confirmed pin the request goes through', () async {
      final pin = TrustedCertificate.forUrl(baseUrl, _fixtureFingerprint);
      final api = AnalysisApi(createDio(baseUrl: baseUrl, trusted: pin));
      final config = await api.fetchConfig();
      expect(config.imageMaxLongSidePx, 1024);
    });

    test('a pin for another fingerprint is refused', () async {
      final other = _fixtureFingerprint.replaceFirst(
        _fixtureFingerprint.substring(0, 2),
        _fixtureFingerprint.startsWith('00') ? '01' : '00',
      );
      final pin = TrustedCertificate.forUrl(baseUrl, other);
      final api = AnalysisApi(createDio(baseUrl: baseUrl, trusted: pin));
      await expectLater(api.fetchConfig(), throwsA(isA<DioException>()));
    });

    test('a pin for another port is refused', () async {
      final pin = TrustedCertificate(
        host: '127.0.0.1',
        port: port + 1,
        fingerprint: _fixtureFingerprint,
      );
      final api = AnalysisApi(createDio(baseUrl: baseUrl, trusted: pin));
      await expectLater(api.fetchConfig(), throwsA(isA<DioException>()));
    });
  });

  group('checkServerAddress', () {
    final info = CertificateInfo(
      fingerprint:
          'AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:'
          'AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA',
      subject: 'CN=calsnap',
      validFrom: DateTime.utc(2026),
      validTo: DateTime.utc(2028),
    );
    const url = 'https://calsnap.lan:8445';

    Future<AddressCheck> check(
      CertificateProbeResult result, {
      TrustedCertificate? pinned,
      String address = url,
    }) => checkServerAddress(
      address,
      pinned: pinned,
      probe: (host, port) async => result,
    );

    test('a plain http address is not probed', () async {
      var probed = false;
      final result = await checkServerAddress(
        'http://10.0.2.2:8445',
        pinned: null,
        probe: (host, port) async {
          probed = true;
          return const CertificateTrusted();
        },
      );
      expect(result, isA<AddressReady>());
      expect(probed, isFalse);
    });

    test(
      'a system-trusted or unreachable server needs no confirmation',
      () async {
        expect(await check(const CertificateTrusted()), isA<AddressReady>());
        expect(
          await check(const CertificateProbeFailed()),
          isA<AddressReady>(),
        );
      },
    );

    test('an untrusted certificate must be confirmed', () async {
      final result = await check(CertificateUntrusted(info));
      expect(result, isA<AddressNeedsTrust>());
      expect((result as AddressNeedsTrust).changed, isFalse);
      expect(result.info.fingerprint, info.fingerprint);
    });

    test(
      'the already confirmed certificate is not asked about again',
      () async {
        final pin = TrustedCertificate.forUrl(url, info.fingerprint);
        expect(
          await check(CertificateUntrusted(info), pinned: pin),
          isA<AddressReady>(),
        );
      },
    );

    test('a different certificate for the same server is a change', () async {
      final pin = TrustedCertificate.forUrl(url, _fixtureFingerprint);
      final result = await check(CertificateUntrusted(info), pinned: pin);
      expect((result as AddressNeedsTrust).changed, isTrue);
    });

    test('a pin for another server does not count as a change', () async {
      final pin = TrustedCertificate.forUrl(
        'https://elsewhere.lan:8445',
        _fixtureFingerprint,
      );
      final result = await check(CertificateUntrusted(info), pinned: pin);
      expect((result as AddressNeedsTrust).changed, isFalse);
    });
  });
}
