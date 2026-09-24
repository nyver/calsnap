import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/config/app_config.dart';
import 'core/logging/app_logger.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  configureLogging();
  // Release builds refuse to run against a cleartext backend URL.
  AppConfig.validate(isReleaseMode: kReleaseMode);
  runApp(
    ProviderScope(
      // A failed initialization is shown by the splash screen, which retries
      // on demand; automatic retries would only delay that screen.
      retry: (retryCount, error) => null,
      child: const CalSnapApp(),
    ),
  );
}
