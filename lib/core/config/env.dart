import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  static late final String appEnv;
  static late final String supabaseUrl;
  static late final String supabaseAnonKey;

  static void init() {
    appEnv = dotenv.env['APP_ENV'] ?? 'dev';
    supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
    supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  }
}
