/// Chatwoot webhook signature verification.
///
/// Chatwoot sends:
///   `X-Chatwoot-Timestamp: <unix seconds>`
///   `X-Chatwoot-Signature: sha256=<HMAC_SHA256(secret, "<timestamp>.<rawBody>") hex>`
///
/// If no secret is configured, verification is skipped (development only).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Constant-time equality check for equal-length byte lists.
bool _timingSafeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

bool verifySignature(
  String secret,
  String rawBody,
  String? timestamp,
  String? signature,
) {
  if (secret.isEmpty) return true;
  if (timestamp == null ||
      timestamp.isEmpty ||
      signature == null ||
      signature.isEmpty) {
    return false;
  }

  final expected =
      'sha256=${Hmac(sha256, utf8.encode(secret)).convert(utf8.encode('$timestamp.$rawBody')).toString()}';

  return _timingSafeEquals(
    Uint8List.fromList(utf8.encode(expected)),
    Uint8List.fromList(utf8.encode(signature)),
  );
}
