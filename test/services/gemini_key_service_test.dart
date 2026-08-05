import 'package:career_path/services/gemini_key_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('loads the configured field once and keeps it in memory', () async {
    var requestCount = 0;
    final service = GeminiKeyService(
      client: MockClient((request) async {
        requestCount++;
        expect(request.url.host, 'api.npoint.io');
        expect(request.headers['user-agent'], 'CareerPath/1.0');
        return http.Response('{"g_api_key":"test-key"}', 200);
      }),
    );

    expect(await service.getKey(), 'test-key');
    expect(await service.getKey(), 'test-key');
    expect(requestCount, 1);
  });

  test('does not retain a failed load and permits a retry', () async {
    var requestCount = 0;
    final service = GeminiKeyService(
      client: MockClient((_) async {
        requestCount++;
        if (requestCount == 1) return http.Response('{}', 500);
        return http.Response('{"g_api_key":"recovered-key"}', 200);
      }),
    );

    await expectLater(
      service.getKey(),
      throwsA(
        isA<GeminiKeyException>().having(
          (error) => error.code,
          'code',
          'key_endpoint_failed',
        ),
      ),
    );
    expect(await service.getKey(), 'recovered-key');
    expect(requestCount, 2);
  });

  test('rejects a response without the expected key field', () async {
    final service = GeminiKeyService(
      client: MockClient((_) async => http.Response('{"other":"value"}', 200)),
    );

    await expectLater(
      service.getKey(),
      throwsA(
        isA<GeminiKeyException>().having(
          (error) => error.code,
          'code',
          'missing_key',
        ),
      ),
    );
  });
}
