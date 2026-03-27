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
  const CotizacionesPage({
    super.key,
    this.initialClientId,
    this.openComposerOnLoad = false,
  });

  final String? initialClientId;
  final bool openComposerOnLoad;

  @override
  ConsumerState<CotizacionesPage> createState() => _CotizacionesPageState();
}

class _CotizacionesPageState extends ConsumerState<CotizacionesPage> {
  String _search = '';
  String? _statusFilter; // null = todos, 'draft', 'concluded', 'approved', 'declined'
  bool _didOpenComposerFromRoute = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _didOpenComposerFromRoute) {
        return;
      }
      final initialClientId = widget.initialClientId?.trim();
      if (widget.openComposerOnLoad && initialClientId != null && initialClientId.isNotEmpty) {
        _didOpenComposerFromRoute = true;
        _openNewQuoteDialog(fixedClientId: initialClientId);
      }
    });
  }

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
        onPressed: () => _openNewQuoteDialog(),
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
                            onAttachPdf: quote.isConcluded
                              ? () => _attachApprovalPdf(quote, projectById[quote.projectId])
                              : null,
                          onPreviewPdf: quote.hasApprovalPdf
                              ? () => _previewApprovalPdf(context, quote)
                              : null,
                            onPreviewActa: quote.isActaFinalizada || quote.isPaid
                              ? () => _previewFinalActa(context, quote)
                              : null,
                            onDownloadActa: quote.isActaFinalizada || quote.isPaid
                              ? () => _downloadFinalActa(context, quote)
                              : null,
                            onShareActa: quote.isActaFinalizada || quote.isPaid
                              ? () => _shareFinalActa(context, quote)
                              : null,
                            onMarkPaid: quote.isActaFinalizada
                              ? () => _changeStatus(quote.id, QuoteStatus.paid)
                              : null,
                            onGoToActas: quote.isApproved
                              ? () => _goToActas(context, quote, projectById[quote.projectId])
                              : null,
                            onConclude: quote.isDraft
                              ? () => _changeStatus(quote.id, QuoteStatus.concluded)
                              : null,
                            onApprove: quote.isConcluded
                              ? () => _changeStatus(quote.id, QuoteStatus.approved)
                              : null,
                            onDecline: !quote.isDeclined &&
                              !quote.isActaFinalizada &&
                              !quote.hasApprovalPdf
                              ? () => _changeStatus(quote.id, QuoteStatus.declined)
                              : null,
                            onReactivate: (quote.isDeclined || quote.isConcluded)
                              ? () => _changeStatus(quote.id, QuoteStatus.draft)
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
          QuoteStatus.concluded => 'Concluida',
          QuoteStatus.approved => 'Aprobada',
          QuoteStatus.actaFinalizada => 'Por cobrar',
          QuoteStatus.paid => 'Pagada',
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

  Future<void> _attachApprovalPdf(QuoteRecord quote, ProjectLookup? project) async {
    ProjectLookup? resolvedProject = project;
    if (resolvedProject == null || (resolvedProject.clientId?.trim().isEmpty ?? true)) {
      try {
        final projects = await ref.read(quoteProjectsProvider.future);
        for (final item in projects) {
          if (item.id == quote.projectId) {
            resolvedProject = item;
            break;
          }
        }
      } catch (_) {}
    }

    final validationError = _approvalPdfPrerequisiteError(quote, resolvedProject);
    if (validationError != null) {
      showRemaMessage(context, validationError);
      return;
    }

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

  String? _approvalPdfPrerequisiteError(QuoteRecord quote, ProjectLookup? project) {
    if (quote.isDeclined) {
      return 'No puedes adjuntar el PDF de aprobacion a una cotizacion declinada.';
    }
    if (quote.isActaFinalizada) {
      return 'No puedes adjuntar el PDF de aprobacion a una cotizacion con acta finalizada.';
    }
    if (!quote.isConcluded) {
      return 'Primero debes concluir la cotizacion antes de adjuntar el PDF de aprobacion.';
    }
    if (project != null && (project.clientId?.trim().isEmpty ?? true)) {
      return 'Debes vincular la cotizacion a un cliente registrado antes de adjuntar el PDF de aprobacion.';
    }
    if (quote.total <= 0) {
      return 'La cotizacion debe estar concluida: agrega al menos un concepto con importe antes de adjuntar el PDF de aprobacion.';
    }
    return null;
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

  Future<ActaDocumentRecord?> _loadFinalActaDocument(QuoteRecord quote) async {
    return ref.read(quotesRepositoryProvider).fetchActaDocument(quote.id);
  }

  Future<void> _previewFinalActa(BuildContext context, QuoteRecord quote) async {
    final document = await _loadFinalActaDocument(quote);
    if (document == null) {
      if (mounted) {
        showRemaMessage(context, 'No hay acta final guardada para esta cotizacion.');
      }
      return;
    }
    await Printing.layoutPdf(onLayout: (_) async => document.bytes, name: document.fileName);
  }

  Future<void> _downloadFinalActa(BuildContext context, QuoteRecord quote) async {
    final document = await _loadFinalActaDocument(quote);
    if (document == null) {
      if (mounted) {
        showRemaMessage(context, 'No hay acta final guardada para esta cotizacion.');
      }
      return;
    }
    await Printing.sharePdf(bytes: document.bytes, filename: document.fileName);
    if (mounted) {
      showRemaMessage(context, 'Acta final lista para descarga.');
    }
  }

  Future<void> _shareFinalActa(BuildContext context, QuoteRecord quote) async {
    final document = await _loadFinalActaDocument(quote);
    if (document == null) {
      if (mounted) {
        showRemaMessage(context, 'No hay acta final guardada para esta cotizacion.');
      }
      return;
    }
    await Printing.sharePdf(bytes: document.bytes, filename: document.fileName);
    if (mounted) {
      showRemaMessage(context, 'Acta final lista para compartir.');
    }
  }

  Future<void> _goToActas(BuildContext context, QuoteRecord quote, ProjectLookup? project) async {
    try {
      ProjectLookup? resolvedProject = project;
      if (resolvedProject == null) {
        try {
          final projects = await ref.read(quoteProjectsProvider.future);
          for (final item in projects) {
            if (item.id == quote.projectId) {
              resolvedProject = item;
              break;
            }
          }
        } catch (_) {}
      }

      String? clientId = resolvedProject?.clientId?.trim();
      if (clientId == null || clientId.isEmpty) {
        final client = SupabaseBootstrap.client;
        if (client != null && RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(quote.projectId)) {
          final projectRow = await client
              .from('projects')
              .select('client_id')
              .eq('id', quote.projectId)
              .maybeSingle();
          clientId = (projectRow?['client_id'] as String?)?.trim();
        }
      }

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

  Future<void> _openNewQuoteDialog({String? fixedClientId}) async {
    final catalogState = ref.read(conceptsCatalogProvider);
    final catalog = catalogState.valueOrNull;
    if (catalog == null) {
      showRemaMessage(context, 'Catalogo de conceptos no disponible aun.');
      await ref.read(conceptsCatalogProvider.notifier).reload();
      return;
    }

    final clientOptions = await _fetchClientOptions();
    if (!mounted) {
      return;
    }

    final normalizedFixedClientId = fixedClientId?.trim();
    ClientOption? fixedClient;
    if (normalizedFixedClientId != null && normalizedFixedClientId.isNotEmpty) {
      for (final item in clientOptions) {
        if (item.id == normalizedFixedClientId) {
          fixedClient = item;
          break;
        }
      }
      if (fixedClient == null) {
        showRemaMessage(context, 'No se pudo resolver el cliente para la nueva cotizacion.');
        return;
      }
    }

    if (fixedClient == null && clientOptions.isEmpty) {
      showRemaMessage(context, 'No hay clientes disponibles para crear cotizacion.');
      return;
    }

    if (!mounted) {
      return;
    }

    final result = await showDialog<_NewQuoteResult>(
      context: context,
      builder: (context) => _NewQuoteDialog(
        catalog: catalog,
        clients: clientOptions,
        fixedClient: fixedClient,
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    ProjectLookup project;
    try {
      final projectKey = await ref.read(quotesProvider.notifier).reserveProjectKey();
      project = await ref.read(quotesProvider.notifier).createProject(
            input: NewProjectInput(
              code: projectKey,
              name: result.projectName,
              clientId: result.clientId,
            ),
          );
      final quote = await ref.read(quotesProvider.notifier).createDraft(
            projectId: project.id,
            universeId: result.universeId,
            projectTypeId: result.projectTypeId,
            projectKey: projectKey,
          );

      if (!mounted) {
        return;
      }
      showRemaMessage(context, 'Cotizacion ${quote.quoteNumber} creada para ${project.name}.');
      context.go('/presupuesto/${quote.id}');
    } catch (error) {
      if (!mounted) {
        return;
      }
      showRemaMessage(context, '$error');
    }
  }

  Future<List<ClientOption>> _fetchClientOptions() async {
    final mergedByName = <String, ClientOption>{
      for (final client in mockClients)
        client.name.trim().toLowerCase(): ClientOption(id: client.id, name: client.name),
    };

    final client = SupabaseBootstrap.client;
    if (client == null) {
      return mergedByName.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    }

    try {
      final rows = await client
          .from('clients')
          .select('id, business_name')
          .order('business_name');
      for (final row in rows) {
        final id = (row['id'] as String? ?? '').trim();
        final name = (row['business_name'] as String? ?? '').trim();
        if (id.isEmpty || name.isEmpty) {
          continue;
        }
        mergedByName[name.toLowerCase()] = ClientOption(id: id, name: name);
      }
    } catch (_) {}

    final result = mergedByName.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    return result;
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
    final pending = quotes.where((quote) => quote.isDraft).length;
    final concluded = quotes.where((quote) => quote.isConcluded).length;
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
            label: 'Concluidas',
            value: '$concluded',
            caption: 'Listas para aprobacion',
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
      case QuoteStatus.concluded:
        bg = const Color(0xFFFFF1CC);
        label = 'Concluida';
        break;
      case QuoteStatus.approved:
        bg = const Color(0xFFDFF4DD);
        label = 'Aprobada';
        break;
      case QuoteStatus.declined:
        bg = const Color(0xFFFFDDDD);
        label = 'Declinada';
        break;
      case QuoteStatus.actaFinalizada:
        bg = const Color(0xFFD0E8FF);
        label = 'Por cobrar';
        break;
      case QuoteStatus.paid:
        bg = const Color(0xFFE3F2FD);
        label = 'Pagada';
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
      ('concluded', 'Concluidas'),
      ('approved', 'Aprobadas'),
      ('declined', 'Declinadas'),
      ('acta_finalizada', 'Por cobrar'),
      ('paid', 'Pagadas'),
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
    this.onAttachPdf,
    this.onPreviewPdf,
    this.onPreviewActa,
    this.onDownloadActa,
    this.onShareActa,
    this.onMarkPaid,
    this.onConclude,
    this.onApprove,
    this.onDecline,
    this.onReactivate,
    this.onGoToActas,
  });

  final QuoteRecord quote;
  final VoidCallback onViewProjectDescription;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback? onAttachPdf;
  final VoidCallback? onPreviewPdf;
  final VoidCallback? onPreviewActa;
  final VoidCallback? onDownloadActa;
  final VoidCallback? onShareActa;
  final VoidCallback? onMarkPaid;
  final VoidCallback? onConclude;
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
                if (quote.isActaFinalizada || quote.isPaid) ...[
                  IconButton(
                    onPressed: onShareActa,
                    icon: const Icon(Icons.share_outlined),
                    tooltip: 'Compartir acta final',
                  ),
                  IconButton(
                    onPressed: onPreviewActa,
                    icon: const Icon(Icons.visibility),
                    tooltip: 'Previsualizar acta final',
                    color: Colors.blue,
                  ),
                  IconButton(
                    onPressed: onDownloadActa,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    tooltip: 'Descargar acta final',
                    color: Colors.deepPurple,
                  ),
                  if (quote.isActaFinalizada)
                    IconButton(
                      onPressed: onMarkPaid,
                      icon: const Icon(Icons.payments_outlined),
                      tooltip: 'Marcar como pagada',
                      color: Colors.green,
                    ),
                ] else ...[
                IconButton(
                  onPressed: onViewProjectDescription,
                  icon: const Icon(Icons.description_outlined),
                  tooltip: 'Ver descripcion del levantamiento',
                  color: RemaColors.primaryDark,
                ),
                IconButton(onPressed: onEdit, icon: const Icon(Icons.edit_outlined), tooltip: 'Editar'),
                IconButton(onPressed: onShare, icon: const Icon(Icons.share_outlined), tooltip: 'Compartir'),
                if (onAttachPdf != null)
                  IconButton(
                    onPressed: onAttachPdf,
                    icon: const Icon(Icons.attach_file),
                    tooltip: quote.hasApprovalPdf ? 'Reemplazar PDF pedido' : 'Adjuntar PDF pedido',
                  ),
                if (onConclude != null)
                  IconButton(
                    onPressed: onConclude,
                    icon: const Icon(Icons.task_alt_outlined),
                    tooltip: 'Concluir cotización',
                    color: Colors.orange.shade700,
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
                    tooltip: quote.isConcluded ? 'Reabrir cotización' : 'Reactivar cotización',
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
    required this.clientId,
    required this.projectName,
    required this.universeId,
    required this.projectTypeId,
  });

  final String clientId;
  final String projectName;
  final String universeId;
  final String projectTypeId;
}

class ClientOption {
  const ClientOption({required this.id, required this.name});

  final String id;
  final String name;
}

class _NewQuoteDialog extends StatefulWidget {
  const _NewQuoteDialog({
    required this.catalog,
    required this.clients,
    this.fixedClient,
  });

  final ConceptCatalogSnapshot catalog;
  final List<ClientOption> clients;
  final ClientOption? fixedClient;

  @override
  State<_NewQuoteDialog> createState() => _NewQuoteDialogState();
}

class _NewQuoteDialogState extends State<_NewQuoteDialog> {
  static const int _minimumProjectNameLength = 4;

  String? _clientId;
  String? _universeId;
  String? _projectTypeId;
  late final TextEditingController _projectNameController;
  late final TextEditingController _clientSearchController;
  String? _projectNameError;
  String? _clientError;
  String? _projectTypeError;

  @override
  void initState() {
    super.initState();
    _projectNameController = TextEditingController();
    _clientSearchController = TextEditingController(text: widget.fixedClient?.name ?? '');
    _clientId = widget.fixedClient?.id;
    if (widget.catalog.universes.isNotEmpty) {
      _universeId = widget.catalog.universes.first.id;
    }
    _projectTypeId = _normalizedProjectTypeId(
      universeId: _universeId,
      currentProjectTypeId: widget.catalog.projectTypes.isNotEmpty
          ? widget.catalog.projectTypes.first.id
          : null,
    );
  }

  @override
  void dispose() {
    _projectNameController.dispose();
    _clientSearchController.dispose();
    super.dispose();
  }

  String _normalizedProjectName(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  List<ProjectTypeCatalogItem> _compatibleProjectTypes(String? universeId) {
    if (universeId == null || universeId.trim().isEmpty) {
      return widget.catalog.projectTypes;
    }
    final compatible = widget.catalog.projectTypesForUniverse(universeId);
    return compatible.isNotEmpty ? compatible : widget.catalog.projectTypes;
  }

  String? _normalizedProjectTypeId({
    required String? universeId,
    required String? currentProjectTypeId,
  }) {
    final compatible = _compatibleProjectTypes(universeId);
    if (compatible.isEmpty) {
      return currentProjectTypeId;
    }
    if (currentProjectTypeId != null &&
        compatible.any((item) => item.id == currentProjectTypeId)) {
      return currentProjectTypeId;
    }
    return compatible.first.id;
  }

  @override
  Widget build(BuildContext context) {
    final compatibleProjectTypes = _compatibleProjectTypes(_universeId);

    return AlertDialog(
      title: const Text('Nueva cotizacion'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.fixedClient != null)
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Cliente'),
                child: Text(widget.fixedClient!.name),
              )
            else
              Autocomplete<ClientOption>(
                displayStringForOption: (option) => option.name,
                optionsBuilder: (textEditingValue) {
                  final query = textEditingValue.text.trim().toLowerCase();
                  if (query.isEmpty) {
                    return widget.clients;
                  }
                  return widget.clients.where(
                    (client) => client.name.toLowerCase().contains(query),
                  );
                },
                onSelected: (option) {
                  setState(() {
                    _clientId = option.id;
                    _clientError = null;
                  });
                  _clientSearchController.value = TextEditingValue(
                    text: option.name,
                    selection: TextSelection.collapsed(offset: option.name.length),
                  );
                },
                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                  if (controller.text != _clientSearchController.text) {
                    controller.value = _clientSearchController.value;
                  }
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      labelText: 'Cliente',
                      hintText: 'Busca y selecciona un cliente',
                      errorText: _clientError,
                    ),
                    onChanged: (value) {
                      _clientSearchController.value = controller.value;
                      if (_clientError != null) {
                        setState(() => _clientError = null);
                      }
                      final normalized = value.trim().toLowerCase();
                      final selected = widget.clients.where(
                        (client) => client.name.toLowerCase() == normalized,
                      );
                      setState(() {
                        _clientId = selected.isNotEmpty ? selected.first.id : null;
                      });
                    },
                    onSubmitted: (_) => onFieldSubmitted(),
                  );
                },
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _projectNameController,
              decoration: InputDecoration(
                labelText: 'Proyecto',
                hintText: 'Escribe el proyecto a realizar',
                errorText: _projectNameError,
              ),
              textCapitalization: TextCapitalization.words,
              onChanged: (_) {
                if (_projectNameError != null) {
                  setState(() => _projectNameError = null);
                }
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _universeId,
              decoration: const InputDecoration(labelText: 'Universo'),
              items: [
                for (final universe in widget.catalog.universes)
                  DropdownMenuItem(value: universe.id, child: Text(universe.name)),
              ],
              onChanged: (value) {
                setState(() {
                  _universeId = value;
                  _projectTypeId = _normalizedProjectTypeId(
                    universeId: value,
                    currentProjectTypeId: _projectTypeId,
                  );
                  _projectTypeError = null;
                });
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _projectTypeId,
              decoration: InputDecoration(
                labelText: 'Tipo de proyecto',
                errorText: _projectTypeError,
              ),
              items: [
                for (final projectType in compatibleProjectTypes)
                  DropdownMenuItem(value: projectType.id, child: Text(projectType.name)),
              ],
              onChanged: (value) => setState(() {
                _projectTypeId = value;
                _projectTypeError = null;
              }),
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
            final projectName = _normalizedProjectName(_projectNameController.text);
            if (projectName.isEmpty) {
              setState(() => _projectNameError = 'Escribe el nombre del proyecto a realizar.');
              return;
            }
            if (projectName.length < _minimumProjectNameLength) {
              setState(
                () => _projectNameError =
                    'El nombre del proyecto debe tener al menos $_minimumProjectNameLength caracteres.',
              );
              return;
            }
            if (_clientId == null) {
              setState(() => _clientError = 'Selecciona un cliente valido de la lista.');
              return;
            }
            if (_universeId == null || _projectTypeId == null) {
              return;
            }
            if (!widget.catalog.hasTemplatesForUniverseAndProjectType(
              _universeId!,
              _projectTypeId!,
            )) {
              setState(
                () => _projectTypeError =
                    'No hay conceptos cargados para la combinacion seleccionada.',
              );
              return;
            }
            Navigator.of(context).pop(
              _NewQuoteResult(
                clientId: _clientId!,
                projectName: projectName,
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
