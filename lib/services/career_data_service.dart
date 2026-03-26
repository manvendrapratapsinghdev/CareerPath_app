import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/book.dart';
import '../models/career_node.dart';
import '../models/institute.dart';
import '../models/job_sector.dart';
import '../models/leaf_details.dart';
import '../models/stream_model.dart';
import 'api_client.dart';

/// Fetches all career data from the backend API and caches it in memory.
///
/// Public synchronous methods (getAllStreams, getCategoriesForStream,
/// getChildrenOf, getNodeById) work exactly like before – screens need no
/// changes – because all data is pre-loaded during [initialize].
///
/// The new [getLeafDetails] method performs a single async API call to
/// retrieve rich data (books / institutes / job sectors) for a leaf node.
class CareerDataService {
  final ApiClient _api;

  List<StreamModel> _streams = [];
  Map<String, CareerNode> _nodesMap = {};
  Map<int, Book> _booksMap = {};
  Map<int, Institute> _institutesMap = {};
  Map<int, JobSector> _jobSectorsMap = {};

  /// Maps slug → backend integer primary key (needed for leaf-details fetch).
  final Map<String, int> _slugToApiId = {};

  CareerDataService(this._api);

  // ── initialisation ─────────────────────────────────────────────────────────

  Future<void>? _initFuture;

  /// Idempotent: first call triggers the API fetch; subsequent calls return
  /// the same future so initialization only ever runs once.
  /// Call [reset] first to force a fresh attempt after a previous failure.
  Future<void> ensureInitialized() => _initFuture ??= initialize();

  /// Clears cached state so [ensureInitialized] triggers a fresh API fetch.
  /// Pass [clearHttpCache] to also evict all HTTP-level cached responses.
  void reset({bool clearHttpCache = false}) {
    _initFuture = null;
    _streams = [];
    _nodesMap = {};
    _slugToApiId.clear();
    _fetchedStreamCategories.clear();
    _fetchedChildren.clear();
    if (clearHttpCache) _api.clearCache();
  }

  bool get isInitialized => _streams.isNotEmpty;

  /// Single API call at startup — just fetches the stream list.
  /// Root nodes and children are loaded lazily when the user navigates.
  Future<void> initialize({bool forceRefresh = false}) async {
    final streamsRaw = await _api.getStreams(forceRefresh: forceRefresh);

    _slugToApiId.clear();
    for (final s in streamsRaw) {
      _slugToApiId[s['slug'] as String] = s['id'] as int;
    }

    _streams = streamsRaw.map((s) {
      return StreamModel(
        id: s['slug'] as String,
        name: s['name'] as String,
        intro: s['intro'] as String?,
        rootNodeCount: (s['root_node_ids'] as List).length,
        categoryIds: [], // populated lazily via fetchStreamCategories()
      );
    }).toList();
  }

  // ── lazy loaders ───────────────────────────────────────────────────────────

  final Set<String> _fetchedStreamCategories = {};
  final Set<String> _fetchedChildren = {};

  /// Fetches and caches the root nodes for [streamSlug].
  /// Pass [forceRefresh] to bypass both service- and HTTP-level caches.
  Future<List<CareerNode>> fetchStreamCategories(String streamSlug,
      {bool forceRefresh = false}) async {
    if (!forceRefresh && _fetchedStreamCategories.contains(streamSlug)) {
      return getCategoriesForStream(streamSlug);
    }
    _fetchedStreamCategories.remove(streamSlug);

    final apiId = _slugToApiId[streamSlug];
    if (apiId == null) return [];

    final rootNodes =
        await _api.getStreamRootNodes(apiId, forceRefresh: forceRefresh);
    final slugs = <String>[];
    for (final n in rootNodes) {
      final slug = n['slug'] as String;
      _slugToApiId[slug] = n['id'] as int;
      _nodesMap[slug] = CareerNode(
        id: slug,
        name: n['name'] as String,
        intro: n['intro'] as String?,
        childCount: (n['child_ids'] as List? ?? []).length,
      );
      slugs.add(slug);
    }

    final idx = _streams.indexWhere((s) => s.id == streamSlug);
    if (idx >= 0) {
      _streams[idx] = StreamModel(
        id: _streams[idx].id,
        name: _streams[idx].name,
        intro: _streams[idx].intro,
        rootNodeCount: _streams[idx].rootNodeCount,
        categoryIds: slugs,
      );
    }
    _fetchedStreamCategories.add(streamSlug);
    return getCategoriesForStream(streamSlug);
  }

  /// Fetches and caches the children of [nodeSlug].
  /// Pass [forceRefresh] to bypass both service- and HTTP-level caches.
  Future<List<CareerNode>> fetchChildrenOf(String nodeSlug,
      {bool forceRefresh = false}) async {
    if (!forceRefresh && _fetchedChildren.contains(nodeSlug)) {
      return getChildrenOf(nodeSlug);
    }
    _fetchedChildren.remove(nodeSlug);

    final apiId = _slugToApiId[nodeSlug];
    if (apiId == null) return [];

    final childrenRaw =
        await _api.getNodeChildren(apiId, forceRefresh: forceRefresh);
    final childSlugs = <String>[];
    for (final c in childrenRaw) {
      final slug = c['slug'] as String;
      _slugToApiId[slug] = c['id'] as int;
      _nodesMap[slug] = CareerNode(
        id: slug,
        name: c['name'] as String,
        intro: c['intro'] as String?,
        childCount: (c['child_ids'] as List? ?? []).length,
      );
      childSlugs.add(slug);
    }

    // Update parent's childIds so getChildrenOf() works from cache
    final parent = _nodesMap[nodeSlug];
    if (parent != null) {
      _nodesMap[nodeSlug] = CareerNode(
        id: parent.id,
        name: parent.name,
        intro: parent.intro,
        childIds: childSlugs,
        childCount: parent.childCount,
      );
    }
    _fetchedChildren.add(nodeSlug);
    return getChildrenOf(nodeSlug);
  }

  // ── synchronous accessors (unchanged public interface) ─────────────────────

  List<StreamModel> getAllStreams() => List.unmodifiable(_streams);

  List<CareerNode> getCategoriesForStream(String streamId) {
    final stream = _streams.cast<StreamModel?>().firstWhere(
          (s) => s!.id == streamId,
          orElse: () => null,
        );
    if (stream == null) return [];
    return stream.categoryIds
        .map((id) => _nodesMap[id])
        .whereType<CareerNode>()
        .toList();
  }

  List<CareerNode> getChildrenOf(String nodeId) {
    final node = _nodesMap[nodeId];
    if (node == null) return [];
    return node.childIds
        .map((id) => _nodesMap[id])
        .whereType<CareerNode>()
        .toList();
  }

  CareerNode? getNodeById(String nodeId) => _nodesMap[nodeId];

  // ── resource accessors ─────────────────────────────────────────────────────

  /// Get a book by its API ID.
  Book? getBookById(int id) => _booksMap[id];

  /// Get all cached books.
  List<Book> getAllBooks() => List.unmodifiable(_booksMap.values);

  /// Get an institute by its API ID.
  Institute? getInstituteById(int id) => _institutesMap[id];

  /// Get all cached institutes.
  List<Institute> getAllInstitutes() => List.unmodifiable(_institutesMap.values);

  /// Get a job sector by its API ID.
  JobSector? getJobSectorById(int id) => _jobSectorsMap[id];

  /// Get all cached job sectors.
  List<JobSector> getAllJobSectors() => List.unmodifiable(_jobSectorsMap.values);

  // ── new async accessor ─────────────────────────────────────────────────────

  /// Fetches rich leaf-node details (books, institutes, job sectors) from the
  /// backend. Returns null when no details are stored for this node.
  Future<LeafDetails?> getLeafDetails(String nodeId,
      {bool forceRefresh = false}) async {
    final apiId = _slugToApiId[nodeId];
    if (apiId == null) return null;
    try {
      final data = await _api.getNodeDetails(apiId, forceRefresh: forceRefresh);
      return LeafDetails.fromJson(data);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  // ── testing helper ─────────────────────────────────────────────────────────

  @visibleForTesting
  void initializeWithData(
      List<StreamModel> streams, Map<String, CareerNode> nodes) {
    _streams = streams;
    _nodesMap = nodes;
  }
}

