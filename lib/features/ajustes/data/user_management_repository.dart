import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_bootstrap.dart';

class ManagedUser {
  const ManagedUser({
    required this.id,
    required this.email,
    required this.role,
    required this.isActive,
    required this.emailConfirmed,
    required this.createdAt,
  });

  final String id;
  final String email;
  final String role;
  final bool isActive;
  final bool emailConfirmed;
  final DateTime? createdAt;

  factory ManagedUser.fromJson(Map<String, dynamic> json) {
    return ManagedUser(
      id: (json['id'] as String? ?? '').trim(),
      email: (json['email'] as String? ?? '').trim(),
      role: (json['role'] as String? ?? 'staff').trim(),
      isActive: json['is_active'] as bool? ?? true,
      emailConfirmed: json['email_confirmed'] as bool? ?? false,
      createdAt: DateTime.tryParse((json['created_at'] as String? ?? '').trim()),
    );
  }
}

class UserManagementRepository {
  SupabaseClient get _client {
    final client = SupabaseBootstrap.client;
    if (client == null) {
      throw StateError('Supabase no esta inicializado.');
    }
    return client;
  }

  Future<List<ManagedUser>> listUsers() async {
    final response = await _client.functions.invoke(
      'user-admin',
      body: {'action': 'list_users'},
    );

    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw StateError('Respuesta invalida al listar usuarios.');
    }

    final usersRaw = data['users'];
    if (usersRaw is! List) {
      return const [];
    }

    return [
      for (final item in usersRaw)
        if (item is Map<String, dynamic>) ManagedUser.fromJson(item),
    ];
  }

  Future<void> inviteUser({
    required String email,
    required String role,
    String? redirectTo,
  }) async {
    await _invokeAction(
      action: 'invite_user',
      payload: {
        'email': email.trim(),
        'role': role.trim().toLowerCase(),
        if (redirectTo != null && redirectTo.isNotEmpty) 'redirect_to': redirectTo,
      },
    );
  }

  Future<void> updateUserRole({
    required String userId,
    required String role,
  }) async {
    await _invokeAction(
      action: 'update_role',
      payload: {
        'user_id': userId,
        'role': role.trim().toLowerCase(),
      },
    );
  }

  Future<void> setUserActive({
    required String userId,
    required bool isActive,
  }) async {
    await _invokeAction(
      action: 'set_active',
      payload: {
        'user_id': userId,
        'is_active': isActive,
      },
    );
  }

  Future<void> resetPassword({required String userId, String? redirectTo}) async {
    await _invokeAction(
      action: 'reset_password',
      payload: {
        'user_id': userId,
        if (redirectTo != null && redirectTo.isNotEmpty) 'redirect_to': redirectTo,
      },
    );
  }

  Future<void> resendInvite({required String userId, String? redirectTo}) async {
    await _invokeAction(
      action: 'resend_invite',
      payload: {
        'user_id': userId,
        if (redirectTo != null && redirectTo.isNotEmpty) 'redirect_to': redirectTo,
      },
    );
  }

  Future<void> _invokeAction({
    required String action,
    required Map<String, dynamic> payload,
  }) async {
    final response = await _client.functions.invoke(
      'user-admin',
      body: {
        'action': action,
        ...payload,
      },
    );

    final data = response.data;
    if (data is Map<String, dynamic> && data['error'] != null) {
      throw StateError(data['error'].toString());
    }

    if (response.status >= 400) {
      throw StateError('No fue posible completar la operacion de usuarios.');
    }
  }
}
