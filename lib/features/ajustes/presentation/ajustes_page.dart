import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/admin_access.dart';
import '../../../core/config/env.dart';
import '../../../core/config/company_profile.dart';
import '../../../core/theme/rema_colors.dart';
import '../../../core/utils/rema_feedback.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/rema_panels.dart';
import '../../auth/data/auth_repository.dart';
import '../data/user_management_repository.dart';

class AjustesPage extends ConsumerStatefulWidget {
  const AjustesPage({super.key});

  @override
  ConsumerState<AjustesPage> createState() => _AjustesPageState();
}

class _AjustesPageState extends ConsumerState<AjustesPage> {
  final _userRepository = UserManagementRepository();
  late final AuthRepository _authRepository;

  bool _pushAlerts = true;
  bool _emailAlerts = false;
  String _language = 'Espanol (Mexico)';
  String _units = 'Sistema Metrico (m, cm)';
  bool _usersLoading = false;
  String? _usersError;
  List<ManagedUser> _users = const [];

  @override
  void initState() {
    super.initState();
    _authRepository = AuthRepository();
    _loadPreferences();
  }

  void _loadPreferences() {
    final user = ref.read(currentUserProvider);
    if (user != null && user.userMetadata != null) {
      setState(() {
        _pushAlerts = user.userMetadata?['pref_push_alerts'] as bool? ?? true;
        _emailAlerts = user.userMetadata?['pref_email_alerts'] as bool? ?? false;
        _language = (user.userMetadata?['pref_language'] as String?) ?? 'Espanol (Mexico)';
        _units = (user.userMetadata?['pref_units'] as String?) ?? 'Sistema Metrico (m, cm)';
      });
    }
  }

  Future<void> _savePref(String key, Object value) async {
    try {
      await _authRepository.updatePreferences({key: value});
    } catch (_) {
      // Silently fail - UI state is already updated via setState
    }
  }

  Future<void> _refreshUsers() async {
    setState(() {
      _usersLoading = true;
      _usersError = null;
    });
    try {
      final users = await _userRepository.listUsers();
      if (!mounted) {
        return;
      }
      setState(() {
        _users = users;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _usersError = error.toString();
      });
      showRemaMessage(context, 'No fue posible cargar usuarios.');
    } finally {
      if (mounted) {
        setState(() => _usersLoading = false);
      }
    }
  }

  Future<void> _openInviteDialog() async {
    final result = await showDialog<_InviteUserPayload>(
      context: context,
      builder: (context) => const _InviteUserDialog(),
    );
    if (result == null) {
      return;
    }

    try {
      final redirectTo = _inviteRedirectUrl();
      await _userRepository.inviteUser(
        email: result.email,
        role: result.role,
        redirectTo: redirectTo,
      );
      if (!mounted) {
        return;
      }
      showRemaMessage(context, 'Invitacion enviada a ${result.email}.');
      await _refreshUsers();
    } catch (error) {
      if (!mounted) {
        return;
      }
      showRemaMessage(context, 'No fue posible invitar usuario: $error');
    }
  }

  Future<void> _openManageDialog() async {
    await _refreshUsers();
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _ManageUsersDialog(
        users: _users,
        onRefresh: _refreshUsers,
        onSetRole: (userId, role) async {
          await _userRepository.updateUserRole(userId: userId, role: role);
          await _refreshUsers();
        },
        onSetActive: (userId, isActive) async {
          await _userRepository.setUserActive(userId: userId, isActive: isActive);
          await _refreshUsers();
        },
        onResetPassword: (userId) async {
          final redirectTo = _authRedirectUrl('reset');
          await _userRepository.resetPassword(userId: userId, redirectTo: redirectTo);
          if (!dialogContext.mounted) {
            return;
          }
          showRemaMessage(dialogContext, 'Correo de reset enviado.');
        },
        onResendInvite: (userId) async {
          final redirectTo = _authRedirectUrl('invite');
          await _userRepository.resendInvite(userId: userId, redirectTo: redirectTo);
          if (!dialogContext.mounted) {
            return;
          }
          showRemaMessage(dialogContext, 'Invitacion reenviada correctamente.');
          await _refreshUsers();
        },
      ),
    );
  }

  String _inviteRedirectUrl() {
    return _authRedirectUrl('invite');
  }

  String _authRedirectUrl(String mode) {
    final configured = Env.appPublicUrl.trim();
    final base = configured.isNotEmpty ? configured : Uri.base.toString();
    final uri = Uri.parse(base);
    return uri.replace(path: '/register', query: 'mode=$mode').toString();
  }

  Future<void> _openChangePasswordDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _ChangePasswordDialog(
        onSave: (newPassword) async {
          await _authRepository.updatePassword(newPassword);
          if (!dialogContext.mounted) return;
          showRemaMessage(dialogContext, 'Contraseña actualizada exitosamente.');
        },
      ),
    );
  }

  Future<void> _signOutAll() async {
    try {
      await _authRepository.signOutAll();
    } catch (e) {
      if (!mounted) return;
      showRemaMessage(context, 'Error al cerrar sesiones: $e');
    }
    if (mounted) {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSuperAdmin = ref.watch(isSuperAdminProvider);

    return PageFrame(
      title: 'Configuracion',
      subtitle: 'Preferencias operativas, seguridad y notificaciones del sistema.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 1100;
          final mainColumn = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _ProfileHero(),
              const SizedBox(height: 24),
              _SecurityPanel(
                onChangePassword: _openChangePasswordDialog,
                onSignOutAll: _signOutAll,
              ),
              if (isSuperAdmin) ...[
                const SizedBox(height: 24),
                _UsersAdminPanel(
                  isLoading: _usersLoading,
                  errorText: _usersError,
                  usersCount: _users.length,
                  onInviteUser: _openInviteDialog,
                  onManageUsers: _openManageDialog,
                  onReloadUsers: _refreshUsers,
                ),
              ],
              const SizedBox(height: 24),
              _PreferencesPanel(
                language: _language,
                units: _units,
                onLanguageChanged: (value) {
                  setState(() => _language = value);
                  _savePref('pref_language', value);
                },
                onUnitsChanged: (value) {
                  setState(() => _units = value);
                  _savePref('pref_units', value);
                },
              ),
            ],
          );
          final sidebar = _NotificationsPanel(
            pushAlerts: _pushAlerts,
            emailAlerts: _emailAlerts,
            onPushChanged: (value) {
              setState(() => _pushAlerts = value);
              _savePref('pref_push_alerts', value);
            },
            onEmailChanged: (value) {
              setState(() => _emailAlerts = value);
              _savePref('pref_email_alerts', value);
            },
          );

          if (!isWide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [mainColumn, const SizedBox(height: 24), sidebar],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 8, child: mainColumn),
              const SizedBox(width: 24),
              Expanded(flex: 4, child: sidebar),
            ],
          );
        },
      ),
    );
  }
}

class _ProfileHero extends ConsumerStatefulWidget {
  const _ProfileHero();

  @override
  ConsumerState<_ProfileHero> createState() => _ProfileHeroState();
}

class _ProfileHeroState extends ConsumerState<_ProfileHero> {
  Future<void> _openEditDialog() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final initialName = user.userMetadata?['full_name'] as String? ?? '';
    final initialTitle = user.userMetadata?['job_title'] as String? ?? '';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _EditProfileDialog(
        initialName: initialName,
        initialTitle: initialTitle,
        onSave: (name, title) async {
          try {
            await AuthRepository().updateProfile(
              fullName: name.trim(),
              jobTitle: title.trim(),
            );
            if (!dialogContext.mounted) return;
            ref.invalidate(currentUserProvider);
            ref.invalidate(appUserRoleProvider);
            showRemaMessage(dialogContext, 'Perfil actualizado exitosamente.');
          } catch (e) {
            if (!dialogContext.mounted) return;
            showRemaMessage(dialogContext, 'Error al actualizar perfil: $e');
          }
        },
      ),
    );
  }

  String _relativeTime(DateTime? dateTime) {
    if (dateTime == null) return 'N/A';

    final now = DateTime.now().toUtc();
    final utcDate = dateTime.toUtc();
    final diff = now.difference(utcDate);

    if (diff.inMinutes < 1) return 'Ahora mismo';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    if (diff.inDays < 7) return 'Hace ${diff.inDays} días';

    return 'Hace ${(diff.inDays / 7).floor()} semanas';
  }

  String _roleLabel(AppUserRole role) {
    switch (role) {
      case AppUserRole.superAdmin:
        return 'Super Admin';
      case AppUserRole.admin:
        return 'Admin';
      case AppUserRole.staff:
        return 'Staff';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final role = ref.watch(appUserRoleProvider);

    final name = user?.userMetadata?['full_name'] != null
        ? user!.userMetadata!['full_name'] as String
        : (user?.email ?? 'Usuario');
    final title = user?.userMetadata != null
        ? user!.userMetadata!['job_title'] as String? ?? _roleLabel(role)
        : _roleLabel(role);
    final isActive = user?.appMetadata != null
        ? user!.appMetadata['is_active'] as bool? ?? true
        : true;
    final rawLastSignIn = user?.lastSignInAt;
    final lastSignIn = rawLastSignIn == null
        ? null
        : DateTime.tryParse(rawLastSignIn);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      color: RemaColors.surfaceLow,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 700;
          if (isMobile) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 48,
                    backgroundColor: RemaColors.surfaceHighest,
                    child: Image.asset(
                      'assets/images/logo_remaa.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$title | ${CompanyProfile.legalName}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _Tag(
                      label: isActive ? 'Activo' : 'Inactivo',
                      backgroundColor: isActive
                          ? const Color(0xFFFFDEA0)
                          : const Color(0xFFFFEBEE),
                    ),
                    _Tag(
                      label: 'Último acceso: ${_relativeTime(lastSignIn)}',
                      backgroundColor: RemaColors.surfaceHighest,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _openEditDialog,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Editar Perfil'),
                  ),
                ),
              ],
            );
          }

          return Row(
            children: [
              CircleAvatar(
                radius: 56,
                backgroundColor: RemaColors.surfaceHighest,
                child: Image.asset(
                  'assets/images/logo_remaa.png',
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$title | ${CompanyProfile.legalName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _Tag(
                          label: isActive ? 'Activo' : 'Inactivo',
                          backgroundColor: isActive
                              ? const Color(0xFFFFDEA0)
                              : const Color(0xFFFFEBEE),
                        ),
                        _Tag(
                          label:
                              'Último acceso: ${_relativeTime(lastSignIn)}',
                          backgroundColor: RemaColors.surfaceHighest,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _openEditDialog,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Editar Perfil'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SecurityPanel extends StatelessWidget {
  const _SecurityPanel({
    required this.onChangePassword,
    required this.onSignOutAll,
  });

  final VoidCallback onChangePassword;
  final Future<void> Function() onSignOutAll;

  @override
  Widget build(BuildContext context) {
    return RemaPanel(
      child: Column(
        children: [
          const RemaSectionHeader(
            title: 'Cuenta y Seguridad',
            icon: Icons.lock_person_outlined,
          ),
          const SizedBox(height: 24),
          _ActionRow(
            title: 'Contrasena',
            subtitle: 'Actualizada por ultima vez hace 3 meses.',
            trailing: TextButton(
              onPressed: onChangePassword,
              child: const Text('Cambiar Contrasena'),
            ),
          ),
          const SizedBox(height: 18),
          _ActionRow(
            title: 'Autenticacion de dos pasos',
            subtitle: 'Agregue una capa extra de seguridad a su cuenta de REMA.',
            trailing: Tooltip(
              message: 'Proximamente',
              child: FilledButton(
                onPressed: null,
                child: const Text('Activar 2FA'),
              ),
            ),
          ),
          const SizedBox(height: 18),
          _ActionRow(
            title: 'Sesiones activas',
            subtitle: 'Cierre de sesion en todos los dispositivos.',
            trailing: TextButton(
              onPressed: onSignOutAll,
              child: const Text(
                'Cerrar todo',
                style: TextStyle(color: RemaColors.error),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreferencesPanel extends StatelessWidget {
  const _PreferencesPanel({
    required this.language,
    required this.units,
    required this.onLanguageChanged,
    required this.onUnitsChanged,
  });

  final String language;
  final String units;
  final ValueChanged<String> onLanguageChanged;
  final ValueChanged<String> onUnitsChanged;

  @override
  Widget build(BuildContext context) {
    return RemaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const RemaSectionHeader(title: 'Preferencias del Sistema', icon: Icons.tune),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 760;
              if (isMobile) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DropdownPreference(
                      label: 'Idioma de interfaz',
                      value: language,
                      options: const ['Espanol (Mexico)', 'English (US)', 'Francais'],
                      onChanged: onLanguageChanged,
                    ),
                    const SizedBox(height: 16),
                    _DropdownPreference(
                      label: 'Unidades de medida',
                      value: units,
                      options: const ['Sistema Metrico (m, cm)', 'Sistema Imperial (ft, in)'],
                      onChanged: onUnitsChanged,
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: _DropdownPreference(
                      label: 'Idioma de interfaz',
                      value: language,
                      options: const ['Espanol (Mexico)', 'English (US)', 'Francais'],
                      onChanged: onLanguageChanged,
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: _DropdownPreference(
                      label: 'Unidades de medida',
                      value: units,
                      options: const ['Sistema Metrico (m, cm)', 'Sistema Imperial (ft, in)'],
                      onChanged: onUnitsChanged,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _NotificationsPanel extends StatelessWidget {
  const _NotificationsPanel({
    required this.pushAlerts,
    required this.emailAlerts,
    required this.onPushChanged,
    required this.onEmailChanged,
  });

  final bool pushAlerts;
  final bool emailAlerts;
  final ValueChanged<bool> onPushChanged;
  final ValueChanged<bool> onEmailChanged;

  @override
  Widget build(BuildContext context) {
    return RemaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RemaSectionHeader(title: 'Notificaciones', icon: Icons.notifications_active_outlined),
          const SizedBox(height: 24),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Alertas Push'),
            subtitle: const Text('Navegador y movil'),
            value: pushAlerts,
            onChanged: onPushChanged,
          ),
          const SizedBox(height: 10),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Correo Electronico'),
            subtitle: const Text('Resumen semanal de proyectos'),
            value: emailAlerts,
            onChanged: onEmailChanged,
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.title, required this.subtitle, required this.trailing});

  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 760;
        if (isMobile) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 18)),
              const SizedBox(height: 6),
              Text(
                subtitle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: RemaColors.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerLeft, child: trailing),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 18)),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: RemaColors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            trailing,
          ],
        );
      },
    );
  }
}

class _DropdownPreference extends StatelessWidget {
  const _DropdownPreference({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: const InputDecoration(),
          items: [
            for (final option in options)
              DropdownMenuItem<String>(
                value: option,
                child: Text(option, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (newValue) {
            if (newValue != null) {
              onChanged(newValue);
            }
          },
        ),
      ],
    );
  }
}

class _UsersAdminPanel extends StatelessWidget {
  const _UsersAdminPanel({
    required this.isLoading,
    required this.errorText,
    required this.usersCount,
    required this.onInviteUser,
    required this.onManageUsers,
    required this.onReloadUsers,
  });

  final bool isLoading;
  final String? errorText;
  final int usersCount;
  final VoidCallback onInviteUser;
  final VoidCallback onManageUsers;
  final VoidCallback onReloadUsers;

  @override
  Widget build(BuildContext context) {
    return RemaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const RemaSectionHeader(
            title: 'Gestion de Usuarios',
            icon: Icons.manage_accounts_outlined,
          ),
          const SizedBox(height: 16),
          Text(
            'Solo el super-admin puede invitar y administrar cuentas admin/staff.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: RemaColors.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: onInviteUser,
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('Nuevo usuario'),
              ),
              OutlinedButton.icon(
                onPressed: onManageUsers,
                icon: const Icon(Icons.groups_2_outlined),
                label: const Text('Administrar usuarios'),
              ),
              TextButton.icon(
                onPressed: isLoading ? null : onReloadUsers,
                icon: const Icon(Icons.refresh),
                label: const Text('Actualizar'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Usuarios detectados: $usersCount',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (isLoading) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(minHeight: 3),
          ],
          if (errorText != null) ...[
            const SizedBox(height: 10),
            Text(
              errorText!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: RemaColors.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _InviteUserPayload {
  const _InviteUserPayload({required this.email, required this.role});

  final String email;
  final String role;
}

class _InviteUserDialog extends StatefulWidget {
  const _InviteUserDialog();

  @override
  State<_InviteUserDialog> createState() => _InviteUserDialogState();
}

class _InviteUserDialogState extends State<_InviteUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  String _role = 'staff';

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Invitar nuevo usuario'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (value) {
                final email = (value ?? '').trim();
                if (email.isEmpty) {
                  return 'Ingresa un email.';
                }
                if (!email.contains('@') || !email.contains('.')) {
                  return 'Ingresa un email valido.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Rol inicial'),
              items: const [
                DropdownMenuItem(value: 'staff', child: Text('Staff')),
                DropdownMenuItem(value: 'admin', child: Text('Admin')),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() => _role = value);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) {
              return;
            }
            Navigator.of(context).pop(
              _InviteUserPayload(
                email: _emailController.text.trim().toLowerCase(),
                role: _role,
              ),
            );
          },
          child: const Text('Enviar invitacion'),
        ),
      ],
    );
  }
}

class _ManageUsersDialog extends StatefulWidget {
  const _ManageUsersDialog({
    required this.users,
    required this.onRefresh,
    required this.onSetRole,
    required this.onSetActive,
    required this.onResetPassword,
    required this.onResendInvite,
  });

  final List<ManagedUser> users;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String userId, String role) onSetRole;
  final Future<void> Function(String userId, bool isActive) onSetActive;
  final Future<void> Function(String userId) onResetPassword;
  final Future<void> Function(String userId) onResendInvite;

  @override
  State<_ManageUsersDialog> createState() => _ManageUsersDialogState();
}

class _ManageUsersDialogState extends State<_ManageUsersDialog> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (!mounted) {
        return;
      }
      showRemaMessage(context, 'No fue posible completar la accion: $error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Administrar usuarios'),
      content: SizedBox(
        width: 720,
        child: widget.users.isEmpty
            ? const Text('No hay usuarios disponibles.')
            : SingleChildScrollView(
                child: Column(
                  children: [
                    for (final user in widget.users)
                      Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(user.email, style: const TextStyle(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Text('Rol actual: ${user.role}'),
                              Text('Estado: ${user.isActive ? 'Activo' : 'Inactivo'}'),
                              Text('Email confirmado: ${user.emailConfirmed ? 'Si' : 'No'}'),
                              if (user.invitePending)
                                Text(
                                  'Invitacion: ${user.inviteExpired ? 'Vencida (requiere reenvio)' : 'Vigente (<24h)'}',
                                ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton(
                                    onPressed: _busy || user.role == 'staff'
                                        ? null
                                        : () => _run(() => widget.onSetRole(user.id, 'staff')),
                                    child: const Text('Hacer Staff'),
                                  ),
                                  OutlinedButton(
                                    onPressed: _busy || user.role == 'admin'
                                        ? null
                                        : () => _run(() => widget.onSetRole(user.id, 'admin')),
                                    child: const Text('Hacer Admin'),
                                  ),
                                  OutlinedButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _run(() => widget.onSetActive(user.id, !user.isActive)),
                                    child: Text(user.isActive ? 'Desactivar' : 'Activar'),
                                  ),
                                  TextButton(
                                    onPressed: _busy ? null : () => _run(() => widget.onResetPassword(user.id)),
                                    child: const Text('Reset password'),
                                  ),
                                  TextButton(
                                    onPressed: _busy || !user.canResendInvite
                                        ? null
                                        : () => _run(() => widget.onResendInvite(user.id)),
                                    child: const Text('Reenviar invitacion'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => _run(widget.onRefresh),
          child: const Text('Recargar'),
        ),
        FilledButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.backgroundColor});

  final String label;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
      ),
    );
  }
}

class _EditProfileDialog extends StatefulWidget {
  const _EditProfileDialog({
    required this.initialName,
    required this.initialTitle,
    required this.onSave,
  });

  final String initialName;
  final String initialTitle;
  final Future<void> Function(String name, String title) onSave;

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  late TextEditingController _nameController;
  late TextEditingController _titleController;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _titleController = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (_nameController.text.trim().isEmpty) {
      showRemaMessage(context, 'Ingresa un nombre.');
      return;
    }

    setState(() => _loading = true);
    try {
      await widget.onSave(_nameController.text, _titleController.text);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showRemaMessage(context, 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar Perfil'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            enabled: !_loading,
            decoration: const InputDecoration(
              labelText: 'Nombre completo',
              hintText: 'Ej: Ing. Miguel Vazquez',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleController,
            enabled: !_loading,
            decoration: const InputDecoration(
              labelText: 'Título / Cargo',
              hintText: 'Ej: Socio Director',
            ),
          ),
          if (_loading) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _loading ? null : _handleSave,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.onSave});

  final Future<void> Function(String newPassword) onSave;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  late TextEditingController _passwordController;
  late TextEditingController _confirmController;
  bool _loading = false;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _passwordController = TextEditingController();
    _confirmController = TextEditingController();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (password.isEmpty) {
      showRemaMessage(context, 'Ingresa una contraseña.');
      return;
    }

    if (password.length < 8) {
      showRemaMessage(context, 'La contraseña debe tener al menos 8 caracteres.');
      return;
    }

    if (password != confirm) {
      showRemaMessage(context, 'Las contraseñas no coinciden.');
      return;
    }

    setState(() => _loading = true);
    try {
      await widget.onSave(password);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showRemaMessage(context, 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cambiar Contraseña'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _passwordController,
            enabled: !_loading,
            obscureText: !_showPassword,
            decoration: InputDecoration(
              labelText: 'Nueva contraseña',
              hintText: 'Mínimo 8 caracteres',
              suffixIcon: IconButton(
                icon: Icon(
                  _showPassword ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _confirmController,
            enabled: !_loading,
            obscureText: !_showPassword,
            decoration: InputDecoration(
              labelText: 'Confirmar contraseña',
              hintText: 'Repite la contraseña',
              suffixIcon: IconButton(
                icon: Icon(
                  _showPassword ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
          ),
          if (_loading) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _loading ? null : _handleSave,
          child: const Text('Cambiar Contraseña'),
        ),
      ],
    );
  }
}
