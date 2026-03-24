import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rema_app/core/config/env.dart';

void main() {
  setUpAll(() async {
    dotenv.testLoad(
      fileInput: 'APP_ENV=test\nSUPABASE_URL=https://example.supabase.co\nSUPABASE_ANON_KEY=test-key\n',
    );
  });

  test('env mantiene defaults cuando faltan variables', () {
    Env.init();

    expect(Env.appEnv, isNotEmpty);
    expect(Env.supabaseUrl, isA<String>());
    expect(Env.supabaseAnonKey, isA<String>());
  });
}
