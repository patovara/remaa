import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/rema_colors.dart';
import '../../../core/utils/rema_feedback.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/rema_panels.dart';
import '../domain/concept_generation.dart';
import '../domain/quote_models.dart';
import 'concepts_catalog_controller.dart';
import 'quotes_controller.dart';

class CotizacionesPage extends ConsumerStatefulWidget {
  const CotizacionesPage({super.key});

  @override
  ConsumerState<CotizacionesPage> createState() => _CotizacionesPageState();
}

class _CotizacionesPageState extends ConsumerState<CotizacionesPage> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final quotesAsync = ref.watch(quotesProvider);

    return PageFrame(
      title: 'Gestion de Cotizaciones',
      subtitle: 'Resumen operativo y detalle de cotizaciones activas.',
      trailing: FilledButton.icon(
        onPressed: _openNewQuoteDialog,
        icon: const Icon(Icons.add),
        label: const Text('Nueva Cotizacion'),
      ),
      child: quotesAsync.when(
        data: (quotes) {
          final filtered = _filterQuotes(quotes);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Buscar cotizacion por folio...',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _search = value.trim().toLowerCase()),
              ),
              const SizedBox(height: 24),
              _QuotesMetrics(quotes: filtered),
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
                            onPressed: () => showRemaMessage(context, 'Filtro avanzado en siguiente iteracion.'),
                            icon: const Icon(Icons.filter_list),
                            label: const Text('Filtrar'),
                          ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: _QuoteTableHeader(),
                    ),
                    if (filtered.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No hay cotizaciones para mostrar.'),
                      )
                    else
                      for (final quote in filtered)
                        _QuoteRow(
                          quote: quote,
                          onEdit: () => context.go('/presupuesto/${quote.id}'),
                          onShare: () => showRemaMessage(context, 'Compartir ${quote.quoteNumber} listo para integrar.'),
                        ),
                  ],
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: RemaPanel(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('No se pudo cargar cotizaciones.'),
                const SizedBox(height: 8),
                Text(error.toString(), style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => ref.read(quotesProvider.notifier).reload(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<QuoteRecord> _filterQuotes(List<QuoteRecord> quotes) {
    if (_search.isEmpty) {
      return quotes;
    }
    return quotes
        .where((quote) => quote.quoteNumber.toLowerCase().contains(_search))
        .toList();
  }

  Future<void> _openNewQuoteDialog() async {
    final catalogState = ref.read(conceptsCatalogProvider);
    final catalog = catalogState.valueOrNull;
    if (catalog == null) {
      showRemaMessage(context, 'Catalogo de conceptos no disponible aun.');
      await ref.read(conceptsCatalogProvider.notifier).reload();
      return;
    }

    List<ProjectLookup> projects;
    try {
      projects = await ref.read(quoteProjectsProvider.future);
    } catch (_) {
      if (!mounted) {
        return;
      }
      showRemaMessage(context, 'No se pudo cargar lista de proyectos.');
      return;
    }

    if (!mounted) {
      return;
    }

    if (projects.isEmpty) {
      showRemaMessage(context, 'No hay proyectos disponibles para crear cotizacion.');
      return;
    }

    final result = await showDialog<_NewQuoteResult>(
      context: context,
      builder: (context) => _NewQuoteDialog(catalog: catalog, projects: projects),
    );

    if (!mounted || result == null) {
      return;
    }

    final quote = await ref.read(quotesProvider.notifier).createDraft(
          projectId: result.projectId,
          universeId: result.universeId,
          projectTypeId: result.projectTypeId,
        );

    if (!mounted) {
      return;
    }
    showRemaMessage(context, 'Cotizacion ${quote.quoteNumber} creada.');
    context.go('/presupuesto/${quote.id}');
  }
}

class _QuotesMetrics extends StatelessWidget {
  const _QuotesMetrics({required this.quotes});

  final List<QuoteRecord> quotes;

  @override
  Widget build(BuildContext context) {
    final total = quotes.fold<double>(0, (sum, quote) => sum + quote.total);
    final pending = quotes.where((quote) => quote.status == 'draft').length;
    final approved = quotes.where((quote) => quote.status == 'approved').length;
    final average = quotes.isEmpty ? 0.0 : total / quotes.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final tiles = [
          RemaMetricTile(
            label: 'Total Cotizado',
            value: _money(total),
            caption: '${quotes.length} cotizaciones',
          ),
          RemaMetricTile(
            label: 'Pendientes',
            value: '$pending',
            caption: 'Estado draft',
            backgroundColor: RemaColors.surfaceWhite,
          ),
          RemaMetricTile(
            label: 'Aprobadas',
            value: '$approved',
            caption: 'Estado approved',
            backgroundColor: RemaColors.surfaceLow,
          ),
          RemaMetricTile(
            label: 'Valor Promedio',
            value: _money(average),
            caption: 'Por cotizacion',
            backgroundColor: const Color(0xFFFFDEA0),
          ),
        ];

        if (constraints.maxWidth < 960) {
          return Column(
            children: [
              for (final tile in tiles) ...[
                tile,
                if (tile != tiles.last) const SizedBox(height: 16),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (final tile in tiles) ...[
              Expanded(child: tile),
              if (tile != tiles.last) const SizedBox(width: 16),
            ],
          ],
        );
      },
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final isPending = status == 'draft';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: isPending ? const Color(0xFFFFDEA0) : const Color(0xFFDFF4DD),
      child: Text(
        (isPending ? 'Pendiente' : 'Aprobada').toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _QuoteTableHeader extends StatelessWidget {
  const _QuoteTableHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        _HeaderCell(flex: 3, label: 'Folio'),
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
  const _QuoteRow({
    required this.quote,
    required this.onEdit,
    required this.onShare,
  });

  final QuoteRecord quote;
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
        children: [
          Expanded(
            flex: 3,
            child: Text(
              quote.quoteNumber,
              style: const TextStyle(fontWeight: FontWeight.w700, color: RemaColors.primaryDark),
            ),
          ),
          Expanded(flex: 2, child: Text(_money(quote.total))),
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

class _NewQuoteResult {
  const _NewQuoteResult({
    required this.projectId,
    required this.universeId,
    required this.projectTypeId,
  });

  final String projectId;
  final String universeId;
  final String projectTypeId;
}

class _NewQuoteDialog extends StatefulWidget {
  const _NewQuoteDialog({required this.catalog, required this.projects});

  final ConceptCatalogSnapshot catalog;
  final List<ProjectLookup> projects;

  @override
  State<_NewQuoteDialog> createState() => _NewQuoteDialogState();
}

class _NewQuoteDialogState extends State<_NewQuoteDialog> {
  String? _projectId;
  String? _universeId;
  String? _projectTypeId;

  @override
  void initState() {
    super.initState();
    if (widget.projects.isNotEmpty) {
      _projectId = widget.projects.first.id;
    }
    if (widget.catalog.universes.isNotEmpty) {
      _universeId = widget.catalog.universes.first.id;
    }
    if (widget.catalog.projectTypes.isNotEmpty) {
      _projectTypeId = widget.catalog.projectTypes.first.id;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nueva cotizacion'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
              DropdownButtonFormField<String>(
                initialValue: _projectId,
                decoration: const InputDecoration(labelText: 'Proyecto'),
                items: [
                  for (final project in widget.projects)
                    DropdownMenuItem(value: project.id, child: Text(project.label)),
                ],
                onChanged: (value) => setState(() => _projectId = value),
              ),
              const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _universeId,
              decoration: const InputDecoration(labelText: 'Universo'),
              items: [
                for (final universe in widget.catalog.universes)
                  DropdownMenuItem(value: universe.id, child: Text(universe.name)),
              ],
              onChanged: (value) => setState(() => _universeId = value),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _projectTypeId,
              decoration: const InputDecoration(labelText: 'Tipo de proyecto'),
              items: [
                for (final projectType in widget.catalog.projectTypes)
                  DropdownMenuItem(value: projectType.id, child: Text(projectType.name)),
              ],
              onChanged: (value) => setState(() => _projectTypeId = value),
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
            if (_projectId == null || _universeId == null || _projectTypeId == null) {
              return;
            }
            Navigator.of(context).pop(
              _NewQuoteResult(
                projectId: _projectId!,
                universeId: _universeId!,
                projectTypeId: _projectTypeId!,
              ),
            );
          },
          child: const Text('Crear'),
        ),
      ],
    );
  }
}

String _money(double value) {
  return '\$${value.toStringAsFixed(2)}';
}
