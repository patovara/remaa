import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/rema_colors.dart';
import 'auth_controller.dart';
import 'auth_frame.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    await ref.read(authControllerProvider.notifier).signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
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

    return AuthFrame(
      title: 'Iniciar sesion',
      subtitle: 'Accede al sistema para gestionar cotizaciones y clientes.',
      cardChild: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
            _AuthField(
              controller: _passwordController,
              label: 'Contrasena',
              icon: Icons.lock_outline,
              obscureText: true,
              validator: (value) {
                if ((value ?? '').isEmpty) {
                  return 'Ingresa tu contrasena.';
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
                  : const Text('INICIAR SESION'),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: isLoading ? null : () => context.go('/register'),
                child: const Text('¿Aun no tienes cuenta? Registrate'),
              ),
            ),
          ],
        ),
      ),
      bottomChild: const _BottomLegend(),
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

class _BottomLegend extends StatelessWidget {
  const _BottomLegend();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;

    return Row(
      children: [
        Expanded(
          child: Text(
            'SECURE PORTAL',
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: style,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'BLUEPRINT READY',
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            textAlign: TextAlign.right,
            style: style,
          ),
        ),
      ],
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
  return 'No se pudo iniciar sesion. Intenta de nuevo.';
}
