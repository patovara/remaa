import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/config/env.dart';
import 'core/config/supabase_bootstrap.dart';
import 'core/logging/app_logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const envFileFromDefine = String.fromEnvironment('ENV_FILE', defaultValue: '');

  final candidates = <String>[
    if (envFileFromDefine.isNotEmpty) envFileFromDefine,
    if (envFileFromDefine.isEmpty && kReleaseMode) '.env.production',
    if (envFileFromDefine.isEmpty && !kReleaseMode) '.env',
    '.env.production',
    '.env',
    '.env.example',
  ];

  var loaded = false;
  for (final file in candidates.toSet()) {
    try {
      await dotenv.load(fileName: file);
      loaded = true;
      break;
    } catch (_) {
      // Continue until a valid env file is loaded.
    }
  }

  if (!loaded) {
    throw StateError('No se pudo cargar ningun archivo de entorno.');
  }

  Env.init();
  await SupabaseBootstrap.initialize();
  AppLogger.info('app_start', data: {
    'env': Env.appEnv,
    'supabase': SupabaseBootstrap.isInitialized ? 'enabled' : 'disabled',
    'billing': Env.billingEnabled ? 'enabled' : 'disabled',
  });

  runApp(const ProviderScope(child: RemaApp()));
}
