import 'package:flutter/material.dart';

import '../../../core/config/company_profile.dart';
import '../../../core/theme/rema_colors.dart';
import '../../../core/utils/rema_feedback.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/rema_panels.dart';

class AjustesPage extends StatefulWidget {
  const AjustesPage({super.key});

  @override
  State<AjustesPage> createState() => _AjustesPageState();
}

class _AjustesPageState extends State<AjustesPage> {
  bool _pushAlerts = true;
  bool _emailAlerts = false;
  String _language = 'Espanol (Mexico)';
  String _units = 'Sistema Metrico (m, cm)';

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'Configuracion',
      subtitle: 'Preferencias operativas, seguridad y notificaciones del sistema.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 1100;
          final mainColumn = Column(
            children: [
              _ProfileHero(onEdit: () => showRemaMessage(context, 'Editor de perfil listo para conectarse con backend.')),
              const SizedBox(height: 24),
              _SecurityPanel(),
              const SizedBox(height: 24),
              _PreferencesPanel(
                language: _language,
                units: _units,
                onLanguageChanged: (value) => setState(() => _language = value),
                onUnitsChanged: (value) => setState(() => _units = value),
              ),
            ],
          );
          final sidebar = _NotificationsPanel(
            pushAlerts: _pushAlerts,
            emailAlerts: _emailAlerts,
            onPushChanged: (value) => setState(() => _pushAlerts = value),
            onEmailChanged: (value) => setState(() => _emailAlerts = value),
          );

          if (!isWide) {
            return Column(
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

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.onEdit});

  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      color: RemaColors.surfaceLow,
      child: Row(
        children: [
          CircleAvatar(
            radius: 56,
            backgroundColor: RemaColors.surfaceHighest,
            child: Image.asset('assets/images/logo_remaa.png', fit: BoxFit.cover),
          ),
          const SizedBox(width: 24),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ing. Miguel Vazquez', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
                SizedBox(height: 6),
                Text('Socio Director | ${CompanyProfile.legalName}'),
                SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _Tag(label: 'Activo', backgroundColor: Color(0xFFFFDEA0)),
                    _Tag(label: 'Ultimo acceso: Hace 12 min', backgroundColor: RemaColors.surfaceHighest),
                  ],
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Editar Perfil'),
          ),
        ],
      ),
    );
  }
}

class _SecurityPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return RemaPanel(
      child: Column(
        children: [
          const RemaSectionHeader(title: 'Cuenta y Seguridad', icon: Icons.lock_person_outlined),
          const SizedBox(height: 24),
          _ActionRow(
            title: 'Contrasena',
            subtitle: 'Actualizada por ultima vez hace 3 meses.',
            trailing: TextButton(
              onPressed: () => showRemaMessage(context, 'Cambio de contrasena listo para conectarse con autenticacion.'),
              child: const Text('Cambiar Contrasena'),
            ),
          ),
          const SizedBox(height: 18),
          _ActionRow(
            title: 'Autenticacion de dos pasos',
            subtitle: 'Agregue una capa extra de seguridad a su cuenta de REMA.',
            trailing: FilledButton(
              onPressed: () => showRemaMessage(context, 'Flujo de 2FA pendiente de integracion.'),
              child: const Text('Activar 2FA'),
            ),
          ),
          const SizedBox(height: 18),
          _ActionRow(
            title: 'Sesiones activas',
            subtitle: 'Usted esta conectado actualmente en 3 dispositivos.',
            trailing: TextButton(
              onPressed: () => showRemaMessage(context, 'Cierre de sesiones masivas pendiente de backend.'),
              child: const Text('Cerrar todo', style: TextStyle(color: RemaColors.error)),
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
        children: [
          const RemaSectionHeader(title: 'Preferencias del Sistema', icon: Icons.tune),
          const SizedBox(height: 24),
          Row(
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 18)),
              const SizedBox(height: 6),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: RemaColors.onSurfaceVariant)),
            ],
          ),
        ),
        const SizedBox(width: 20),
        trailing,
      ],
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
          decoration: const InputDecoration(),
          items: [
            for (final option in options)
              DropdownMenuItem<String>(value: option, child: Text(option)),
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
