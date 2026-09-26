import 'package:http/http.dart' as http;

Future<Object? Function()?> createAiIoHttpClientFactory({
  required bool trustDebugCa,
  required String debugCaAsset,
}) async => null;

Future<http.Client> createAiHttpClient({
  required bool trustDebugCa,
  required String debugCaAsset,
}) async {
  return http.Client();
}
