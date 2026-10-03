import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:relic/relic.dart';

import 'package:my_ai_bot/my_ai_bot.dart';

/// Fetch the first value of a header, case-insensitively.
/// dart:io normalizes header names to lowercase, but be defensive anyway.
String? _header(Request req, String name) =>
    req.headers[name.toLowerCase()]?.firstOrNull ??
    req.headers[name]?.firstOrNull;

Body _jsonBody(Object data) =>
    Body.fromString(jsonEncode(data), mimeType: MimeType.json);

Future<Response> _health(AppConfig config, Request req) async {
  return Response.ok(
    body: _jsonBody({
      'ok': true,
      'model': config.llm.model,
      'signatureVerification': config.botSecret.isNotEmpty,
    }),
  );
}

Future<Response> _webhook(AppConfig config, Request req) async {
  final raw = await req.readAsString();

  final valid = verifySignature(
    config.botSecret,
    raw,
    _header(req, 'x-chatwoot-timestamp'),
    _header(req, 'x-chatwoot-signature'),
  );
  if (!valid) {
    logger.warn('Rejected webhook with invalid signature');
    return Response.unauthorized(body: Body.fromString('invalid signature'));
  }

  final ChatwootEvent event;
  try {
    event = ChatwootEvent.parse(raw);
  } on FormatException {
    return Response.badRequest(body: Body.fromString('invalid json'));
  }

  // Answer in the background so Chatwoot receives a fast 200 (avoids retries).
  unawaited(
    handleIncoming(config, event).catchError((Object err, StackTrace stack) {
      logger.error('handler failed', err, stack);
    }),
  );

  return Response.ok(body: _jsonBody({'accepted': true}));
}

Future<void> main(List<String> args) async {
  // `bot --healthcheck` lets minimal (distroless) containers probe the
  // running server without a shell, curl, or a Dart SDK.
  if (args.contains('--healthcheck')) {
    return runHealthcheck();
  }

  final AppConfig config;
  try {
    config = AppConfig.load();
  } on StateError catch (err) {
    stderr.writeln('$err');
    exit(1);
  }

  final host = config.host;
  final address = switch (host) {
    '0.0.0.0' || '' => InternetAddress.anyIPv4,
    '127.0.0.1' || 'localhost' => InternetAddress.loopbackIPv4,
    _ => await InternetAddress.lookup(
      host,
    ).then((addrs) => addrs.first, onError: (_) => InternetAddress.anyIPv4),
  };

  final app =
      RelicApp()
        ..get('/health', (req) => _health(config, req))
        ..post('/webhook', (req) => _webhook(config, req))
        ..fallback = respondWith(
          (_) => Response.notFound(body: Body.fromString('Not found')),
        );

  await app.serve(address: address, port: config.port);

  if (config.botSecret.isEmpty) {
    logger.warn(
      'BOT_SECRET is empty — webhook signature verification is '
      'DISABLED. Set it in production.',
    );
  }
  logger.info(
    'MyAIBot listening on :${config.port} '
    '(model=${config.llm.model}, chatwoot=${config.chatwootUrl})',
  );
}
