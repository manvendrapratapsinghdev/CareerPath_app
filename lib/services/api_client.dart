import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../config/api_urls.dart';
import 'data_source.dart';

/// A single cached response entry.
class _CacheEntry {
  final dynamic data;
  final DateTime expiresAt;
  _CacheEntry(this.data, this.expiresAt);
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Low-level HTTP client that talks to the Career Path backend.
/// All URLs are resolved from [ApiUrls] — no hardcoded strings here.
class ApiClient implements DataSource {
  final http.Client _client;

  /// In-memory response cache keyed by URL.
  final Map<String, _CacheEntry> _cache = {};

  /// How long a cached response remains valid.
  final Duration cacheTtl;

  ApiClient({http.Client? client, this.cacheTtl = const Duration(minutes: 30)})
      : _client = client ?? _createClient();

  /// In debug builds, bypass SSL certificate verification to handle
  /// self-signed or expired certificates (e.g. ngrok tunnels).
  /// In release builds the standard verified client is used.
  static http.Client _createClient() {
    final ioClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 8);
    if (kDebugMode) {
      ioClient.badCertificateCallback = (cert, host, port) => true;
    }
    return IOClient(ioClient);
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  // ngrok requires this header to skip the browser interstitial warning page.
  static const _defaultHeaders = <String, String>{
    'ngrok-skip-browser-warning': 'true',
    'Content-Type': 'application/json',
  };

  static dynamic _decodeJson(String body) => json.decode(body);

  Future<dynamic> _get(String url, {bool bypassCache = false}) async {
    if (!bypassCache) {
      final entry = _cache[url];
      if (entry != null && !entry.isExpired) {
        debugPrint('[ApiClient] CACHE HIT $url');
        return entry.data;
      }
    }

    debugPrint('[ApiClient] GET $url');
    final uri = Uri.parse(url);
    final response = await _client.get(uri, headers: _defaultHeaders);
    if (response.statusCode != 200) {
      throw ApiException(
        'GET $url failed with status ${response.statusCode}',
        response.statusCode,
      );
    }
    final data = await compute(_decodeJson, response.body);
    _cache[url] = _CacheEntry(data, DateTime.now().add(cacheTtl));
    return data;
  }

  /// Removes all cached entries.
  void clearCache() => _cache.clear();

  /// Removes the cached entry for a specific [url].
  void invalidate(String url) => _cache.remove(url);

  // ── streams ────────────────────────────────────────────────────────────────

  /// Returns all streams with their category_ids (integers).
  @override
  Future<List<Map<String, dynamic>>> getStreams(
      {bool forceRefresh = false}) async {
    final data = await _get(ApiUrls.streams, bypassCache: forceRefresh);
    return List<Map<String, dynamic>>.from(data as List);
  }

  // ── stream root nodes ───────────────────────────────────────────────────────

  /// Returns root-level nodes (parent_id IS NULL) for a given stream API integer id.
  @override
  Future<List<Map<String, dynamic>>> getStreamRootNodes(int streamApiId,
      {bool forceRefresh = false}) async {
    final data = await _get(ApiUrls.streamNodes(streamApiId),
        bypassCache: forceRefresh);
    return List<Map<String, dynamic>>.from(data as List);
  }

  // ── nodes ──────────────────────────────────────────────────────────────────

  /// Returns the direct children of a node.
  @override
  Future<List<Map<String, dynamic>>> getNodeChildren(int nodeApiId,
      {bool forceRefresh = false}) async {
    final data = await _get(ApiUrls.nodeChildren(nodeApiId),
        bypassCache: forceRefresh);
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Returns rich leaf-node details (books, institutes, job sectors).
  @override
  Future<Map<String, dynamic>> getNodeDetails(int nodeApiId,
      {bool forceRefresh = false}) async {
    final data = await _get(ApiUrls.nodeDetails(nodeApiId),
        bypassCache: forceRefresh);
    return Map<String, dynamic>.from(data as Map);
  }

  // ── books ──────────────────────────────────────────────────────────────────

  /// Returns all recommended books.
  Future<List<Map<String, dynamic>>> getBooks(
      {bool forceRefresh = false}) async {
    final data = await _get(ApiUrls.books, bypassCache: forceRefresh);
    return List<Map<String, dynamic>>.from(data as List);
  }

  // ── institutes ─────────────────────────────────────────────────────────────

  /// Returns all educational institutes.
  Future<List<Map<String, dynamic>>> getInstitutes(
      {bool forceRefresh = false}) async {
    final data = await _get(ApiUrls.institutes, bypassCache: forceRefresh);
    return List<Map<String, dynamic>>.from(data as List);
  }

  // ── job sectors ────────────────────────────────────────────────────────────

  /// Returns all job sectors.
  Future<List<Map<String, dynamic>>> getJobSectors(
      {bool forceRefresh = false}) async {
    final data = await _get(ApiUrls.jobSectors, bypassCache: forceRefresh);
    return List<Map<String, dynamic>>.from(data as List);
  }

  void dispose() {
    _client.close();
    _cache.clear();
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;
  const ApiException(this.message, this.statusCode);

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Thrown when a non-streams API call fails, indicating the backend is down.
class ServerDownException implements Exception {
  final String message;
  const ServerDownException([this.message =
      'Server is down. Please contact admin (9807942950) to start the server.']);

  @override
  String toString() => 'ServerDownException: $message';
}
