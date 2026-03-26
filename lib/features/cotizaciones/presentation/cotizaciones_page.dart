import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../../core/config/supabase_bootstrap.dart';
import '../../../core/theme/rema_colors.dart';
import '../../../core/utils/rema_feedback.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/rema_panels.dart';
import '../domain/concept_generation.dart';
import '../domain/quote_models.dart';
import '../../clientes/presentation/clientes_mock_data.dart';
import 'concepts_catalog_controller.dart';
import 'quotes_controller.dart';

class CotizacionesPage extends ConsumerStatefulWidget {
  const CotizacionesPage({super.key});

  @override
  ConsumerState<CotizacionesPage> createState() => _CotizacionesPageState();
}

class _CotizacionesPageState extends ConsumerState<CotizacionesPage> {
  String _search = '';
  String? _statusFilter; // null = todos, 'draft', 'approved', 'declined'

  @override
  Widget build(BuildContext context) {
    final quotesAsync = ref.watch(quotesProvider);
    final projectsAsync = ref.watch(quoteProjectsProvider);
    final projectById = {
      for (final project in projectsAsync.valueOrNull ?? const <ProjectLookup>[])
        project.id: project,
    };

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
              _StatusFilterBar(
                current: _statusFilter,
                onChanged: (value) => setState(() => _statusFilter = value),
              ),
              const SizedBox(height: 16),
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
                          onViewProjectDescription: () =>
                              _showProjectDescription(context, quote, projectById[quote.projectId]),
                          onEdit: () => context.go('/presupuesto/${quote.id}'),
                          onShare: () => showRemaMessage(context, 'Compartir ${quote.quoteNumber} listo para integrar.'),
                          onAttachPdf: () => _attachApprovalPdf(quote),
                          onPreviewPdf: quote.hasApprovalPdf
                              ? () => _previewApprovalPdf(context, quote)
                              : null,
                          onGoToActas: quote.status == 'approved'
                              ? () => _goToActas(context, quote)
                              : null,
                          onApprove: quote.status == 'draft'
                              ? () => _changeStatus(quote.id, 'approved')
                              : null,
                          onDecline: quote.status != 'declined' &&
                              quote.status != 'acta_finalizada' &&
                              !quote.hasApprovalPdf
                              ? () => _changeStatus(quote.id, 'declined')
                              : null,
                          onReactivate: quote.status == 'declined'
                              ? () => _changeStatus(quote.id, 'draft')
                              : null,
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
    var result = quotes;
    if (_statusFilter != null) {
      result = result.where((q) => q.status == _statusFilter).toList();
    }
    if (_search.isNotEmpty) {
      result = result.where((q) => q.quoteNumber.toLowerCase().contains(_search)).toList();
    }
    return result;
  }

  Future<void> _changeStatus(String quoteId, String newStatus) async {
    try {
      await ref.read(quotesProvider.notifier).updateStatus(quoteId: quoteId, status: newStatus);
      if (mounted) {
        final label = switch (newStatus) {
          'approved' => 'Aprobada',
          'declined' => 'Declinada',
          _ => 'Reactivada',
        };
        showRemaMessage(context, 'Cotizacion $label.');
      }
    } catch (error) {
      if (mounted) {
        showRemaMessage(context, '$error');
      }
    }
  }

  Future<void> _attachApprovalPdf(QuoteRecord quote) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );

    if (!mounted || result == null || result.files.isEmpty) {
      return;
    }

    final file = result.files.first;
    final Uint8List? bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      showRemaMessage(context, 'No se pudo leer el PDF seleccionado.');
      return;
    }

    try {
      await ref.read(quotesProvider.notifier).attachApprovalPdf(
            quoteId: quote.id,
            bytes: bytes,
            fileName: file.name,
          );
      if (mounted) {
        showRemaMessage(context, 'PDF del pedido adjuntado en ${quote.quoteNumber}.');
      }
    } catch (error) {
      if (mounted) {
        showRemaMessage(context, '$error');
      }
    }
  }

  Future<void> _previewApprovalPdf(BuildContext context, QuoteRecord quote) async {
    if (quote.approvalPdfPath == null || quote.approvalPdfPath!.isEmpty) {
      showRemaMessage(context, 'No hay PDF adjunto para previsualizar.');
      return;
    }

    try {
      final client = SupabaseBootstrap.client;
      if (client == null) {
        showRemaMessage(context, 'No hay conexion activa con Supabase.');
        return;
      }

      // Descargar el PDF desde storage
      final bytes = await client.storage
          .from('quote-approvals')
          .download(quote.approvalPdfPath!);

      if (!mounted) return;

      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        format: PdfPageFormat.letter,
        name: 'confirmacion_pedido_${quote.quoteNumber}.pdf',
      );
    } catch (error) {
      if (mounted) {
        showRemaMessage(context, 'No se pudo cargar el PDF: $error');
      }
    }
  }

  Future<void> _goToActas(BuildContext context, QuoteRecord quote) async {
    try {
      final client = SupabaseBootstrap.client;
      if (client == null) {
        showRemaMessage(context, 'No hay conexion activa con Supabase.');
        return;
      }

      // Obtener el proyecto para extraer el clientId
      final projectRow = await client
          .from('projects')
          .select('client_id')
          .eq('id', quote.projectId)
          .single();

      final clientId = projectRow['client_id'] as String?;
      if (clientId == null || clientId.isEmpty) {
        showRemaMessage(context, 'Este proyecto no tiene cliente asignado.');
        return;
      }

      if (!mounted) return;

      // Navegar a ACTAS con el clientId
      context.push('/actas?clientId=$clientId&quoteId=${quote.id}');
    } catch (error) {
      if (mounted) {
        showRemaMessage(context, 'Error al cargar datos del cliente: $error');
      }
    }
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

        final projectKey = await ref.read(quotesProvider.notifier).reserveProjectKey();

        final quote = await ref.read(quotesProvider.notifier).createDraft(
          projectId: result.projectId,
          universeId: result.universeId,
          projectTypeId: result.projectTypeId,
          projectKey: projectKey,
        );

    if (!mounted) {
      return;
    }
    showRemaMessage(context, 'Cotizacion ${quote.quoteNumber} creada.');
    context.go('/presupuesto/${quote.id}');
  }

  Future<void> _showProjectDescription(
    BuildContext context,
    QuoteRecord quote,
    ProjectLookup? project,
  ) async {
    final description = project?.description?.trim() ?? '';
    final hasDescription = description.isNotEmpty;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Descripcion de levantamiento'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                project == null
                    ? 'Proyecto no encontrado para ${quote.quoteNumber}.'
                    : '${project.code} - ${project.name}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              if (project?.siteAddress != null && project!.siteAddress!.trim().isNotEmpty) ...[
                Text(
                  project.siteAddress!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: RemaColors.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
              ],
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: RemaColors.surfaceLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  hasDescription
                      ? description
                      : 'Este proyecto no tiene descripcion capturada en levantamiento.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
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
    Color bg;
    String label;
    switch (status) {
      case 'approved':
        bg = const Color(0xFFDFF4DD);
        label = 'Aprobada';
        break;
      case 'declined':
        bg = const Color(0xFFFFDDDD);
        label = 'Declinada';
        break;
      case 'acta_finalizada':
        bg = const Color(0xFFD0E8FF);
        label = 'Acta Final';
        break;
      default:
        bg = const Color(0xFFFFDEA0);
        label = 'Pendiente';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: bg,
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({required this.current, required this.onChanged});

  final String? current;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = <(String?, String)>[
      (null, 'Todos'),
      ('draft', 'Pendientes'),
      ('approved', 'Aprobadas'),
      ('declined', 'Declinadas'),
      ('acta_finalizada', 'Acta finalizada'),
    ];
    return Wrap(
      spacing: 8,
      children: [
        for (final (value, label) in options)
          FilterChip(
            label: Text(label),
            selected: current == value,
            onSelected: (_) => onChanged(value),
          ),
      ],
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
    required this.onViewProjectDescription,
    required this.onEdit,
    required this.onShare,
    required this.onAttachPdf,
    this.onPreviewPdf,
    this.onApprove,
    this.onDecline,
    this.onReactivate,
    this.onGoToActas,
  });

  final QuoteRecord quote;
  final VoidCallback onViewProjectDescription;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onAttachPdf;
  final VoidCallback? onPreviewPdf;
  final VoidCallback? onApprove;
  final VoidCallback? onDecline;
  final VoidCallback? onReactivate;
  final VoidCallback? onGoToActas;

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
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Align(alignment: Alignment.centerLeft, child: _StatusBadge(status: quote.status)),
                const SizedBox(width: 8),
                Icon(
                  quote.hasApprovalPdf ? Icons.picture_as_pdf : Icons.picture_as_pdf_outlined,
                  color: quote.hasApprovalPdf ? Colors.green : Colors.grey,
                  size: 18,
                ),
                if (quote.hasApprovalPdf) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.visibility_outlined,
                    color: Colors.blue,
                    size: 18,
                  ),
                ],
                if (quote.status == 'acta_finalizada') ...[
                  const SizedBox(width: 6),
                  const Tooltip(
                    message: 'Pago pendiente',
                    child: Icon(
                      Icons.payments_outlined,
                      color: Colors.amber,
                      size: 20,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: onViewProjectDescription,
                  icon: const Icon(Icons.description_outlined),
                  tooltip: 'Ver descripcion del levantamiento',
                  color: RemaColors.primaryDark,
                ),
                IconButton(onPressed: onEdit, icon: const Icon(Icons.edit_outlined), tooltip: 'Editar'),
                IconButton(onPressed: onShare, icon: const Icon(Icons.share_outlined), tooltip: 'Compartir'),
                IconButton(
                  onPressed: onAttachPdf,
                  icon: const Icon(Icons.attach_file),
                  tooltip: quote.hasApprovalPdf ? 'Reemplazar PDF pedido' : 'Adjuntar PDF pedido',
                ),
                if (onPreviewPdf != null)
                  IconButton(
                    onPressed: onPreviewPdf,
                    icon: const Icon(Icons.visibility),
                    tooltip: 'Previsualizar PDF',
                    color: Colors.blue,
                  ),
                if (onApprove != null)
                  IconButton(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check_circle_outline),
                    tooltip: 'Aprobar',
                    color: Colors.green,
                  ),
                if (onDecline != null)
                  IconButton(
                    onPressed: onDecline,
                    icon: const Icon(Icons.cancel_outlined),
                    tooltip: 'Declinar',
                    color: Colors.red,
                  ),
                if (onReactivate != null)
                  IconButton(
                    onPressed: onReactivate,
                    icon: const Icon(Icons.undo),
                    tooltip: 'Reactivar cotización',
                    color: Colors.orange,
                  ),
                if (onGoToActas != null)
                  IconButton(
                    onPressed: onGoToActas,
                    icon: const Icon(Icons.assignment_outlined),
                    tooltip: 'Ir a ACTAS',
                    color: Colors.purple,
                  ),
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
