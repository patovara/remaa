import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/rema_colors.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/rema_panels.dart';
import 'clientes_mock_data.dart';

class ClientesPage extends StatelessWidget {
  const ClientesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'Clientes',
      subtitle: 'Administra la base de datos de socios comerciales y proyectos arquitectonicos activos.',
      trailing: FilledButton.icon(
        onPressed: () => context.go('/nuevo-cliente'),
        icon: const Icon(Icons.add),
        label: const Text('Anadir Cliente'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
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
                  child: RemaMetricTile(
                    label: 'Total Carteras',
                    value: '42',
                    caption: '+3 este mes',
                  ),
                ),
                const SizedBox(width: 16, height: 16),
                const Expanded(
                  child: RemaMetricTile(
                    label: 'Proyectos en Curso',
                    value: '18',
                    caption: '85% capacidad',
                    backgroundColor: RemaColors.primaryDark,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 16, height: 16),
                const Expanded(
                  child: RemaMetricTile(
                    label: 'Facturacion Estimada',
                    value: '\$4.2M',
                    caption: 'MXN',
                    backgroundColor: RemaColors.surfaceHighest,
                  ),
                ),
              ];
              if (isWide) {
                return Row(children: metrics);
              }
              return const Column(
                children: [
                  RemaMetricTile(
                    label: 'Total Carteras',
                    value: '42',
                    caption: '+3 este mes',
                  ),
                  SizedBox(height: 16),
                  RemaMetricTile(
                    label: 'Proyectos en Curso',
                    value: '18',
                    caption: '85% capacidad',
                    backgroundColor: RemaColors.primaryDark,
                    foregroundColor: Colors.white,
                  ),
                  SizedBox(height: 16),
                  RemaMetricTile(
                    label: 'Facturacion Estimada',
                    value: '\$4.2M',
                    caption: 'MXN',
                    backgroundColor: RemaColors.surfaceHighest,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
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
                  for (final client in _clients)
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

const _clients = mockClients;
