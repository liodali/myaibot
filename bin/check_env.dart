/// Print the effective configuration (for quick sanity checks).
library;

import 'dart:convert';

import 'package:my_ai_bot/my_ai_bot.dart';

Future<void> main() async {
  final config = AppConfig.load();
  print('Configuration loaded OK\n');
  print(
    const JsonEncoder.withIndent('  ').convert({
      'chatwootUrl': config.chatwootUrl,
      'llmBaseUrl': config.llm.baseUrl,
      'model': config.llm.model,
      'onlyWhenPending': config.onlyWhenPending,
      'handoffKeyword': config.handoffKeyword,
      'projectsRoot': config.projectsRoot,
      'defaultProject': config.defaultProject,
      'projectsMap': config.projectsMap,
      'projectsNameMap': config.projectsNameMap,
      'maxHistory': config.maxHistory,
      'signatureVerification': config.botSecret.isNotEmpty,
    }),
  );
}
