import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/ai_provider_config.dart';
import '../config/api_urls.dart';

class GeminiKeyException implements Exception {
  final String code;

  const GeminiKeyException(this.code);

  @override
  String toString() => 'GeminiKeyException($code)';
}

/// Loads the prototype Gemini credential into memory only.
///
/// The value is never persisted, logged, or exposed through app state. This
/// does not make a publicly retrievable credential secret; it only prevents
/// hardcoding and local storage.
class GeminiKeyService {
  final http.Client _client;
  String? _apiKey;
  Future<String>? _loadFuture;

  GeminiKeyService({http.Client? client}) : _client = client ?? http.Client();

  bool get isLoaded => _apiKey != null;

  Future<void> preload() async {
    await getKey();
  }

  Future<String> getKey() {
    final existing = _apiKey;
    if (existing != null) return Future.value(existing);
    return _loadFuture ??= _load();
  }

  Future<String> _load() async {
    try {
      final response = await _client
          .get(
            Uri.parse(ApiUrls.geminiKeyConfig),
            headers: const {
              'Accept': 'application/json',
              'User-Agent': 'CareerPath/1.0',
            },
          )
          .timeout(AiProviderConfig.keyTimeout);
      if (response.statusCode != 200) {
        throw const GeminiKeyException('key_endpoint_failed');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const GeminiKeyException('invalid_key_response');
      }
      final value = decoded['g_api_key'];
      if (value is! String || value.trim().isEmpty) {
        throw const GeminiKeyException('missing_key');
      }

      _apiKey = value.trim();
      return _apiKey!;
    } on GeminiKeyException {
      rethrow;
    } on Exception catch (error) {
      debugPrint(
        '[AI Guide] Key configuration unavailable (${error.runtimeType})',
      );
      throw const GeminiKeyException('key_unavailable');
    } finally {
      if (_apiKey == null) _loadFuture = null;
    }
  }

  void clear() {
    _apiKey = null;
    _loadFuture = null;
  }

  void dispose() {
    clear();
    _client.close();
  }
}
