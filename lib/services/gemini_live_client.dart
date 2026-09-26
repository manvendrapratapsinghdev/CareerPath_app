import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../config/ai_provider_config.dart';
import '../config/api_urls.dart';

/// Server → client events of Gemini Live `BidiGenerateContent`.
sealed class LiveEvent {
  const LiveEvent();
}

class LiveSetupComplete extends LiveEvent {
  const LiveSetupComplete();
}

class LiveAudio extends LiveEvent {
  const LiveAudio(this.pcm24k);
  final Uint8List pcm24k;
}

class LiveInputTranscript extends LiveEvent {
  const LiveInputTranscript(this.text);
  final String text;
}

class LiveOutputTranscript extends LiveEvent {
  const LiveOutputTranscript(this.text);
  final String text;
}

class LiveInterrupted extends LiveEvent {
  const LiveInterrupted();
}

class LiveTurnComplete extends LiveEvent {
  const LiveTurnComplete();
}

class LiveFunctionCall {
  const LiveFunctionCall({
    required this.id,
    required this.name,
    required this.args,
  });

  final String? id;
  final String name;
  final Map<String, dynamic> args;
}

class LiveToolCall extends LiveEvent {
  const LiveToolCall(this.calls);
  final List<LiveFunctionCall> calls;
}

class LiveToolCallCancellation extends LiveEvent {
  const LiveToolCallCancellation(this.ids);
  final List<String> ids;
}

class LiveGoAway extends LiveEvent {
  const LiveGoAway();
}

class LiveClosed extends LiveEvent {
  const LiveClosed(this.code, this.reason);
  final int? code;
  final String? reason;
}

/// Direct phone → Google WebSocket for Gemini Live. There is no backend in
/// between; the API key travels in the `x-goog-api-key` header.
class GeminiLiveClient {
  GeminiLiveClient({Object? Function()? httpClientFactory})
    : _httpClientFactory = httpClientFactory;

  final Object? Function()? _httpClientFactory;
  WebSocket? _socket;
  StreamController<LiveEvent>? _events;

  Stream<LiveEvent> get events =>
      _events?.stream ?? const Stream<LiveEvent>.empty();

  bool get isOpen => _socket?.readyState == WebSocket.open;

  /// Opens the socket, sends [setup] and completes once Gemini replies with
  /// `setupComplete`.
  Future<void> connect({
    required String apiKey,
    required Map<String, dynamic> setup,
  }) async {
    await close();
    final events = StreamController<LiveEvent>.broadcast();
    _events = events;
    final socket = await WebSocket.connect(
      ApiUrls.geminiLiveWebSocket,
      headers: {'x-goog-api-key': apiKey},
      customClient: _httpClientFactory?.call() as HttpClient?,
    ).timeout(AiProviderConfig.liveConnectTimeout);
    socket.pingInterval = const Duration(seconds: 20);
    _socket = socket;

    final ready = Completer<void>();
    socket.listen(
      (data) {
        for (final event in parse(data)) {
          if (event is LiveSetupComplete && !ready.isCompleted) {
            ready.complete();
          }
          if (!events.isClosed) events.add(event);
        }
      },
      onError: (Object error) {
        if (!ready.isCompleted) ready.completeError(error);
        if (!events.isClosed) events.add(LiveClosed(null, '$error'));
      },
      onDone: () {
        if (!ready.isCompleted) {
          ready.completeError(
            StateError('Live socket closed: ${socket.closeReason}'),
          );
        }
        if (!events.isClosed) {
          events.add(LiveClosed(socket.closeCode, socket.closeReason));
        }
      },
      cancelOnError: false,
    );
    socket.add(jsonEncode(setup));
    await ready.future.timeout(AiProviderConfig.liveConnectTimeout);
  }

  void sendAudio(Uint8List pcm16k) => _send({
    'realtimeInput': {
      'audio': {
        'data': base64Encode(pcm16k),
        'mimeType': 'audio/pcm;rate=${AiProviderConfig.liveInputSampleRate}',
      },
    },
  });

  void sendText(String text) => _send({
    'realtimeInput': {'text': text},
  });

  void sendAudioStreamEnd() => _send({
    'realtimeInput': {'audioStreamEnd': true},
  });

  void sendToolResponses(List<Map<String, dynamic>> responses) => _send({
    'toolResponse': {'functionResponses': responses},
  });

  void _send(Map<String, dynamic> message) {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) return;
    socket.add(jsonEncode(message));
  }

  Future<void> close() async {
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      try {
        await socket.close(WebSocketStatus.normalClosure);
      } on Object {
        // Already closed.
      }
    }
    final events = _events;
    _events = null;
    if (events != null && !events.isClosed) await events.close();
  }

  /// Parses one frame; Gemini sends JSON as text or binary frames.
  static List<LiveEvent> parse(Object? data) {
    final String text;
    if (data is String) {
      text = data;
    } else if (data is List<int>) {
      text = utf8.decode(data);
    } else {
      return const [];
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return const [];
    }
    if (decoded is! Map) return const [];
    final events = <LiveEvent>[];
    if (decoded.containsKey('setupComplete')) {
      events.add(const LiveSetupComplete());
    }
    final content = decoded['serverContent'];
    if (content is Map) {
      final input = content['inputTranscription'];
      if (input is Map && input['text'] is String) {
        events.add(LiveInputTranscript(input['text'] as String));
      }
      final turn = content['modelTurn'];
      final parts = turn is Map ? turn['parts'] : null;
      if (parts is List) {
        for (final part in parts.whereType<Map>()) {
          final inline = part['inlineData'];
          if (inline is Map && inline['data'] is String) {
            events.add(LiveAudio(base64Decode(inline['data'] as String)));
          }
        }
      }
      final output = content['outputTranscription'];
      if (output is Map && output['text'] is String) {
        events.add(LiveOutputTranscript(output['text'] as String));
      }
      if (content['interrupted'] == true) events.add(const LiveInterrupted());
      if (content['turnComplete'] == true) {
        events.add(const LiveTurnComplete());
      }
    }
    final toolCall = decoded['toolCall'];
    if (toolCall is Map && toolCall['functionCalls'] is List) {
      events.add(
        LiveToolCall([
          for (final call
              in (toolCall['functionCalls'] as List).whereType<Map>())
            LiveFunctionCall(
              id: call['id']?.toString(),
              name: call['name']?.toString() ?? '',
              args: call['args'] is Map
                  ? Map<String, dynamic>.from(call['args'] as Map)
                  : const {},
            ),
        ]),
      );
    }
    final cancellation = decoded['toolCallCancellation'];
    if (cancellation is Map && cancellation['ids'] is List) {
      events.add(
        LiveToolCallCancellation(
          (cancellation['ids'] as List).map((id) => id.toString()).toList(),
        ),
      );
    }
    if (decoded.containsKey('goAway')) events.add(const LiveGoAway());
    return events;
  }
}
