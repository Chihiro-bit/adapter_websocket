import 'dart:convert';
import 'interceptor.dart';
import 'websocket_message.dart';
import 'compression_stub.dart'
    if (dart.library.io) 'compression_io.dart';

/// Wire-format marker keys embedded in the JSON envelope.
const _kCompressed = '__c__';
const _kData = 'd';

/// Interceptor that gzip-compresses outgoing messages above [threshold] bytes
/// and transparently decompresses incoming compressed messages.
///
/// On web platforms compression is skipped (dart:io unavailable); messages
/// pass through unmodified.
///
/// Wire format for compressed messages:
/// ```json
/// {"__c__": 1, "d": "<base64-encoded gzip data>"}
/// ```
class CompressionInterceptor extends WebSocketInterceptor {
  /// Minimum uncompressed byte length before compression is applied.
  final int threshold;

  CompressionInterceptor({this.threshold = 1024});

  /// Whether compression is available on the current platform.
  bool get isSupported => platformSupportsCompression;

  @override
  Future<WebSocketMessage?> onSend(WebSocketMessage message) async {
    if (!platformSupportsCompression) return message;
    // Never compress heartbeat frames or binary blobs.
    if (message.type == 'heartbeat' || message.type == 'binary') {
      return message;
    }

    String? text;
    final data = message.data;
    if (data is String) {
      text = data;
    } else if (data is Map || data is List) {
      text = jsonEncode(data);
    } else {
      return message;
    }

    if (text.length < threshold) return message;

    final compressed = platformGzipEncode(utf8.encode(text));
    final envelope = jsonEncode({
      _kCompressed: 1,
      _kData: base64Encode(compressed),
    });

    return WebSocketMessage(
      data: envelope,
      timestamp: message.timestamp,
      type: message.type,
      metadata: {
        ...?message.metadata,
        _kCompressed: true,
        'originalSize': text.length,
        'compressedSize': compressed.length,
      },
    );
  }

  @override
  Future<WebSocketMessage?> onReceive(WebSocketMessage message) async {
    if (!platformSupportsCompression) return message;

    final data = message.data;
    Map<String, dynamic>? envelope;

    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) envelope = decoded;
      } catch (_) {
        return message;
      }
    } else if (data is Map<String, dynamic>) {
      envelope = data;
    }

    if (envelope == null || envelope[_kCompressed] != 1) return message;

    final b64 = envelope[_kData] as String?;
    if (b64 == null) return message;

    try {
      final decompressed = utf8.decode(platformGzipDecode(base64Decode(b64)));
      dynamic parsed;
      try {
        parsed = jsonDecode(decompressed);
      } catch (_) {
        parsed = decompressed;
      }

      final meta = Map<String, dynamic>.from(message.metadata ?? {})
        ..remove(_kCompressed);

      return WebSocketMessage(
        data: parsed,
        timestamp: message.timestamp,
        type: message.type,
        metadata: meta,
      );
    } catch (_) {
      return message;
    }
  }
}
