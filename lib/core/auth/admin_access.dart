import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_bootstrap.dart';

const _ownerEmail = 'mvazquez@gruporemaa.com';

enum AppUserRole { staff, admin, superAdmin }

final appUserRoleProvider = Provider<AppUserRole>((ref) {
  final client = SupabaseBootstrap.client;
  final user = client?.auth.currentUser;

  if (user == null) {
    return AppUserRole.staff;
  }

  if (user.email?.trim().toLowerCase() == _ownerEmail) {
    return AppUserRole.superAdmin;
  }

  final appRole = _readRole(user.appMetadata);
  if (appRole != null) {
    return appRole;
  }

  final userRole = _readRole(user.userMetadata);
  if (userRole != null) {
    return userRole;
  }

  return AppUserRole.staff;
});

final isAdminProvider = Provider<bool>(
  (ref) {
    final role = ref.watch(appUserRoleProvider);
    return role == AppUserRole.admin || role == AppUserRole.superAdmin;
  },
);

final isSuperAdminProvider = Provider<bool>(
  (ref) => ref.watch(appUserRoleProvider) == AppUserRole.superAdmin,
);

final currentUserProvider = Provider<User?>((ref) {
  return SupabaseBootstrap.client?.auth.currentUser;
});

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
  if (value == 'super_admin' || value == 'superadmin' || value == 'owner') {
    return AppUserRole.superAdmin;
  }
  if (value == 'admin' || value == 'administrator') {
    return AppUserRole.admin;
  }
  if (value == 'staff' || value == 'user') {
    return AppUserRole.staff;
  }
  return null;
}
