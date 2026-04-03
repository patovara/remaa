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

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final isInviteMode = widget.mode == 'invite';

    if (isInviteMode) {
      await ref.read(authControllerProvider.notifier).updatePassword(
            _passwordController.text,
          );

      if (!mounted) return;

      final authState = ref.read(authControllerProvider);
      if (!authState.hasError) {
        context.go('/levantamiento');
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
    final isInviteMode = widget.mode == 'invite';

    return AuthFrame(
      title: isInviteMode ? 'Establece tu acceso' : 'Crear cuenta',
      subtitle: isInviteMode
          ? 'Crea una contraseña para activar tu acceso al portal REMA.'
          : 'Registra tus credenciales para acceder al portal de REMA.',
      cardChild: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
              label: 'Confirmar contrasena',
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
                  : Text(isInviteMode ? 'ACTIVAR ACCESO' : 'CREAR CUENTA'),
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
