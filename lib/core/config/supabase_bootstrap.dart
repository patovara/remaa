import 'package:supabase_flutter/supabase_flutter.dart';

import '../logging/app_logger.dart';
import 'env.dart';

class SupabaseBootstrap {
  static bool _initialized = false;

  static bool get isConfigured => Env.supabaseUrl.isNotEmpty && Env.supabaseAnonKey.isNotEmpty;
  static bool get isInitialized => _initialized;
  static SupabaseClient? get client => _initialized ? Supabase.instance.client : null;

  static Future<void> initialize() async {
    if (_initialized || !isConfigured) {
      if (!isConfigured) {
        AppLogger.info('supabase_skipped', data: {'reason': 'missing_env'});
      }
      return;
    }

    try {
      await Supabase.initialize(
        url: Env.supabaseUrl,
        anonKey: Env.supabaseAnonKey,
      );
      _initialized = true;
      AppLogger.info('supabase_initialized');
    } catch (error) {
      AppLogger.error('supabase_init_failed', data: {'error': error.toString()});
    }
  }
}