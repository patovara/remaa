import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_bootstrap.dart';

class AuthRepository {
  SupabaseClient get _client {
    final client = SupabaseBootstrap.client;
    if (client == null) {
      throw StateError('Supabase no esta inicializado.');
    }
    return client;
  }

  Session? get currentSession => _client.auth.currentSession;

  Stream<AuthState> authStateChanges() => _client.auth.onAuthStateChange;

  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) {
    return _client.auth.signUp(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() => _client.auth.signOut();

  Future<void> updatePassword(String newPassword) {
    return _client.auth.updateUser(
      UserAttributes(password: newPassword),
    );
  }

  Future<void> updateProfile({
    String? fullName,
    String? jobTitle,
  }) {
    final data = <String, dynamic>{};
    if (fullName != null) data['full_name'] = fullName;
    if (jobTitle != null) data['job_title'] = jobTitle;
    return _client.auth.updateUser(
      UserAttributes(data: data),
    );
  }

  Future<void> updatePreferences(Map<String, dynamic> prefs) {
    return _client.auth.updateUser(
      UserAttributes(data: prefs),
    );
  }

  Future<void> signOutAll() {
    return _client.auth.signOut(scope: SignOutScope.global);
  }
}
