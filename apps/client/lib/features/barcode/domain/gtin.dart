/// Validation of product barcodes (GS1 GTIN), mirroring the backend so that a
/// misread code is discarded on the device and never sent.
abstract final class Gtin {
  /// The canonical form of [raw], or null when it is not a valid GTIN-8,
  /// GTIN-12 (UPC-A), GTIN-13 (EAN-13) or GTIN-14. A UPC-A code gets a leading
  /// zero and becomes an EAN-13.
  static String? normalize(String raw) {
    final code = raw.trim();
    if (!const {8, 12, 13, 14}.contains(code.length)) return null;
    for (final unit in code.codeUnits) {
      if (unit < 0x30 || unit > 0x39) return null; // ASCII digits only
    }
    if (!_validCheckDigit(code)) return null;
    return code.length == 12 ? '0$code' : code;
  }

  /// From the right, the digits before the check digit are weighted 3, 1, 3, ...
  static bool _validCheckDigit(String code) {
    var sum = 0;
    var weight = 3;
    for (var i = code.length - 2; i >= 0; i--) {
      sum += (code.codeUnitAt(i) - 0x30) * weight;
      weight = 4 - weight;
    }
    return (10 - sum % 10) % 10 == code.codeUnitAt(code.length - 1) - 0x30;
  }
}
