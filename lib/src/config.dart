/// Environment-backed configuration with a minimal `.env` loader.
///
/// Values from a `.env` file (if present) are merged in, but real
/// environment variables always win.
library;

import 'dart:io';

/// Load KEY=VALUE pairs from `.env` if present. Existing environment
/// variables always win. Lines starting with `#` are comments.
void _loadDotEnv([String path = '.env']) {
  final file = File(path);
  if (!file.existsSync()) return;

  for (final rawLine in file.readAsLinesSync()) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final eq = line.indexOf('=');
    if (eq <= 0) continue;

    final key = line.substring(0, eq).trim();
    var value = line.substring(eq + 1).trim();
    if (value.length >= 2 &&
        (value.startsWith("'") && value.endsWith("'") ||
            value.startsWith('"') && value.endsWith('"'))) {
      value = value.substring(1, value.length - 1);
    }
    // `export KEY=VALUE` style is tolerated.
    final envKey = key == 'export' ? '' : key;
    if (envKey.isEmpty) continue;
    if (Platform.environment[key] == null) {
      _dotEnv[key] = value;
    }
  }
}

final Map<String, String> _dotEnv = {}; // populated lazily below
bool _loaded = false;

String? _lookup(String name) {
  if (!_loaded) {
    _loadDotEnv();
    _loaded = true;
  }
  return Platform.environment[name] ?? _dotEnv[name];
}

String optionalEnv(String name, String fallback) {
  final value = _lookup(name);
  return (value == null || value.isEmpty) ? fallback : value;
}

String requiredEnv(String name) {
  final value = _lookup(name);
  if (value == null || value.isEmpty) {
    throw StateError('Missing required environment variable: $name');
  }
  return value;
}

bool boolEnv(String name, bool fallback) {
  final value = _lookup(name);
  if (value == null || value.isEmpty) return fallback;
  return const {'1', 'true', 'yes', 'on'}.contains(value.toLowerCase());
}

int intEnv(String name, int fallback) {
  final value = _lookup(name);
  if (value == null || value.isEmpty) return fallback;
  return int.tryParse(value) ?? fallback;
}

double doubleEnv(String name, double fallback) {
  final value = _lookup(name);
  if (value == null || value.isEmpty) return fallback;
  return double.tryParse(value) ?? fallback;
}

String _trimUrl(String url) => url.replaceAll(RegExp(r'/+$'), '');

/// Parse "inboxId:project,inboxId:project" into a routing map.
Map<int, String> parseProjectsMap(String raw) {
  final map = <int, String>{};
  for (final entry in raw.split(',')) {
    final t = entry.trim();
    if (t.isEmpty) continue;
    final idx = t.indexOf(':');
    if (idx <= 0) continue;
    final id = int.tryParse(t.substring(0, idx).trim());
    final name = t.substring(idx + 1).trim();
    if (id != null && name.isNotEmpty) map[id] = name;
  }
  return map;
}

class LlmConfig {
  final String baseUrl;
  final String model;
  final String apiKey;
  final double temperature;
  final int maxTokens;

  const LlmConfig({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    required this.temperature,
    required this.maxTokens,
  });
}

class AppConfig {
  final int port;
  final String host;
  final String logLevel;

  final String chatwootUrl;
  final String botToken;
  final String botSecret;

  final LlmConfig llm;

  final String systemPrompt;
  final String projectsRoot;
  final String defaultProject;
  final Map<int, String> projectsMap;

  /// Which project's knowledge applies to a chat from [inboxId]?
  /// Unmapped inboxes fall back to [defaultProject].
  String projectFor(int? inboxId) =>
      inboxId == null
          ? defaultProject
          : (projectsMap[inboxId] ?? defaultProject);
  final int maxHistory;
  final bool onlyWhenPending;
  final String handoffKeyword;

  AppConfig._({
    required this.projectsRoot,
    required this.defaultProject,
    required this.projectsMap,
    required this.port,
    required this.host,
    required this.logLevel,
    required this.chatwootUrl,
    required this.botToken,
    required this.botSecret,
    required this.llm,
    required this.systemPrompt,
    required this.maxHistory,
    required this.onlyWhenPending,
    required this.handoffKeyword,
  });

  /// Load configuration from the environment (plus optional `.env` file).
  /// Throws [StateError] when a required variable is missing.
  static AppConfig load() => AppConfig._(
    port: intEnv('PORT', 3000),
    host: optionalEnv('HOST', '0.0.0.0'),
    logLevel: optionalEnv('LOG_LEVEL', 'info'),
    chatwootUrl: _trimUrl(
      optionalEnv('CHATWOOT_URL', 'http://chatwoot_rails_1:3000'),
    ),
    botToken: requiredEnv('BOT_TOKEN'),
    botSecret: optionalEnv('BOT_SECRET', ''),
    llm: LlmConfig(
      baseUrl: _trimUrl(
        optionalEnv('LLM_BASE_URL', 'https://api.groq.com/openai/v1'),
      ),
      model: optionalEnv('LLM_MODEL', 'llama-3.3-70b-versatile'),
      apiKey: requiredEnv('LLM_API_KEY'),
      temperature: doubleEnv('LLM_TEMPERATURE', 0.3),
      maxTokens: intEnv('LLM_MAX_TOKENS', 500),
    ),
    systemPrompt: optionalEnv(
      'SYSTEM_PROMPT',
      'You are a friendly, concise customer support assistant. '
          "Reply in the customer's language.",
    ),
    projectsRoot: optionalEnv('PROJECTS_ROOT', '/app/projects'),
    defaultProject: optionalEnv('DEFAULT_PROJECT', 'default'),
    projectsMap: parseProjectsMap(optionalEnv('PROJECTS_MAP', '')),
    maxHistory: intEnv('MAX_HISTORY', 10),
    onlyWhenPending: boolEnv('ONLY_WHEN_PENDING', true),
    handoffKeyword: optionalEnv('HANDOFF_KEYWORD', '[HANDOFF]'),
  );
}
