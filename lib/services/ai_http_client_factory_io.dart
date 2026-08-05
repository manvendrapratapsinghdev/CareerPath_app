import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

Future<http.Client> createAiHttpClient({
  required bool trustDebugCa,
  required String debugCaAsset,
}) async {
  if (!trustDebugCa) return http.Client();

  final certificate = await rootBundle.load(debugCaAsset);
  final bytes = certificate.buffer.asUint8List(
    certificate.offsetInBytes,
    certificate.lengthInBytes,
  );
  final context = SecurityContext(withTrustedRoots: true)
    ..setTrustedCertificatesBytes(bytes);
  return IOClient(HttpClient(context: context));
}
