import 'package:http/http.dart' as http;

Future<http.Client> createAiHttpClient({
  required bool trustDebugCa,
  required String debugCaAsset,
}) async {
  return http.Client();
}
