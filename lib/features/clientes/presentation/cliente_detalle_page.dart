import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/supabase_bootstrap.dart';
import '../../../core/theme/rema_colors.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/rema_panels.dart';
import 'client_responsibles_controller.dart';
import 'clientes_mock_data.dart';

class ClienteDetallePage extends ConsumerStatefulWidget {
  const ClienteDetallePage({super.key, required this.clientId});

  final String clientId;

  @override
  ConsumerState<ClienteDetallePage> createState() => _ClienteDetallePageState();
}

class _ClienteDetallePageState extends ConsumerState<ClienteDetallePage> {
  ClientRecord? _resolvedClient;
  late final Future<ClientRecord?> _clientFuture = _resolveClient();

  bool _isUuid(String value) {
    final uuidPattern = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    );
    return uuidPattern.hasMatch(value);
  }

  Future<ClientRecord?> _resolveClient() async {
    final local = findClientById(widget.clientId);
    if (local != null) {
      _resolvedClient = local;
      return local;
    }

    if (!_isUuid(widget.clientId) || SupabaseBootstrap.client == null) {
      return null;
    }

    try {
      final row = await SupabaseBootstrap.client!
          .from('clients')
          .select('id, business_name, email, phone, address_line, city')
          .eq('id', widget.clientId)
          .maybeSingle();

      if (row == null) {
        return null;
      }

      final businessName = (row['business_name'] as String? ?? '').trim();
      if (businessName.isEmpty) {
        return null;
      }

      final addressLine = (row['address_line'] as String? ?? '').trim();
      final city = (row['city'] as String? ?? '').trim();
      final fullAddress = [
        if (addressLine.isNotEmpty) addressLine,
        if (city.isNotEmpty) city,
      ].join(', ');

      final remote = ClientRecord(
        id: row['id'] as String? ?? widget.clientId,
        name: businessName,
        sector: 'Sector cliente',
        badge: 'Activo',
        activeProjects: '00',
        months: '--',
        icon: Icons.apartment,
        contactEmail: (row['email'] as String? ?? 'sin-correo@cliente.com').trim(),
        phone: (row['phone'] as String? ?? 'Sin telefono').trim(),
        address: fullAddress.isEmpty ? 'Sin direccion registrada' : fullAddress,
        responsibles: const [],
      );
      _resolvedClient = remote;
      return remote;
    } catch (_) {
      return null;
    }
  }

  List<ClientResponsibleRecord> _sorted(List<ClientResponsibleRecord> input) {
    final items = [...input];
    items.sort((left, right) => left.role.index.compareTo(right.role.index));
    return items;
  }

  List<ClientResponsibleRecord> get _currentResponsibles {
    final currentState = ref.read(clientResponsiblesProvider(widget.clientId));
    return _sorted(currentState.valueOrNull ?? _resolvedClient?.responsibles ?? const []);
  }

  Future<void> _addResponsible() async {
    final messenger = ScaffoldMessenger.of(context);
    final responsibles = _currentResponsibles;
    final created = await showDialog<ClientResponsibleRecord>(
      context: context,
      builder: (context) => ResponsibleEditorDialog(
        takenRoles: responsibles.map((item) => item.role).toSet(),
      ),
    );

    if (!mounted || created == null) {
      return;
    }

    try {
      await ref.read(clientResponsiblesProvider(widget.clientId).notifier).save(created);
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showMessage(messenger, 'No fue posible guardar el responsable.');
      return;
    }

    _showMessage(messenger, 'Responsable ${created.role.label.toLowerCase()} agregado.');
  }

  Future<void> _editResponsible(ClientResponsibleRecord responsible) async {
    final messenger = ScaffoldMessenger.of(context);
    final responsibles = _currentResponsibles;
    final updated = await showDialog<ClientResponsibleRecord>(
      context: context,
      builder: (context) => ResponsibleEditorDialog(
        initialValue: responsible,
        takenRoles: responsibles
            .where((item) => item.id != responsible.id)
            .map((item) => item.role)
            .toSet(),
      ),
    );

    if (!mounted || updated == null) {
      return;
    }

    try {
      await ref.read(clientResponsiblesProvider(widget.clientId).notifier).save(updated);
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showMessage(messenger, 'No fue posible actualizar el responsable.');
      return;
    }

    _showMessage(messenger, 'Responsable ${updated.role.label.toLowerCase()} actualizado.');
  }

  Future<void> _deleteResponsible(ClientResponsibleRecord responsible) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar responsable'),
        content: Text(
          'Se quitara a ${responsible.fullName} del expediente de cliente. Puedes volver a capturarlo despues.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) {
      return;
    }

    try {
      await ref.read(clientResponsiblesProvider(widget.clientId).notifier).remove(responsible);
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showMessage(messenger, 'No fue posible eliminar el responsable.');
      return;
    }

    _showMessage(messenger, 'Responsable ${responsible.role.label.toLowerCase()} eliminado.');
  }

  void _showMessage(ScaffoldMessengerState messenger, String message) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final responsiblesState = ref.watch(clientResponsiblesProvider(widget.clientId));
    return FutureBuilder<ClientRecord?>(
      future: _clientFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const PageFrame(
            title: 'Cargando cliente',
            subtitle: 'Obteniendo informacion del expediente...',
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final client = snapshot.data;
        if (client == null) {
          return PageFrame(
            title: 'Cliente no encontrado',
            subtitle: 'El expediente solicitado no existe en este prototipo.',
            trailing: TextButton.icon(
              onPressed: () => context.go('/clientes'),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Volver'),
            ),
            child: const RemaPanel(
              child: Text('Revisa el listado de clientes y vuelve a abrir el expediente desde ahi.'),
            ),
          );
        }

        return PageFrame(
          title: client.name,
          subtitle: 'Expediente del cliente y administracion de responsables para firmas.',
          trailing: TextButton.icon(
            onPressed: () => context.go('/clientes'),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Clientes'),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 1080;
              final responsibleItems = _sorted(responsiblesState.valueOrNull ?? client.responsibles);
              final summary = _ClientSummaryPanel(client: client);
              final responsiblesPanel = _ResponsiblesPanel(
                responsibles: responsibleItems,
                isLoading: responsiblesState.isLoading && !responsiblesState.hasValue,
                canAddMore: responsibleItems.length < ResponsibleRole.values.length,
                onAdd: _addResponsible,
                onEdit: _editResponsible,
                onDelete: _deleteResponsible,
                onRetry: () => ref.read(clientResponsiblesProvider(widget.clientId).notifier).reload(),
                hasError: responsiblesState.hasError && !responsiblesState.hasValue,
              );

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: summary),
                    const SizedBox(width: 24),
                    Expanded(flex: 7, child: responsiblesPanel),
                  ],
                );
              }

              return Column(
                children: [
                  summary,
                  const SizedBox(height: 20),
                  responsiblesPanel,
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _ClientSummaryPanel extends StatelessWidget {
  const _ClientSummaryPanel({required this.client});

  final ClientRecord client;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        RemaPanel(
          backgroundColor: RemaColors.primaryDark,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 72,
                height: 72,
                color: Colors.white.withValues(alpha: 0.08),
                alignment: Alignment.center,
                child: Icon(client.icon, color: Colors.white, size: 32),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      client.badge.toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.72),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      client.name,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      client.sector,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        RemaPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const RemaSectionHeader(title: 'Ficha del cliente', icon: Icons.badge_outlined),
              const SizedBox(height: 24),
              _SummaryRow(label: 'Correo principal', value: client.contactEmail),
              const SizedBox(height: 16),
              _SummaryRow(label: 'Telefono', value: client.phone),
              const SizedBox(height: 16),
              _SummaryRow(label: 'Direccion', value: client.address),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _SummaryMetric(
                      label: 'Proyectos activos',
                      value: client.activeProjects,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _SummaryMetric(
                      label: 'Meses relacion',
                      value: client.months,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResponsiblesPanel extends StatelessWidget {
  const _ResponsiblesPanel({
    required this.responsibles,
    required this.isLoading,
    required this.hasError,
    required this.canAddMore,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onRetry,
  });

  final List<ClientResponsibleRecord> responsibles;
  final bool isLoading;
  final bool hasError;
  final bool canAddMore;
  final VoidCallback onAdd;
  final ValueChanged<ClientResponsibleRecord> onEdit;
  final ValueChanged<ClientResponsibleRecord> onDelete;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return RemaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RemaSectionHeader(
            title: 'Responsables',
            icon: Icons.how_to_reg_outlined,
            trailing: FilledButton.icon(
              onPressed: canAddMore ? onAdd : null,
              icon: const Icon(Icons.add),
              label: const Text('Agregar'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            canAddMore
                ? 'Administra supervisor y gerente del cliente. Si Supabase esta configurado, los cambios se sincronizan; si no, la pantalla sigue funcionando en modo local.'
                : 'El expediente ya tiene los dos roles cubiertos. Edita o elimina alguno si necesitas cambiarlo.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: RemaColors.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          if (isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (hasError)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: RemaColors.surfaceLow,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: RemaColors.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('No fue posible cargar los responsables del cliente.'),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                ],
              ),
            )
          else if (responsibles.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: RemaColors.surfaceLow,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: RemaColors.outlineVariant),
              ),
              child: const Text('Aun no hay responsables registrados para este cliente.'),
            )
          else
            for (final responsible in responsibles) ...[
              _ResponsibleCard(
                responsible: responsible,
                onEdit: () => onEdit(responsible),
                onDelete: () => onDelete(responsible),
              ),
              const SizedBox(height: 16),
            ],
        ],
      ),
    );
  }
}

class _ResponsibleCard extends StatelessWidget {
  const _ResponsibleCard({
    required this.responsible,
    required this.onEdit,
    required this.onDelete,
  });

  final ClientResponsibleRecord responsible;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: RemaColors.surfaceLow,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: RemaColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: RemaColors.surfaceHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  responsible.role.label.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: onEdit,
                tooltip: 'Editar responsable',
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                onPressed: onDelete,
                tooltip: 'Eliminar responsable',
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '${responsible.title} ${responsible.fullName}'.trim(),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            responsible.position,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: RemaColors.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              _ContactPill(icon: Icons.call_outlined, label: responsible.phone),
              _ContactPill(icon: Icons.mail_outline, label: responsible.email),
            ],
          ),
          if (responsible.contactNotes.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              responsible.contactNotes,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

class _ContactPill extends StatelessWidget {
  const _ContactPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: RemaColors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: RemaColors.primaryDark),
          const SizedBox(width: 10),
          Text(label),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
              ),
        ),
        const SizedBox(height: 6),
        Text(value, style: Theme.of(context).textTheme.bodyLarge),
      ],
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: RemaColors.surfaceLow,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(label),
        ],
      ),
    );
  }
}

class ResponsibleEditorDialog extends StatefulWidget {
  const ResponsibleEditorDialog({super.key, this.initialValue, required this.takenRoles});

  final ClientResponsibleRecord? initialValue;
  final Set<ResponsibleRole> takenRoles;

  @override
  State<ResponsibleEditorDialog> createState() => _ResponsibleEditorDialogState();
}

class _ResponsibleEditorDialogState extends State<ResponsibleEditorDialog> {
  final _formKey = GlobalKey<FormState>();

  late ResponsibleRole _role = widget.initialValue?.role ?? _firstAvailableRole();
  late final TextEditingController _titleController = TextEditingController(
    text: widget.initialValue?.title ?? '',
  );
  late final TextEditingController _positionController = TextEditingController(
    text: widget.initialValue?.position ?? '',
  );
  late final TextEditingController _fullNameController = TextEditingController(
    text: widget.initialValue?.fullName ?? '',
  );
  late final TextEditingController _phoneController = TextEditingController(
    text: widget.initialValue?.phone ?? '',
  );
  late final TextEditingController _emailController = TextEditingController(
    text: widget.initialValue?.email ?? '',
  );
  late final TextEditingController _notesController = TextEditingController(
    text: widget.initialValue?.contactNotes ?? '',
  );

  ResponsibleRole _firstAvailableRole() {
    for (final role in ResponsibleRole.values) {
      if (!widget.takenRoles.contains(role)) {
        return role;
      }
    }
    return ResponsibleRole.supervisor;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _positionController.dispose();
    _fullNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _submit() {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      return;
    }

    Navigator.of(context).pop(
      ClientResponsibleRecord(
        id: widget.initialValue?.id ?? '${_role.code}-${DateTime.now().millisecondsSinceEpoch}',
        role: _role,
        title: _titleController.text.trim(),
        position: _positionController.text.trim(),
        fullName: _fullNameController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        contactNotes: _notesController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialValue == null ? 'Nuevo responsable' : 'Editar responsable'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<ResponsibleRole>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Rol'),
                  items: [
                    for (final role in ResponsibleRole.values)
                      DropdownMenuItem(
                        value: role,
                        enabled: role == widget.initialValue?.role || !widget.takenRoles.contains(role),
                        child: Text(role.label),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _role = value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'Titulo'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _positionController,
                  decoration: const InputDecoration(labelText: 'Puesto'),
                  validator: (value) => _requiredValue(value, 'Ingresa el puesto.'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _fullNameController,
                  decoration: const InputDecoration(labelText: 'Nombre completo'),
                  validator: (value) => _requiredValue(value, 'Ingresa el nombre completo.'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(labelText: 'Telefono'),
                  validator: (value) => _requiredValue(value, 'Ingresa el telefono.'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Correo electronico'),
                  validator: (value) => _requiredEmail(value),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Notas de contacto'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Guardar'),
        ),
      ],
    );
  }

  String? _requiredValue(String? value, String message) {
    if (value == null || value.trim().isEmpty) {
      return message;
    }
    return null;
  }

  String? _requiredEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Ingresa el correo electronico.';
    }
    if (!value.contains('@')) {
      return 'Ingresa un correo valido.';
    }
    return null;
  }
}