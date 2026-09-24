import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/logging/app_logger.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  configureLogging();
  runApp(
    ProviderScope(
      // A failed initialization is shown by the splash screen, which retries
      // on demand; automatic retries would only delay that screen.
      retry: (retryCount, error) => null,
      child: const CalSnapApp(),
    ),
  );
}
