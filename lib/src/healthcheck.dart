/// Container healthcheck: exit 0 when /health responds 200.
/// Shared by `bin/server.dart --healthcheck` (inside containers, where no
/// shell or curl exists) and `bin/healthcheck.dart` (for local use).
library;

import 'dart:io';

const healthcheckPortEnv = 'HEALTHCHECK_PORT';

Future<void> runHealthcheck() async {
  final port =
      int.tryParse(Platform.environment[healthcheckPortEnv] ?? '') ?? 3000;
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    final request = await client.getUrl(
      Uri.parse('http://localhost:$port/health'),
    );
    final response = await request.close();
    await response.drain<void>();
    exit(response.statusCode == 200 ? 0 : 1);
  } catch (_) {
    exit(1);
  }
}
