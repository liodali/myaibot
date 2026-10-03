/// Send a fake "message_created" webhook to the bot, signed exactly like
/// Chatwoot.
///
/// Usage:
///   BOT_SECRET=xxx dart run bin/simulate_webhook.dart "How do I reset my password?"
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

Future<void> main(List<String> args) async {
  final env = Platform.environment;
  final webhookUrl = env['WEBHOOK_URL'] ?? 'http://localhost:3000/webhook';
  final secret = env['BOT_SECRET'] ?? '';
  final accountId = int.tryParse(env['ACCOUNT_ID'] ?? '1') ?? 1;
  final conversationId = int.tryParse(env['CONVERSATION_ID'] ?? '1') ?? 1;
  final message = args.isNotEmpty ? args.join(' ') : 'Hello, can you help me?';

  final body = jsonEncode({
    'event': 'message_created',
    'id': DateTime.now().millisecondsSinceEpoch,
    'content': message,
    'message_type': 'incoming',
    'private': false,
    'account': {'id': accountId},
    'conversation': {'id': conversationId, 'status': 'pending'},
    'sender': {'id': 1, 'type': 'contact', 'name': 'Test Contact'},
    'inbox': {'id': 1},
  });

  final headers = <String, String>{'Content-Type': 'application/json'};
  if (secret.isNotEmpty) {
    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    headers['X-Chatwoot-Timestamp'] = ts;
    headers['X-Chatwoot-Signature'] =
        'sha256=${Hmac(sha256, utf8.encode(secret)).convert(utf8.encode('$ts.$body')).toString()}';
  }

  final request = await HttpClient().openUrl('POST', Uri.parse(webhookUrl))
    ..followRedirects = false;
  headers.forEach(request.headers.set);
  final payload = utf8.encode(body);
  request.headers.contentLength = payload.length;
  request.add(payload);

  final response = await request.close();
  final text = await response.transform(utf8.decoder).join();
  print('HTTP ${response.statusCode}: $text');
  exit(response.statusCode >= 200 && response.statusCode < 300 ? 0 : 1);
}
