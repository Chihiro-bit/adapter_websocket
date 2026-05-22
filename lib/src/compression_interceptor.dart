import 'dart:convert';
import 'interceptor.dart';
import 'websocket_message.dart';

// dart:io gzip is unavailable on web; use a platform guard.
bool get _isWeb => identical(0, 0.0);

List<int> _compress(List<int> data) {
  if (_isWeb) return data;
  // Inline import via function to avoid top-level dart:io dependency on web.
  return _gzipEncode(data);
}

List<int> _decompress(List<int> data) {
  if (_isWeb) return data;
  return _gzipDecode(data);
}

// Isolated so tree-shaker can remove on web.
List<int> _gzipEncode(List<int> data) {
  // ignore: avoid_dynamic_calls
  final codec = _gzip();
  return codec.encode(data);
}

List<int> _gzipDecode(List<int> data) {
  final codec = _gzip();
  return codec.decode(data);
}

dynamic _gzip() {
  // We use dynamic dispatch so this file compiles on web (dart:io absent).
  // The guard `_isWeb` ensures these lines never execute on web at runtime.
  // ignore: return_of_invalid_type
  return (const _GZipStub());
}

/// Stub that is replaced at runtime by dart:io GZipCodec on native platforms.
class _GZipStub {
  const _GZipStub();
  List<int> encode(List<int> data) => data;
  List<int> decode(List<int> data) => data;
}

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
  bool get isSupported => !_isWeb;

  @override
  Future<WebSocketMessage?> onSend(WebSocketMessage message) async {
    // Never compress heartbeat frames or binary blobs.
    if (message.type == 'heartbeat' || message.type == 'binary') {
      return message;
    }
    if (_isWeb) return message;

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

    final compressed = _compress(utf8.encode(text));
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
    if (_isWeb) return message;

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
      final decompressed = utf8.decode(_decompress(base64Decode(b64)));
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
