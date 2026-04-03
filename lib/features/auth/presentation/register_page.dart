import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/rema_colors.dart';
import 'auth_controller.dart';
import 'auth_frame.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key, this.mode});

  final String? mode;

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool get _isInviteMode => widget.mode == 'invite';
  bool get _isResetMode => widget.mode == 'reset';
  bool get _isPasswordSetupMode => _isInviteMode || _isResetMode;
  bool get _hasInvalidMode =>
      widget.mode != null && widget.mode!.isNotEmpty && !_isPasswordSetupMode;

  @override
  void initState() {
    super.initState();
    if (_hasInvalidMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(content: Text('Enlace invalido o expirado. Inicia sesion nuevamente.')),
          );
        context.go('/login');
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Map<String, String> _urlParams(Uri uri) {
    final params = <String, String>{
      ...uri.queryParameters,
    };

    final fragment = uri.fragment.trim();
    if (fragment.isEmpty) {
      return params;
    }

    var fragmentQuery = fragment;
    final queryIndex = fragmentQuery.indexOf('?');
    if (queryIndex >= 0 && queryIndex + 1 < fragmentQuery.length) {
      fragmentQuery = fragmentQuery.substring(queryIndex + 1);
    }

    if (!fragmentQuery.contains('=')) {
      return params;
    }

    try {
      final fragmentParams = Uri.splitQueryString(fragmentQuery);
      for (final entry in fragmentParams.entries) {
        params.putIfAbsent(entry.key, () => entry.value);
      }
    } catch (_) {
      // Ignore malformed fragments and keep existing params.
    }

    return params;
  }

  OtpType? _otpTypeFromUrlValue(String rawType) {
    switch (rawType.trim().toLowerCase()) {
      case 'invite':
        return OtpType.invite;
      case 'recovery':
        return OtpType.recovery;
      case 'magiclink':
        return OtpType.magiclink;
      case 'signup':
        return OtpType.signup;
      case 'email_change':
      case 'emailchange':
        return OtpType.emailChange;
      case 'email':
        return OtpType.email;
      default:
        return null;
    }
  }

  Future<void> _ensureAuthSessionForPasswordSetup() async {
    final client = Supabase.instance.client;
    if (client.auth.currentSession != null) {
      return;
    }

    final uri = Uri.base;
    final params = _urlParams(uri);

    final code = (params['code'] ?? '').trim();
    if (code.isNotEmpty) {
      await client.auth.exchangeCodeForSession(code);
    }

    if (client.auth.currentSession != null) {
      return;
    }

    final refreshFromQuery = (params['refresh_token'] ?? '').trim();
    if (refreshFromQuery.isNotEmpty) {
      await client.auth.setSession(refreshFromQuery);
    }

    if (client.auth.currentSession != null) {
      return;
    }

    final rawType = (params['type'] ?? '').trim();
    final otpType = _otpTypeFromUrlValue(rawType) ?? (_isInviteMode ? OtpType.invite : OtpType.recovery);
    final tokenHash = (params['token_hash'] ?? params['token'] ?? '').trim();
    if (tokenHash.isNotEmpty) {
      await client.auth.verifyOTP(
        type: otpType,
        tokenHash: tokenHash,
      );
    }

    if (client.auth.currentSession == null) {
      throw StateError('Auth session missing! Reabre el enlace desde el correo.');
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final isInviteMode = _isPasswordSetupMode;

    if (isInviteMode) {
      try {
        await _ensureAuthSessionForPasswordSetup();

        await ref.read(authControllerProvider.notifier).updatePassword(
              _passwordController.text,
            );
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(content: Text(_authErrorMessage(error))),
          );
        return;
      }

      if (!mounted) return;

      final authState = ref.read(authControllerProvider);
      if (!authState.hasError) {
        await Supabase.instance.client.auth.signOut();
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(
              content: Text('Contrasena guardada. Inicia sesion para continuar.'),
            ),
          );
        context.go('/login');
      }
    } else {
      await ref.read(authControllerProvider.notifier).signUp(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );

      if (!mounted) return;

      final authState = ref.read(authControllerProvider);
      if (!authState.hasError) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(
              content: Text('Cuenta creada. Inicia sesion para continuar.'),
            ),
          );
        context.go('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<void>>(authControllerProvider, (previous, next) {
      if (next.hasError) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(content: Text(_authErrorMessage(next.error))),
          );
      }
    });

    final authState = ref.watch(authControllerProvider);
    final isLoading = authState.isLoading;
    final isInviteMode = _isPasswordSetupMode;

    return AuthFrame(
      title: isInviteMode ? 'Establece tu acceso' : 'Crear cuenta',
      subtitle: isInviteMode
          ? 'Define tu contrasena para activar tu acceso. El correo ya fue registrado por el super admin.'
          : 'Registra tus credenciales para acceder al portal de REMA.',
      cardChild: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isInviteMode) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF6DB),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _isInviteMode ? 'Modo invitacion' : 'Modo recuperacion de contrasena',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (!isInviteMode) ...[
              _AuthField(
                controller: _emailController,
                label: 'Correo',
                icon: Icons.mail_outline,
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  final input = value?.trim() ?? '';
                  if (input.isEmpty) {
                    return 'Ingresa tu correo.';
                  }
                  final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                  if (!emailRegex.hasMatch(input)) {
                    return 'Correo invalido.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
            ],
            _AuthField(
              controller: _passwordController,
              label: 'Contrasena',
              icon: Icons.lock_outline,
              obscureText: true,
              validator: (value) {
                final input = value ?? '';
                if (input.isEmpty) {
                  return 'Ingresa una contrasena.';
                }
                if (input.length < 8) {
                  return 'La contrasena debe tener al menos 8 caracteres.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            _AuthField(
              controller: _confirmPasswordController,
              label: 'Repetir contrasena',
              icon: Icons.verified_user_outlined,
              obscureText: true,
              validator: (value) {
                if ((value ?? '').isEmpty) {
                  return 'Confirma tu contrasena.';
                }
                if (value != _passwordController.text) {
                  return 'Las contrasenas no coinciden.';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: isLoading ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: RemaColors.primary,
                foregroundColor: const Color(0xFF694C00),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isInviteMode ? 'GUARDAR CONTRASENA' : 'CREAR CUENTA'),
            ),
            if (!isInviteMode) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: isLoading ? null : () => context.go('/login'),
                  child: const Text('Ya tengo cuenta. Iniciar sesion'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.obscureText = false,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
      ),
    );
  }
}

String _authErrorMessage(Object? error) {
  if (error is AuthException && error.message.trim().isNotEmpty) {
    return error.message;
  }
  if (error is StateError && error.message.trim().isNotEmpty) {
    return error.message;
  }
  return 'No se pudo crear la cuenta. Intenta de nuevo.';
}
