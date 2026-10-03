/// OpenAI-compatible /chat/completions client.
library;

import '../src/config.dart';
import '../src/http_json.dart';
import '../src/logger.dart';

enum Role { system, user, assistant }

class ChatMessage {
  final Role role;
  final String content;
  const ChatMessage(this.role, this.content);

  Map<String, dynamic> toJson() => {'role': role.name, 'content': content};
}

/// Call an OpenAI-compatible /chat/completions endpoint.
Future<String> chat(AppConfig config, List<ChatMessage> messages) async {
  final started = DateTime.now();

  final data = await httpJson(
    'POST',
    Uri.parse('${config.llm.baseUrl}/chat/completions'),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${config.llm.apiKey}',
    },
    body: {
      'model': config.llm.model,
      'messages': messages.map((m) => m.toJson()).toList(),
      'temperature': config.llm.temperature,
      'max_tokens': config.llm.maxTokens,
    },
  );

  final choices = data['choices'];
  String? content;
  if (choices is List && choices.isNotEmpty) {
    final choice = choices.first;
    if (choice is Map<String, dynamic>) {
      final message = choice['message'];
      if (message is Map<String, dynamic>) {
        content = message['content']?.toString();
      }
    }
  }
  final trimmed = content?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    throw StateError('LLM returned an empty response');
  }

  final elapsed = DateTime.now().difference(started).inMilliseconds;
  logger.debug('LLM replied in ${elapsed}ms (${trimmed.length} chars)');
  return trimmed;
}
