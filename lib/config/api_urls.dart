/// Central registry for every URL used by the app.
///
/// Rule: NO URL string is allowed anywhere else in the codebase.
/// All HTTP calls must reference a constant from this class.
class ApiUrls {
  ApiUrls._(); // prevent instantiation

  // ── Base URL ───────────────────────────────────────────────────────────────

  static const String baseUrl =
      'https://schedular-lennox-nonpermissible.ngrok-free.dev';

  // ── Streams ────────────────────────────────────────────────────────────────

  /// GET  /api/streams  →  list all streams
  static String get streams => '$baseUrl/api/streams';

  /// GET  /api/streams/{id}  →  single stream
  static String stream(int id) => '$baseUrl/api/streams/$id';

  /// GET  /api/streams/{id}/nodes  →  root-level nodes for a stream
  static String streamNodes(int streamId) =>
      '$baseUrl/api/streams/$streamId/nodes';

  // ── Nodes ──────────────────────────────────────────────────────────────────

  /// GET  /api/nodes/{id}  →  single node with child_ids
  static String node(int id) => '$baseUrl/api/nodes/$id';

  /// GET  /api/nodes/{id}/children  →  direct children of a node
  static String nodeChildren(int nodeId) =>
      '$baseUrl/api/nodes/$nodeId/children';

  /// GET  /api/nodes/{id}/details  →  leaf-node rich data (books / institutes / sectors)
  static String nodeDetails(int nodeId) =>
      '$baseUrl/api/nodes/$nodeId/details';

  // ── Books ──────────────────────────────────────────────────────────────────

  /// GET  /api/books  →  list all recommended books
  static String get books => '$baseUrl/api/books';

  // ── Institutes ─────────────────────────────────────────────────────────────

  /// GET  /api/institutes  →  list all educational institutes
  static String get institutes => '$baseUrl/api/institutes';

  // ── Job Sectors ────────────────────────────────────────────────────────────

  /// GET  /api/job_sectors  →  list all job sectors
  static String get jobSectors => '$baseUrl/api/job_sectors';
}
