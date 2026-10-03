/// Standalone healthcheck (local use). In containers, the compiled server
/// binary is invoked with `--healthcheck` instead — see bin/server.dart.
library;

import 'package:my_ai_bot/my_ai_bot.dart';

Future<void> main() => runHealthcheck();
