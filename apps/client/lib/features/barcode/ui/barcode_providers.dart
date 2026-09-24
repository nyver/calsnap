import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../recognition/ui/analysis_controller.dart';

/// Whether the backend can look products up by barcode. Read again every time
/// a screen offering the scanner opens; the configuration itself is cached, so
/// the answer is available offline.
final barcodeSupportedProvider = FutureProvider.autoDispose<bool>(
  (ref) async =>
      (await ref.watch(remoteConfigRepositoryProvider).current()).barcodeLookup,
);
