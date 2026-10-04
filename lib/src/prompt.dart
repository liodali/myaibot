/// System prompt composition with per-project knowledge bases.
///
/// One bot serves every project: the webhook's inbox id selects the project
/// (see AppConfig.projectFor), and the matching knowledge base under
/// `PROJECTS_ROOT/<project>/knowledge/faq.md` is injected into the system
/// prompt. An optional `PROJECTS_ROOT/<project>/persona.md` overrides the
/// global SYSTEM_PROMPT for that project.
library;

import 'dart:io';

import '../src/config.dart';
import '../src/logger.dart';

final Map<String, String> _knowledgeCache = {};
final Map<String, String> _personaCache = {};

String _readOrEmpty(String path, String what) {
  try {
    return File(path).readAsStringSync().trim();
  } catch (_) {
    return '';
  }
}

String _knowledgePath(AppConfig config, String project) =>
    '${config.projectsRoot}/$project/knowledge/faq.md';

String _personaPath(AppConfig config, String project) =>
    '${config.projectsRoot}/$project/persona.md';

/// Load (and cache) a project's knowledge base.
String loadKnowledgeFor(AppConfig config, String project) {
  return _knowledgeCache.putIfAbsent(project, () {
    final path = _knowledgePath(config, project);
    final text = _readOrEmpty(path, 'knowledge');
    if (text.isEmpty) {
      logger.warn(
        'No knowledge base for project "$project" '
        '($path) — replying with persona only',
      );
    } else {
      logger.info(
        'Loaded "$project" knowledge base '
        '(${text.length} chars)',
      );
    }
    return text;
  });
}

/// Persona for a project: optional persona.md, else the global prompt.
String personaFor(AppConfig config, String project) {
  return _personaCache.putIfAbsent(project, () {
    final text = _readOrEmpty(_personaPath(config, project), 'persona');
    return text.isEmpty ? config.systemPrompt : text;
  });
}

/// Compose the system prompt for [project], appending its knowledge base.
String buildSystemPrompt(AppConfig config, String project) {
  final knowledge = loadKnowledgeFor(config, project);
  final persona = personaFor(config, project);
  if (knowledge.isEmpty) return persona;

  return [
    persona,
    '',
    '# Knowledge base',
    'Use the following when relevant. If the answer is not here, offer to hand off to a human.',
    '',
    knowledge,
  ].join('\n');
}
