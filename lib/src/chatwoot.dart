/// Chatwoot Agent Bot API client.
library;

import '../src/config.dart';
import '../src/http_json.dart';
import '../src/logger.dart';
import '../src/types.dart';

Map<String, String> _authHeaders(AppConfig config) => {
  'Content-Type': 'application/json',
  'api_access_token': config.botToken,
  // Rails runs with FORCE_SSL; the proxy normally proves the original
  // scheme via this header. We call rails directly on the internal
  // network, so we send it ourselves to avoid the http->https 301.
  'X-Forwarded-Proto': 'https',
};

String _messagesUrl(AppConfig config, int accountId, int conversationId) =>
    '${config.chatwootUrl}/api/v1/accounts/$accountId/'
    'conversations/$conversationId/messages';

String _conversationUrl(AppConfig config, int accountId, int conversationId) =>
    '${config.chatwootUrl}/api/v1/accounts/$accountId/'
    'conversations/$conversationId';

List<ChatwootMessage> _parseMessages(dynamic payload) {
  if (payload is! List) return const [];
  return payload
      .whereType<Map<String, dynamic>>()
      .map(ChatwootMessage.fromJson)
      .toList();
}

/// Fetch conversation messages (oldest → newest).
Future<List<ChatwootMessage>> fetchMessages(
  AppConfig config,
  int accountId,
  int conversationId,
) async {
  final body = await httpJson(
    'GET',
    Uri.parse(_messagesUrl(config, accountId, conversationId)),
    headers: _authHeaders(config),
  );

  // The API returns {"payload": [...]} (or a bare array, which the helper
  // wraps under '@value').
  return _parseMessages(body['payload'] ?? body['@value']);
}

/// Post an outgoing message (or private note) into a conversation.
Future<void> postMessage(
  AppConfig config,
  int accountId,
  int conversationId,
  String content, {
  bool privateNote = false,
}) async {
  await httpJson(
    'POST',
    Uri.parse(_messagesUrl(config, accountId, conversationId)),
    headers: _authHeaders(config),
    body: {
      'content': content,
      'message_type': 'outgoing',
      'private': privateNote,
    },
  );
  logger.debug(
    'Posted ${privateNote ? 'private note' : 'reply'} to conversation $conversationId',
  );
}

/// Change a conversation status (open | pending | resolved).
Future<void> setStatus(
  AppConfig config,
  int accountId,
  int conversationId,
  String status,
) async {
  await httpJson(
    'POST',
    Uri.parse(
      '${_conversationUrl(config, accountId, conversationId)}/toggle_status',
    ),
    headers: _authHeaders(config),
    body: {'status': status},
  );
  logger.debug('Set conversation $conversationId status -> $status');
}
