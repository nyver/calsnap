import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

/// Routes `package:logging` records to the debug console. Release builds emit
/// nothing. Never log photos, food names or response bodies.
void configureLogging() {
  Logger.root.level = kReleaseMode ? Level.OFF : Level.INFO;
  Logger.root.onRecord.listen((record) {
    if (kReleaseMode) return;
    debugPrint(
      '[${record.level.name}] ${record.loggerName}: ${record.message}'
      '${record.error != null ? ' (${record.error.runtimeType})' : ''}',
    );
  });
}
