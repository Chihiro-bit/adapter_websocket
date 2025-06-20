import 'dart:io';

/// Callback for handling bad TLS certificates.
typedef BadCertificateCallback = bool Function(
  X509Certificate cert,
  String host,
  int port,
);


/// Configuration class for WebSocket connections
class WebSocketConfig {
  final String url;
  final List<String>? protocols;
  final Map<String, String>? headers;
  final HttpClient? httpClient;
  final BadCertificateCallback? badCertificateCallback;
  final Duration? pingInterval;
  final Duration connectionTimeout;
  final Duration reconnectDelay;
  final int maxReconnectAttempts;
  final bool autoReconnect;
  final bool enableLogging;
  
  // Enhanced heartbeat configuration
  final bool enableHeartbeat;
  final Duration heartbeatInterval;
  final Duration heartbeatTimeout;
  final String heartbeatMessage;
  final String? expectedPongMessage;
  final int maxMissedHeartbeats;
  final bool useExponentialBackoff;
  final Duration maxReconnectDelay;
  final double backoffMultiplier;

  const WebSocketConfig({
    required this.url,
    this.protocols,
    this.headers,
    this.pingInterval,
    this.connectionTimeout = const Duration(seconds: 10),
    this.reconnectDelay = const Duration(seconds: 5),
    this.maxReconnectAttempts = 3,
    this.autoReconnect = true,
    this.enableLogging = false,
    // Heartbeat defaults
    this.enableHeartbeat = true,
    this.heartbeatInterval = const Duration(seconds: 30),
    this.heartbeatTimeout = const Duration(seconds: 10),
    this.heartbeatMessage = 'ping',
    this.expectedPongMessage,
    this.maxMissedHeartbeats = 3,
    this.useExponentialBackoff = true,
    this.maxReconnectDelay = const Duration(minutes: 5),
    this.backoffMultiplier = 2.0,
    this.httpClient,
    this.badCertificateCallback,
  });

  /// Creates a copy of this config with updated values
  WebSocketConfig copyWith({
    String? url,
    List<String>? protocols,
    Map<String, String>? headers,
    Duration? pingInterval,
    Duration? connectionTimeout,
    Duration? reconnectDelay,
    int? maxReconnectAttempts,
    bool? autoReconnect,
    bool? enableLogging,
    bool? enableHeartbeat,
    Duration? heartbeatInterval,
    Duration? heartbeatTimeout,
    String? heartbeatMessage,
    String? expectedPongMessage,
    int? maxMissedHeartbeats,
    bool? useExponentialBackoff,
    Duration? maxReconnectDelay,
    double? backoffMultiplier,
    HttpClient? httpClient,
    BadCertificateCallback? badCertificateCallback,
  }) {
    return WebSocketConfig(
      url: url ?? this.url,
      protocols: protocols ?? this.protocols,
      headers: headers ?? this.headers,
      pingInterval: pingInterval ?? this.pingInterval,
      connectionTimeout: connectionTimeout ?? this.connectionTimeout,
      reconnectDelay: reconnectDelay ?? this.reconnectDelay,
      maxReconnectAttempts: maxReconnectAttempts ?? this.maxReconnectAttempts,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      enableLogging: enableLogging ?? this.enableLogging,
      enableHeartbeat: enableHeartbeat ?? this.enableHeartbeat,
      heartbeatInterval: heartbeatInterval ?? this.heartbeatInterval,
      heartbeatTimeout: heartbeatTimeout ?? this.heartbeatTimeout,
      heartbeatMessage: heartbeatMessage ?? this.heartbeatMessage,
      expectedPongMessage: expectedPongMessage ?? this.expectedPongMessage,
      maxMissedHeartbeats: maxMissedHeartbeats ?? this.maxMissedHeartbeats,
      useExponentialBackoff: useExponentialBackoff ?? this.useExponentialBackoff,
      maxReconnectDelay: maxReconnectDelay ?? this.maxReconnectDelay,
      backoffMultiplier: backoffMultiplier ?? this.backoffMultiplier,
      httpClient: httpClient ?? this.httpClient,
      badCertificateCallback:
          badCertificateCallback ?? this.badCertificateCallback,
    );
  }

  @override
  String toString() {
    return 'WebSocketConfig(url: $url, protocols: $protocols, autoReconnect: $autoReconnect, enableHeartbeat: $enableHeartbeat)';
  }
}
