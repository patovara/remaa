import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/rema_colors.dart';
import '../../../core/utils/rema_feedback.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/rema_panels.dart';

class CotizacionesPage extends StatelessWidget {
  const CotizacionesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'Gestion de Cotizaciones',
      subtitle: 'Resumen operativo y detalle de cotizaciones activas.',
      trailing: FilledButton.icon(
        onPressed: () => showRemaMessage(
          context,
          'Nueva cotizacion preparada con datos demo.',
          label: 'Abrir',
          onAction: () => context.go('/presupuesto'),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Nueva Cotizacion'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            decoration: const InputDecoration(
              hintText: 'Buscar cotizacion por clave o cliente...',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 960;
              if (!isWide) {
                return const Column(
                  children: [
                    RemaMetricTile(
                      label: 'Total Cotizado',
                      value: '\$2,840,000',
                      caption: '+12.5% este mes',
                    ),
                    SizedBox(height: 16),
                    RemaMetricTile(
                      label: 'Pendientes',
                      value: '14',
                      caption: 'Esperando aprobacion',
                      backgroundColor: RemaColors.surfaceWhite,
                    ),
                    SizedBox(height: 16),
                    RemaMetricTile(
                      label: 'Aprobadas',
                      value: '38',
                      caption: '82% ratio de exito',
                      backgroundColor: RemaColors.surfaceLow,
                    ),
                    SizedBox(height: 16),
                    RemaMetricTile(
                      label: 'Valor Promedio',
                      value: '\$74,500',
                      caption: 'Por proyecto individual',
                      backgroundColor: Color(0xFFFFDEA0),
                    ),
                  ],
                );
              }
              return const Row(
                children: [
                  Expanded(
                    child: RemaMetricTile(
                      label: 'Total Cotizado',
                      value: '\$2,840,000',
                      caption: '+12.5% este mes',
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: RemaMetricTile(
                      label: 'Pendientes',
                      value: '14',
                      caption: 'Esperando aprobacion',
                      backgroundColor: RemaColors.surfaceWhite,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: RemaMetricTile(
                      label: 'Aprobadas',
                      value: '38',
                      caption: '82% ratio de exito',
                      backgroundColor: RemaColors.surfaceLow,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: RemaMetricTile(
                      label: 'Valor Promedio',
                      value: '\$74,500',
                      caption: 'Por proyecto individual',
                      backgroundColor: Color(0xFFFFDEA0),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          RemaPanel(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Listado Detallado', style: Theme.of(context).textTheme.titleLarge),
                      ),
                      TextButton.icon(
                        onPressed: () => showRemaMessage(context, 'Filtro listo para conectarse con backend.'),
                        icon: const Icon(Icons.filter_list),
                        label: const Text('Filtrar'),
                      ),
                      TextButton.icon(
                        onPressed: () => showRemaMessage(context, 'Exportacion demo disponible en la siguiente iteracion.'),
                        icon: const Icon(Icons.download),
                        label: const Text('Exportar'),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: _QuoteTableHeader(),
                ),
                for (final quote in _quotes)
                  _QuoteRow(
                    quote: quote,
                    onEdit: () => context.go('/presupuesto'),
                    onShare: () => showRemaMessage(context, 'Compartir ${quote.id} queda listo para integracion.'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final isPending = status == 'Pendiente';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: isPending ? const Color(0xFFFFDEA0) : const Color(0xFFDFF4DD),
      child: Text(status.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _QuoteTableHeader extends StatelessWidget {
  const _QuoteTableHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _HeaderCell(flex: 2, label: 'ID Cotizacion'),
        _HeaderCell(flex: 4, label: 'Proyecto'),
        _HeaderCell(flex: 3, label: 'Cliente'),
        _HeaderCell(flex: 2, label: 'Total'),
        _HeaderCell(flex: 2, label: 'Estado'),
        _HeaderCell(flex: 2, label: 'Acciones'),
      ],
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({required this.flex, required this.label});

  final int flex;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(label, style: Theme.of(context).textTheme.labelSmall),
      ),
    );
  }
}

class _QuoteRow extends StatelessWidget {
  const _QuoteRow({required this.quote, required this.onEdit, required this.onShare});

  final ({String id, String title, String location, String client, String status, String amount}) quote;
  final VoidCallback onEdit;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: RemaColors.surfaceLow.withValues(alpha: 0.8)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(quote.id, style: const TextStyle(fontWeight: FontWeight.w700, color: RemaColors.primaryDark)),
          ),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(quote.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(quote.location, style: const TextStyle(color: RemaColors.onSurfaceVariant)),
              ],
            ),
          ),
          Expanded(flex: 3, child: Text(quote.client)),
          Expanded(flex: 2, child: Text(quote.amount, style: const TextStyle(fontWeight: FontWeight.w700))),
          Expanded(flex: 2, child: Align(alignment: Alignment.centerLeft, child: _StatusBadge(status: quote.status))),
          Expanded(
            flex: 2,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(onPressed: onEdit, icon: const Icon(Icons.edit_outlined), tooltip: 'Editar'),
                IconButton(onPressed: onShare, icon: const Icon(Icons.share_outlined), tooltip: 'Compartir'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const _quotes = <({String id, String title, String location, String client, String status, String amount})>[
  (
    id: '#QT-2024-082',
    title: 'Residencia Los Olivos',
    location: 'Ubicacion: Valle Real',
    client: 'Ing. Roberto Mendez',
    status: 'Pendiente',
    amount: '\$145,200.00 MXN'
  ),
  (
    id: '#QT-2024-079',
    title: 'Torre Loft 360',
    location: 'Ubicacion: Zona Residencial',
    client: 'Construcciones Alpha S.A.',
    status: 'Aprobada',
    amount: '\$482,000.00 MXN'
  ),
  (
    id: '#QT-2024-075',
    title: 'Ampliacion Quinta Gto',
    location: 'Ubicacion: Guanajuato Capital',
    client: 'Familia Torres',
    status: 'Aprobada',
    amount: '\$218,900.00 MXN'
  ),
];
