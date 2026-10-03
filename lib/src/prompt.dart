/// System prompt composition with an in-memory knowledge base.
library;

import 'dart:io';

import '../src/config.dart';
import '../src/logger.dart';

String? _cache;

/// Load the markdown knowledge base once and keep it in memory.
Future<String> loadKnowledge(AppConfig config) async {
  if (_cache != null) return _cache!;
  try {
    _cache = (await File(config.knowledgeFile).readAsString()).trim();
    logger.info(
      'Loaded knowledge base (${_cache!.length} chars) from ${config.knowledgeFile}',
    );
  } catch (_) {
    _cache = '';
    logger.warn(
      'Knowledge file not found: ${config.knowledgeFile} (continuing without it)',
    );
  }
  return _cache!;
}

/// Compose the system prompt, appending the knowledge base when present.
Future<String> buildSystemPrompt(AppConfig config) async {
  final knowledge = await loadKnowledge(config);
  if (knowledge.isEmpty) return config.systemPrompt;

  return [
    config.systemPrompt,
    '',
    '# Knowledge base',
    'Use the following when relevant. If the answer is not here, offer to hand off to a human.',
    '',
    knowledge,
  ].join('\n');
}
