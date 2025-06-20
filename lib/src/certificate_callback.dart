import "dart:io";

/// Callback for when a TLS certificate fails validation.
typedef CertificateErrorCallback = void Function(
  X509Certificate cert,
  String host,
  int port,
);
