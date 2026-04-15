import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_bootstrap.dart';

class WeeklyQuoteSummaryRepository {
  SupabaseClient get _client {
    final client = SupabaseBootstrap.client;
    if (client == null) {
      throw StateError('Supabase no esta inicializado.');
    }
    return client;
  }

  Map<String, String> _authHeaders() {
    final accessToken = _client.auth.currentSession?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('Sesion expirada. Inicia sesion de nuevo.');
    }
    return {
      'Authorization': 'Bearer $accessToken',
    };
  }

  Future<void> resendNow() async {
    final response = await _client.functions.invoke(
      'weekly-quote-summary',
      headers: _authHeaders(),
      body: {'action': 'resend_now'},
    );

    final data = response.data;
    if (data is Map<String, dynamic> && data['error'] != null) {
      throw StateError(data['error'].toString());
    }

    if (response.status >= 400) {
      throw StateError('No fue posible reenviar el resumen semanal.');
    }
  }
}
