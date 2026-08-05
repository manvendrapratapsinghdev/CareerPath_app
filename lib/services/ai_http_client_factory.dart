import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'ai_http_client_factory_stub.dart'
    if (dart.library.io) 'ai_http_client_factory_io.dart'
    as platform;

/// Creates the HTTP clients used for direct AI-provider communication.
///
/// Normal builds use the platform trust roots. A developer can opt a debug
/// build into the bundled HT Media inspection CA when testing behind the
/// company proxy:
/// `--dart-define=AI_TRUST_HT_MEDIA_DEBUG_CA=true`.
///
/// The override is intentionally unavailable in profile and release builds.
class AiHttpClientFactory {
  static const _trustDebugCa = bool.fromEnvironment(
    'AI_TRUST_HT_MEDIA_DEBUG_CA',
    defaultValue: false,
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
