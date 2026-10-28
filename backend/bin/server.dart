import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf_io.dart' as io;
import 'package:whiskers_backend/whiskers_backend.dart';

/// Starts the Whiskers backend.
///
/// Settings come from environment variables; a `.env` file in the current
/// folder is read too (real environment variables win over it).
Future<void> main() async {
  final env = <String, String>{};
  final file = File('.env');
  if (file.existsSync()) env.addAll(parseEnvFile(file.readAsStringSync()));
  env.addAll(Platform.environment);

  final ServerConfig config;
  try {
    config = ServerConfig.fromEnv(env);
  } on ConfigException catch (e) {
    stderr.writeln('Configuration error: $e');
    exit(64); // "command line usage error"
  }

  final handler = buildHandler(
    config: config,
    services: servicesFromConfig(config),
  );
  final server = await io.serve(handler, InternetAddress.anyIPv4, config.port);
  // Only names and numbers here, never keys or the token secret.
  stdout.writeln(
    'Whiskers backend listening on port ${server.port} '
    '(provider: ${config.provider.name}, '
    'daily cap: ${config.dailyRequestCap})',
  );

  // Docker / Cloud Run send SIGTERM to stop: finish current requests first.
  var stopping = false;
  Future<void> shutdown(ProcessSignal signal) async {
    if (stopping) return;
    stopping = true;
    stdout.writeln('Received $signal, shutting down...');
    await server
        .close(force: false)
        .timeout(
          const Duration(seconds: 20),
          onTimeout: () => server.close(force: true),
        );
    exit(0);
  }

  ProcessSignal.sigterm.watch().listen(shutdown);
  ProcessSignal.sigint.watch().listen(shutdown);
}
