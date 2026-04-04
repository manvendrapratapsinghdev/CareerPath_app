import '../services/data_source.dart';
import 'local_database.dart';

/// Local data source backed by the bundled SQLite database.
/// Implements [DataSource] so it can replace [ApiClient] in [CareerDataService].
class LocalDataSource implements DataSource {
  final LocalDatabase _db;

  LocalDataSource(this._db);

  @override
  Future<List<Map<String, dynamic>>> getStreams({
    bool forceRefresh = false,
  }) =>
      _db.getStreams();

  @override
  Future<List<Map<String, dynamic>>> getStreamRootNodes(
    int streamApiId, {
    bool forceRefresh = false,
  }) =>
      _db.getStreamRootNodes(streamApiId);

  @override
  Future<List<Map<String, dynamic>>> getNodeChildren(
    int nodeApiId, {
    bool forceRefresh = false,
  }) =>
      _db.getNodeChildren(nodeApiId);

  @override
  Future<Map<String, dynamic>> getNodeDetails(
    int nodeApiId, {
    bool forceRefresh = false,
  }) =>
      _db.getNodeDetails(nodeApiId);

  /// Fetch all nodes at once for eager-loading.
  Future<List<Map<String, dynamic>>> getAllNodes() => _db.getAllNodes();
}
