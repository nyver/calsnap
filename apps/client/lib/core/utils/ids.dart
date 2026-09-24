import 'dart:math';

/// Generates sortable UUIDv7 text identifiers for all primary keys.
///
/// Identifiers created in the same millisecond keep their creation order: the
/// 12 bits after the timestamp hold a counter (RFC 9562, section 6.2, method 1).
/// The counter state is process-wide, so every instance shares one sequence.
class IdGenerator {
  const IdGenerator();

  static final Random _random = Random.secure();
  static int _lastMs = 0;
  static int _counter = 0;

  String newId() {
    var ms = DateTime.now().millisecondsSinceEpoch;
    if (ms > _lastMs) {
      _lastMs = ms;
      // Start below the top of the range so that the counter has headroom.
      _counter = _random.nextInt(0x200);
    } else {
      // Same millisecond, or the clock went backwards: continue the sequence.
      ms = _lastMs;
      _counter++;
      if (_counter > 0xFFF) {
        // Counter exhausted: borrow the next millisecond.
        _lastMs++;
        ms = _lastMs;
        _counter = 0;
      }
    }

    final bytes = List<int>.filled(16, 0);
    for (var i = 0; i < 6; i++) {
      bytes[i] = (ms >> (8 * (5 - i))) & 0xFF;
    }
    bytes[6] = 0x70 | (_counter >> 8); // version 7 + counter high bits
    bytes[7] = _counter & 0xFF;
    for (var i = 8; i < 16; i++) {
      bytes[i] = _random.nextInt(256);
    }
    bytes[8] = 0x80 | (bytes[8] & 0x3F); // RFC 4122 variant

    final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')];
    return '${hex.sublist(0, 4).join()}-${hex.sublist(4, 6).join()}-'
        '${hex.sublist(6, 8).join()}-${hex.sublist(8, 10).join()}-'
        '${hex.sublist(10).join()}';
  }
}
