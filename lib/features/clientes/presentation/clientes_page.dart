import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/supabase_bootstrap.dart';
import '../../../core/theme/rema_colors.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/rema_panels.dart';
import 'clientes_mock_data.dart';

class ClientesPage extends StatefulWidget {
  const ClientesPage({super.key});

  @override
  State<ClientesPage> createState() => _ClientesPageState();
}

class _ClientesPageState extends State<ClientesPage> {
  final _searchController = TextEditingController();
  List<ClientRecord> _clients = const <ClientRecord>[];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadClients() async {
    setState(() => _isLoading = true);
    final next = await _fetchClients();
    if (!mounted) {
      return;
    }
    setState(() {
      _clients = next;
      _isLoading = false;
    });
  }

  Future<List<ClientRecord>> _fetchClients() async {
    final base = List<ClientRecord>.from(mockClients);
    final client = SupabaseBootstrap.client;
    if (client == null) {
      return base;
    }

    try {
      final rows = await client
          .from('clients')
          .select('id, business_name, email, phone, address_line, city, created_at')
          .order('created_at', ascending: false);

      final knownNames = base.map((item) => item.name.trim().toLowerCase()).toSet();
      for (final row in rows) {
        final name = (row['business_name'] as String? ?? '').trim();
        if (name.isEmpty) {
          continue;
        }
        if (knownNames.contains(name.toLowerCase())) {
          continue;
        }

        final addressLine = (row['address_line'] as String? ?? '').trim();
        final city = (row['city'] as String? ?? '').trim();
        final fullAddress = [
          if (addressLine.isNotEmpty) addressLine,
          if (city.isNotEmpty) city,
        ].join(', ');

        base.add(
          ClientRecord(
            id: row['id'] as String? ?? name.toLowerCase().replaceAll(' ', '-'),
            name: name,
            sector: 'Sector cliente',
            badge: 'Activo',
            activeProjects: '00',
            months: '--',
            icon: Icons.apartment,
            contactEmail: (row['email'] as String? ?? 'sin-correo@cliente.com').trim(),
            phone: (row['phone'] as String? ?? 'Sin telefono').trim(),
            address: fullAddress.isEmpty ? 'Sin direccion registrada' : fullAddress,
            responsibles: const [],
          ),
        );
      }
    } catch (_) {
      return base;
    }

    return base;
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = _clients
        .where(
          (client) =>
              query.isEmpty ||
              client.name.toLowerCase().contains(query) ||
              client.sector.toLowerCase().contains(query),
        )
        .toList();

    final totalActiveProjects = filtered
        .map((item) => int.tryParse(item.activeProjects) ?? 0)
        .fold<int>(0, (sum, value) => sum + value);

    return PageFrame(
      title: 'Clientes',
      subtitle: 'Administra la base de datos de socios comerciales y proyectos arquitectonicos activos.',
      trailing: Wrap(
        spacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _isLoading ? null : _loadClients,
            icon: const Icon(Icons.refresh),
            label: const Text('Actualizar'),
          ),
          FilledButton.icon(
            onPressed: () => context.go('/nuevo-cliente'),
            icon: const Icon(Icons.add),
            label: const Text('Anadir Cliente'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Buscar cliente...',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 920;
              final metrics = <Widget>[
                const Expanded(
                  child: SizedBox.shrink(),
                ),
                const SizedBox(width: 16, height: 16),
                const Expanded(
                  child: SizedBox.shrink(),
                ),
                const SizedBox(width: 16, height: 16),
                const Expanded(
                  child: SizedBox.shrink(),
                ),
              ];
              metrics[0] = Expanded(
                child: RemaMetricTile(
                  label: 'Total Carteras',
                  value: filtered.length.toString().padLeft(2, '0'),
                  caption: 'Clientes visibles',
                ),
              );
              metrics[2] = Expanded(
                child: RemaMetricTile(
                  label: 'Proyectos en Curso',
                  value: totalActiveProjects.toString().padLeft(2, '0'),
                  caption: 'Suma de activos',
                  backgroundColor: RemaColors.primaryDark,
                  foregroundColor: Colors.white,
                ),
              );
              metrics[4] = Expanded(
                child: RemaMetricTile(
                  label: 'Fuente de Datos',
                  value: SupabaseBootstrap.client == null ? 'LOCAL' : 'LOCAL+DB',
                  caption: 'Clientes + Supabase',
                  backgroundColor: RemaColors.surfaceHighest,
                ),
              );
              if (isWide) {
                return Row(children: metrics);
              }
              return Column(
                children: [
                  RemaMetricTile(
                    label: 'Total Carteras',
                    value: filtered.length.toString().padLeft(2, '0'),
                    caption: 'Clientes visibles',
                  ),
                  const SizedBox(height: 16),
                  RemaMetricTile(
                    label: 'Proyectos en Curso',
                    value: totalActiveProjects.toString().padLeft(2, '0'),
                    caption: 'Suma de activos',
                    backgroundColor: RemaColors.primaryDark,
                    foregroundColor: Colors.white,
                  ),
                  const SizedBox(height: 16),
                  RemaMetricTile(
                    label: 'Fuente de Datos',
                    value: SupabaseBootstrap.client == null ? 'LOCAL' : 'LOCAL+DB',
                    caption: 'Clientes + Supabase',
                    backgroundColor: RemaColors.surfaceHighest,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (filtered.isEmpty)
            const RemaPanel(
              child: Text('No hay clientes para mostrar con el filtro actual.'),
            )
          else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1100
                  ? 3
                  : constraints.maxWidth >= 760
                      ? 2
                      : 1;
              final itemWidth = columns == 1
                  ? constraints.maxWidth
                  : (constraints.maxWidth - (16 * (columns - 1))) / columns;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final client in filtered)
                    SizedBox(
                      width: itemWidth,
                      child: _ClientCard(client: client),
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

class _ClientCard extends StatelessWidget {
  const _ClientCard({required this.client});

  final ClientRecord client;

  @override
  Widget build(BuildContext context) {
    return RemaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64,
                height: 64,
                color: RemaColors.surfaceLow,
                alignment: Alignment.center,
                child: Icon(client.icon, color: RemaColors.onSurfaceVariant, size: 28),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                color: client.badge == 'Premium' ? const Color(0xFFFFDEA0) : RemaColors.surfaceHighest,
                child: Text(
                  client.badge.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            client.name,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(client.sector.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 22),
          Row(
            children: [
              _ClientMetric(value: client.activeProjects, label: 'Proyectos activos'),
              Container(width: 1, height: 32, color: RemaColors.outlineVariant.withValues(alpha: 0.3)),
              const SizedBox(width: 18),
              _ClientMetric(value: client.months, label: 'Meses relacion'),
            ],
          ),
          const SizedBox(height: 22),
          TextButton.icon(
            onPressed: () => context.go('/clientes/${client.id}'),
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Ver detalles'),
          ),
        ],
      ),
    );
  }
}

class _ClientMetric extends StatelessWidget {
  const _ClientMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

