/// Core webhook processing: dedup, history assembly, LLM reply, handoff.
library;

import 'dart:collection';

import '../src/chatwoot.dart' as chatwoot;
import '../src/config.dart';
import '../src/llm.dart';
import '../src/logger.dart';
import '../src/prompt.dart';
import '../src/types.dart';

/// Insertion-ordered set of processed message ids (webhook retry dedup).
final LinkedHashSet<int> _processedIds = LinkedHashSet<int>();
const _maxTracked = 5000;

/// Returns false for duplicate message ids (webhook retries).
bool _markProcessed(int id) {
  if (!_processedIds.add(id)) return false;
  if (_processedIds.length > _maxTracked) {
    _processedIds.remove(_processedIds.first);
  }
  return true;
}

List<ChatMessage> _toHistory(AppConfig config, List<ChatwootMessage> messages) {
  final history = <ChatMessage>[];
  for (final m in messages) {
    final content = (m.content ?? '').trim();
    if (content.isEmpty) continue;
    if (m.messageType == 'incoming') {
      history.add(ChatMessage(Role.user, content));
    } else if (m.messageType == 'outgoing' && !m.privateMessage) {
      history.add(ChatMessage(Role.assistant, content));
    }
  }
  final start =
      history.length > config.maxHistory
          ? history.length - config.maxHistory
          : 0;
  return history.sublist(start);
}

Future<void> handleIncoming(AppConfig config, ChatwootEvent event) async {
  if (event.event != 'message_created' || event.messageType != 'incoming') {
    return;
  }

  final accountId = event.accountId;
  final conversationId = event.conversationId;
  final text = (event.content ?? '').toString().trim();
  if (accountId == null || conversationId == null || text.isEmpty) return;

  if (event.id != null && !_markProcessed(event.id!)) {
    logger.debug('Duplicate message ${event.id}, skipping');
    return;
  }

  if (config.onlyWhenPending &&
      event.conversationStatus != null &&
      event.conversationStatus != 'pending') {
    logger.info(
      'Skipping conv=$conversationId '
      '(status=${event.conversationStatus}; a human is handling it)',
    );
    return;
  }

  // Which project's knowledge applies? The inbox id routes the chat.
  final project = config.projectFor(event.inboxId);
  final preview = text.length > 100 ? text.substring(0, 100) : text;
  logger.info(
    'conv=$conversationId account=$accountId '
    'inbox=${event.inboxId} project=$project: $preview',
  );

  var history = <ChatMessage>[];
  try {
    history = _toHistory(
      config,
      await chatwoot.fetchMessages(config, accountId, conversationId),
    );
  } catch (err, stack) {
    logger.warn(
      'Could not load conversation history; replying without context '
      '($err)',
    );
    logger.debug('$stack');
  }

  // Avoid duplicating the current message if it is already the last history turn.
  final last = history.isNotEmpty ? history.last : null;
  if (!(last != null && last.role == Role.user && last.content == text)) {
    history.add(ChatMessage(Role.user, text));
  }

  final systemPrompt = buildSystemPrompt(config, project);
  final answer = await chat(config, [
    ChatMessage(Role.system, systemPrompt),
    ...history,
  ]);

  if (answer.contains(config.handoffKeyword)) {
    final cleaned = answer.replaceAll(config.handoffKeyword, '').trim();
    if (cleaned.isNotEmpty) {
      await chatwoot.postMessage(config, accountId, conversationId, cleaned);
    }
    await chatwoot.postMessage(
      config,
      accountId,
      conversationId,
      '🤖 AI assistant requested a human handoff.',
      privateNote: true,
    );
    await chatwoot.setStatus(config, accountId, conversationId, 'open');
    logger.info('Handed off conv=$conversationId to a human');
    return;
  }

  await chatwoot.postMessage(config, accountId, conversationId, answer);
}
