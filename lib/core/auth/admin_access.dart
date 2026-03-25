import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';
import '../config/supabase_bootstrap.dart';

enum AppUserRole { staff, admin }

final appUserRoleProvider = Provider<AppUserRole>((ref) {
  final client = SupabaseBootstrap.client;
  final user = client?.auth.currentUser;

  if (user == null) {
    return _isProdEnvironment() ? AppUserRole.staff : AppUserRole.admin;
  }

  final appRole = _readRole(user.appMetadata);
  if (appRole != null) {
    return appRole;
  }

  final userRole = _readRole(user.userMetadata);
  if (userRole != null) {
    return userRole;
  }

  return _isProdEnvironment() ? AppUserRole.staff : AppUserRole.admin;
});

final isAdminProvider = Provider<bool>(
  (ref) => ref.watch(appUserRoleProvider) == AppUserRole.admin,
);

AppUserRole? _readRole(Map<String, dynamic>? metadata) {
  if (metadata == null) {
    return null;
  }

  final direct = metadata['role'];
  final directRole = _parseRole(direct);
  if (directRole != null) {
    return directRole;
  }

  final roles = metadata['roles'];
  if (roles is Iterable) {
    for (final value in roles) {
      final role = _parseRole(value);
      if (role != null) {
        return role;
      }
    }
  }

  return null;
}

AppUserRole? _parseRole(Object? raw) {
  final value = '$raw'.trim().toLowerCase();
  if (value == 'admin' || value == 'administrator') {
    return AppUserRole.admin;
  }
  if (value == 'staff' || value == 'user') {
    return AppUserRole.staff;
  }
  return null;
}

bool _isProdEnvironment() {
  try {
    return Env.appEnv == 'prod';
  } catch (_) {
    return false;
  }
}