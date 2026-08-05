import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'ai_http_client_factory_stub.dart'
    if (dart.library.io) 'ai_http_client_factory_io.dart'
    as platform;

/// Creates the HTTP clients used for direct AI-provider communication.
///
/// Debug builds trust the bundled HT Media inspection CA so emulator requests
/// work behind the company proxy. A developer can explicitly disable it with:
/// `--dart-define=AI_TRUST_HT_MEDIA_DEBUG_CA=false`.
///
/// The override is intentionally unavailable in profile and release builds.
class AiHttpClientFactory {
  static const _trustDebugCa = bool.fromEnvironment(
    'AI_TRUST_HT_MEDIA_DEBUG_CA',
    defaultValue: true,
  );
  static const _debugCaAsset = 'assets/certificates/ht_media_netskope_ca.pem';

  const AiHttpClientFactory._();

  static Future<http.Client> create() {
    return platform.createAiHttpClient(
      trustDebugCa: kDebugMode && _trustDebugCa,
      debugCaAsset: _debugCaAsset,
    );
  }
}
