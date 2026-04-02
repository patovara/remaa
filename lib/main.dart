import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/config/env.dart';
import 'core/config/supabase_bootstrap.dart';
import 'core/logging/app_logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const envFile = String.fromEnvironment('ENV_FILE', defaultValue: '.env');

  try {
    await dotenv.load(fileName: envFile);
  } catch (_) {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      await dotenv.load(fileName: '.env.example');
    }
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
