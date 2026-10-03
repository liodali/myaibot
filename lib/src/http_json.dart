/// Tiny JSON-over-HTTP helper built on dart:io HttpClient.
///
/// Keeps the runtime dependency surface minimal (relic + crypto only),
/// matching the original service's "zero-deps" ethos.
library;

import 'dart:convert';
import 'dart:io';

class HttpJsonException implements Exception {
  final int statusCode;
  final String body;
  HttpJsonException(this.statusCode, this.body);

  @override
  String toString() => 'HTTP $statusCode: $body';
}

final _client = HttpClient()..connectionTimeout = const Duration(seconds: 30);

Future<Map<String, dynamic>> httpJson(
  String method,
  Uri uri, {
  Map<String, String> headers = const {},
  Object? body,
}) async {
  final request = await _client.openUrl(method, uri);
  headers.forEach(request.headers.set);
  if (body != null) {
    final payload = utf8.encode(jsonEncode(body));
    request.headers.contentLength = payload.length;
    request.add(payload);
  }

  final response = await request.close();
  final text = await response.transform(utf8.decoder).join();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpJsonException(response.statusCode, text);
  }
  if (text.isEmpty) return {};
  final decoded = jsonDecode(text);
  return decoded is Map<String, dynamic>
      ? decoded
      : <String, dynamic>{'@value': decoded};
}
