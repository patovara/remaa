import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  static late final String appEnv;
  static late final String appPublicUrl;
  static late final String supabaseUrl;
  static late final String supabaseAnonKey;
  static late final bool billingEnabled;

  static void init() {
    appEnv = dotenv.env['APP_ENV'] ?? 'dev';
    appPublicUrl = dotenv.env['APP_PUBLIC_URL'] ?? '';
    supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
    supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
    billingEnabled = _parseBool(dotenv.env['ENABLE_BILLING']);
  }

  static bool _parseBool(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case '1':
      case 'true':
      case 'yes':
      case 'on':
        return true;
      default:
        return false;
    }
  }
}
