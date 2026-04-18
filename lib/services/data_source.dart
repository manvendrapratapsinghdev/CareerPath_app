/// Abstract data source for career path data.
/// Implemented by both [ApiClient] (network) and [LocalDataSource] (bundled DB).
abstract class DataSource {
  Future<List<Map<String, dynamic>>> getStreams({bool forceRefresh = false});

  Future<List<Map<String, dynamic>>> getStreamRootNodes(
    int streamApiId, {
    bool forceRefresh = false,
  });

  Future<List<Map<String, dynamic>>> getNodeChildren(
    int nodeApiId, {
    bool forceRefresh = false,
  });

  Future<Map<String, dynamic>> getNodeDetails(
    int nodeApiId, {
    bool forceRefresh = false,
  });
}
