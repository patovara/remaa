import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/config/company_profile.dart';
import '../../../core/theme/rema_colors.dart';
import '../../../core/utils/rema_feedback.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/rema_panels.dart';
import '../../cotizaciones/domain/quote_models.dart';
import '../../cotizaciones/domain/concept_generation.dart';
import '../../cotizaciones/presentation/concepts_catalog_controller.dart';
import '../../cotizaciones/presentation/quotes_controller.dart';
import '../../levantamiento/presentation/levantamiento_state.dart';
import 'quote_item_editor_dialog.dart';

class PresupuestoPage extends ConsumerWidget {
  const PresupuestoPage({super.key, required this.quoteId});

  final String quoteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quotesState = ref.watch(quotesProvider);
    final itemsState = ref.watch(quoteItemsProvider(quoteId));
    final catalogState = ref.watch(conceptsCatalogProvider);
    final projectsState = ref.watch(quoteProjectsProvider);
    final activeLevantamiento = ref.watch(activeLevantamientoProvider);
    final currentQuote = _findQuote(quotesState.valueOrNull ?? const [], quoteId);
    final currentItems = itemsState.valueOrNull;
    final projectById = {
      for (final project in projectsState.valueOrNull ?? const <ProjectLookup>[])
        project.id: project,
    };
    final currentProject =
        currentQuote == null ? null : projectById[currentQuote.projectId];

    return PageFrame(
      title: 'Presupuesto',
      subtitle: 'Vista formal de cotizacion ajustada para revision y envio.',
      trailing: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (currentQuote != null && currentQuote.isDraft)
            FilledButton.icon(
              onPressed: () => _changeQuoteStatus(
                context,
                ref,
                currentQuote,
                QuoteStatus.concluded,
              ),
              icon: const Icon(Icons.task_alt_outlined),
              label: const Text('Concluir'),
            ),
          if (currentQuote != null && currentQuote.isConcluded)
            OutlinedButton.icon(
              onPressed: () => _changeQuoteStatus(
                context,
                ref,
                currentQuote,
                QuoteStatus.draft,
              ),
              icon: const Icon(Icons.undo),
              label: const Text('Reabrir'),
            ),
          IconButton(
            onPressed: currentQuote != null
                ? () async {
                    final persistedEntries = await ref
                        .read(projectSurveyEntriesProvider(currentQuote.projectId).future)
                        .catchError((_) => const <SurveyEntryRecord>[]);
                    if (!context.mounted) {
                      return;
                    }
                    await _showProjectDescription(
                      context,
                      currentQuote,
                      currentProject,
                      activeLevantamiento,
                      persistedEntries,
                    );
                  }
                : null,
            icon: const Icon(Icons.description_outlined, color: Colors.black),
          ),
          IconButton(
            onPressed: currentQuote != null && currentItems != null
                ? () => _printQuote(context, ref: ref, quote: currentQuote, items: currentItems)
                : null,
            icon: const Icon(Icons.print_outlined),
          ),
          IconButton(
            onPressed: currentQuote != null && currentItems != null
                ? () => _downloadQuote(context, ref: ref, quote: currentQuote, items: currentItems)
                : null,
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            onPressed: currentQuote != null && currentItems != null
                ? () => _shareQuote(context, ref: ref, quote: currentQuote, items: currentItems)
                : null,
            icon: const Icon(Icons.share_outlined),
          ),
        ],
      ),
      child: quotesState.when(
        data: (quotes) {
          final quote = _findQuote(quotes, quoteId);
          if (quote == null) {
            return const RemaPanel(child: Text('No se encontro la cotizacion solicitada.'));
          }

          return itemsState.when(
            data: (items) => _BudgetView(
              quote: quote,
              items: items,
              canEditItems: quote.canEditItems,
              contextState: ref.watch(quoteContextProvider(quote.projectId)),
              universeLabel: _labelById(
                quote.universeId,
                catalogState.valueOrNull?.universes.map((item) => (item.id, item.name)).toList() ??
                    const <(String, String)>[],
              ),
              projectTypeLabel: _labelById(
                quote.projectTypeId,
                catalogState.valueOrNull?.projectTypes
                        .map((item) => (item.id, item.name))
                        .toList() ??
                    const <(String, String)>[],
              ),
              onAddItem: () => _openItemDialog(context, ref, quote, null, catalogState),
              onEditItem: (item) => _openItemDialog(context, ref, quote, item, catalogState),
              onDeleteItem: (item) => ref.read(quoteItemsProvider(quote.id).notifier).remove(item.id),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => RemaPanel(
              child: Column(
                children: [
                  const Text('No se pudieron cargar los conceptos de la cotizacion.'),
                  const SizedBox(height: 8),
                  Text(error.toString()),
                ],
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => RemaPanel(
          child: Text('No se pudo cargar la cotizacion: $error'),
        ),
      ),
    );
  }

  Future<void> _changeQuoteStatus(
    BuildContext context,
    WidgetRef ref,
    QuoteRecord quote,
    String nextStatus,
  ) async {
    try {
      await ref.read(quotesProvider.notifier).updateStatus(
            quoteId: quote.id,
            status: nextStatus,
          );
      if (!context.mounted) {
        return;
      }
      final message = switch (nextStatus) {
        QuoteStatus.concluded => 'Cotizacion concluida. Ya puedes adjuntar el PDF de aprobacion.',
        QuoteStatus.draft => 'Cotizacion reabierta para edicion.',
        _ => 'Estado actualizado.',
      };
      showRemaMessage(context, message);
      if (nextStatus == QuoteStatus.concluded) {
        context.go('/cotizaciones');
      }
    } catch (error) {
      if (context.mounted) {
        showRemaMessage(context, '$error');
      }
    }
  }

  QuoteRecord? _findQuote(List<QuoteRecord> quotes, String id) {
    for (final quote in quotes) {
      if (quote.id == id) {
        return quote;
      }
    }
    return null;
  }

  String _labelById(String id, List<(String, String)> options) {
    for (final option in options) {
      if (option.$1 == id) {
        return option.$2;
      }
    }
    return id;
  }

  Future<void> _openItemDialog(
    BuildContext context,
    WidgetRef ref,
    QuoteRecord quote,
    QuoteItemRecord? initial,
    AsyncValue<ConceptCatalogSnapshot> catalogState,
  ) async {
    final catalog = catalogState.valueOrNull;
    if (catalog == null) {
      showRemaMessage(context, 'Catalogo no disponible aun.');
      return;
    }

    final result = await showDialog<QuoteItemEditorResult>(
      context: context,
      builder: (context) => QuoteItemEditorDialog(
        quote: quote,
        catalog: catalog,
        initialValue: initial,
      ),
    );

    if (result == null) {
      return;
    }

    await ref.read(quoteItemsProvider(quote.id).notifier).save(result.item);
    if (context.mounted) {
      showRemaMessage(context, 'Concepto guardado en cotizacion.');
    }
  }

  Future<void> _printQuote(
    BuildContext context, {
    required WidgetRef ref,
    required QuoteRecord quote,
    required List<QuoteItemRecord> items,
  }) async {
    final bytes = await _buildQuotePdf(ref: ref, quote: quote, items: items);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      format: PdfPageFormat.letter,
      name: 'cotizacion_${quote.quoteNumber}.pdf',
    );
  }

  Future<void> _downloadQuote(
    BuildContext context, {
    required WidgetRef ref,
    required QuoteRecord quote,
    required List<QuoteItemRecord> items,
  }) async {
    final bytes = await _buildQuotePdf(ref: ref, quote: quote, items: items);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'cotizacion_${quote.quoteNumber}.pdf',
    );
    if (context.mounted) {
      showRemaMessage(context, 'Cotizacion lista para descarga.');
    }
  }

  Future<void> _shareQuote(
    BuildContext context, {
    required WidgetRef ref,
    required QuoteRecord quote,
    required List<QuoteItemRecord> items,
  }) async {
    final bytes = await _buildQuotePdf(ref: ref, quote: quote, items: items);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'cotizacion_${quote.quoteNumber}.pdf',
    );
    if (context.mounted) {
      showRemaMessage(context, 'Cotizacion lista para compartir.');
    }
  }

  Future<void> _showProjectDescription(
    BuildContext context,
    QuoteRecord quote,
    ProjectLookup? project,
    ActiveLevantamientoSession? activeLevantamiento,
    List<SurveyEntryRecord> persistedEntries,
  ) async {
    final description = project?.description?.trim() ?? '';
    final activeMatchesQuote =
        activeLevantamiento != null && activeLevantamiento.quoteId == quote.id;
    final sessionEntries = activeMatchesQuote
        ? activeLevantamiento.entries
      : const <SurveyEntryRecord>[];
    final hasSessionEntries = sessionEntries.isNotEmpty;
    final mergedEntries = <SurveyEntryRecord>[...persistedEntries];
    for (final entry in sessionEntries) {
      final duplicate = mergedEntries.any(
        (item) =>
            item.description.trim() == entry.description.trim() &&
            item.evidencePreviewList.length == entry.evidencePreviewList.length,
      );
      if (!duplicate) {
        mergedEntries.add(entry);
      }
    }
    mergedEntries.sort((a, b) {
      final left = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final right = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return left.compareTo(right);
    });
    final parsedDescriptions = hasSessionEntries
        ? <String>[]
        : description
                .split('\n\n---\n\n')
                .map((item) => item.trim())
                .where((item) => item.isNotEmpty)
                .toList();
    final hasDescriptions = hasSessionEntries || parsedDescriptions.isNotEmpty;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Descripcion de levantamiento'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
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
              if (!hasDescriptions)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: RemaColors.surfaceLow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Este proyecto no tiene descripcion capturada en levantamiento.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              if (mergedEntries.isNotEmpty)
                ...mergedEntries
                    .map((entry) => _LevantamientoEntryCard(entry: entry))
                    ,
              if (mergedEntries.isEmpty)
                ...parsedDescriptions
                    .map((entry) => _LevantamientoEntryCard(
                          entry: SurveyEntryRecord(description: entry),
                        ))
                    ,
            ],
          ),
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

  Future<Uint8List> _buildQuotePdf({
    required WidgetRef ref,
    required QuoteRecord quote,
    required List<QuoteItemRecord> items,
  }) async {
    final pdf = pw.Document();
    final logo = await _loadHeaderLogo();
    final watermark = await _loadWatermarkImage();
    final money = NumberFormat.currency(symbol: r'$', decimalDigits: 2, locale: 'en_US');
    final dateLabel = quote.validUntil != null ? _date(quote.validUntil!) : _date(DateTime.now());
    final quoteContext =
      await ref.read(quotesProvider.notifier).fetchQuoteContext(projectId: quote.projectId);
    final catalog = await ref.read(conceptsCatalogProvider.future);
    final activeLevantamiento = ref.read(activeLevantamientoProvider);
    final persistedEntries = await ref
        .read(projectSurveyEntriesProvider(quote.projectId).future)
        .catchError((_) => const <SurveyEntryRecord>[]);
    final activeMatchesQuote =
        activeLevantamiento != null && activeLevantamiento.quoteId == quote.id;
    final sessionEntries =
        activeMatchesQuote ? activeLevantamiento.entries : const <SurveyEntryRecord>[];
    final mergedEntries = <SurveyEntryRecord>[...persistedEntries];
    for (final entry in sessionEntries) {
      final duplicate = mergedEntries.any(
        (item) =>
            item.description.trim() == entry.description.trim() &&
            item.evidencePreviewList.length == entry.evidencePreviewList.length,
      );
      if (!duplicate) {
        mergedEntries.add(entry);
      }
    }
    final universeLabel = _labelById(
      quote.universeId,
      [for (final item in catalog.universes) (item.id, item.name)],
    );
    final projectTypeLabel = _labelById(
      quote.projectTypeId,
      [for (final item in catalog.projectTypes) (item.id, item.name)],
    );
    final evidenceEntries = mergedEntries
        .where((entry) => entry.evidencePreviewList.any((bytes) => bytes.isNotEmpty))
        .toList();
    if (evidenceEntries.isEmpty && activeLevantamiento?.quoteId == quote.id) {
      final fallback = activeLevantamiento?.evidencePreviewList ?? const <Uint8List>[];
      if (fallback.any((bytes) => bytes.isNotEmpty)) {
        evidenceEntries.add(
          SurveyEntryRecord(
            description: 'Evidencia de levantamiento',
            evidencePreviewList: fallback,
          ),
        );
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.letter,
          margin: const pw.EdgeInsets.all(28),
          buildBackground: watermark != null
              ? (_) => pw.Positioned.fill(
                    child: pw.Center(
                      child: pw.Opacity(
                        opacity: 0.10,
                        child: pw.Image(watermark, width: 380, fit: pw.BoxFit.contain),
                      ),
                    ),
                  )
              : null,
        ),
        build: (context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                width: 92,
                height: 46,
                alignment: pw.Alignment.centerLeft,
                child: logo != null
                    ? pw.Image(logo, fit: pw.BoxFit.contain)
                    : pw.Text(
                        CompanyProfile.brandName,
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
                      ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('COTIZACION', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                  pw.Text('Folio: ${quote.quoteNumber}'),
                  pw.Text('Fecha: $dateLabel'),
                  pw.Text('Estado: ${quote.status.toUpperCase()}'),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(width: 0.7, color: PdfColors.black),
            ),
            child: pw.Column(
              children: [
                pw.Row(
                  children: [
                    pw.Expanded(child: _pdfHeaderField('Proyecto', quoteContext.projectName)),
                    pw.SizedBox(width: 8),
                    pw.Expanded(child: _pdfHeaderField('Cliente', quoteContext.clientName)),
                  ],
                ),
                pw.SizedBox(height: 6),
                pw.Row(
                  children: [
                    pw.Expanded(child: _pdfHeaderField('Direccion', quoteContext.address)),
                    pw.SizedBox(width: 8),
                    pw.Expanded(child: _pdfHeaderField('Ubicacion', quoteContext.location)),
                  ],
                ),
                pw.SizedBox(height: 6),
                pw.Row(
                  children: [
                    pw.Expanded(child: _pdfHeaderField('Universo', universeLabel)),
                    pw.SizedBox(width: 8),
                    pw.Expanded(child: _pdfHeaderField('Tipo de remodelacion', projectTypeLabel)),
                  ],
                ),
              ],
            ),
          ),
          if (evidenceEntries.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            _pdfEvidenceBlocks(entries: evidenceEntries),
          ],
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(4.6),
              1: const pw.FlexColumnWidth(1.2),
              2: const pw.FlexColumnWidth(0.9),
              3: const pw.FlexColumnWidth(1.3),
              4: const pw.FlexColumnWidth(1.4),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  _pdfCell('Concepto / Descripcion', isHeader: true),
                  _pdfCell('Unidad', isHeader: true),
                  _pdfCell('Cant.', isHeader: true),
                  _pdfCell('P.U.', isHeader: true),
                  _pdfCell('Importe', isHeader: true),
                ],
              ),
              for (final item in items)
                pw.TableRow(
                  children: [
                    _pdfCell(item.concept),
                    _pdfCell(item.unit),
                    _pdfCell(item.quantity.toStringAsFixed(2)),
                    _pdfCell(money.format(item.unitPrice)),
                    _pdfCell(money.format(item.lineTotal)),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.SizedBox(
              width: 220,
              child: pw.Column(
                children: [
                  _pdfTotalRow('Subtotal', money.format(quote.subtotal)),
                  _pdfTotalRow('IVA (16%)', money.format(quote.tax)),
                  _pdfTotalRow('Total', money.format(quote.total), strong: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return Uint8List.fromList(await pdf.save());
  }

  Future<pw.MemoryImage?> _loadHeaderLogo() async {
    try {
      final data = await rootBundle.load('assets/images/logo_remaa.png');
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  Future<pw.MemoryImage?> _loadWatermarkImage() async {
    try {
      final data = await rootBundle.load('assets/images/marca_agua_remaa.png');
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }
}

pw.Widget _pdfEvidenceBlocks({
  required List<SurveyEntryRecord> entries,
}) {
  // Aplanar todas las imágenes de todas las entradas en una sola lista
  final allImages = [
    for (final entry in entries)
      for (final bytes in entry.evidencePreviewList)
        if (bytes.isNotEmpty) pw.MemoryImage(bytes),
  ];

  if (allImages.isEmpty) {
    return pw.SizedBox.shrink();
  }

  return pw.Container(
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(width: 0.6, color: PdfColors.grey600),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Registro fotografico',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5),
        ),
        pw.SizedBox(height: 6),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.start,
          children: [
            for (final image in allImages) ...[
              pw.Container(
                width: 120,
                height: 90,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(width: 0.4, color: PdfColors.grey500),
                ),
                child: pw.Image(image, fit: pw.BoxFit.cover),
              ),
              pw.SizedBox(width: 6),
            ],
          ],
        ),
      ],
    ),
  );
}

class _BudgetView extends StatelessWidget {
  const _BudgetView({
    required this.quote,
    required this.items,
    required this.canEditItems,
    required this.contextState,
    required this.universeLabel,
    required this.projectTypeLabel,
    required this.onAddItem,
    required this.onEditItem,
    required this.onDeleteItem,
  });

  final QuoteRecord quote;
  final List<QuoteItemRecord> items;
  final bool canEditItems;
  final AsyncValue<QuoteContextInfo> contextState;
  final String universeLabel;
  final String projectTypeLabel;
  final VoidCallback onAddItem;
  final ValueChanged<QuoteItemRecord> onEditItem;
  final ValueChanged<QuoteItemRecord> onDeleteItem;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: RemaPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (ctx, constraints) {
                  final isMobile = constraints.maxWidth < 600;
                  final leftCol = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Image.asset('assets/images/logo_remaa.png', height: 56),
                      const SizedBox(height: 16),
                      Text(CompanyProfile.brandName, style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(CompanyProfile.legalName),
                      Text('TEL: ${CompanyProfile.phone}'),
                    ],
                  );
                  final rightCol = Column(
                    crossAxisAlignment: isMobile
                        ? CrossAxisAlignment.start
                        : CrossAxisAlignment.end,
                    children: [
                      Text(
                        'COTIZACION',
                        style: Theme.of(context).textTheme.headlineLarge?.copyWith(color: RemaColors.primaryDark),
                      ),
                      const SizedBox(height: 6),
                      Text('FOLIO: ${quote.quoteNumber}'),
                      Text('FECHA: ${_date(quote.validUntil ?? DateTime.now())}'),
                      Text('ESTADO: ${quote.status.toUpperCase()}'),
                    ],
                  );
                  if (isMobile) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [leftCol, const SizedBox(height: 16), rightCol],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: leftCol),
                      rightCol,
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              contextState.when(
                data: (context) => Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: RemaColors.surfaceLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: RemaColors.outlineVariant.withValues(alpha: 0.35)),
                  ),
                  child: Wrap(
                    spacing: 24,
                    runSpacing: 10,
                    children: [
                      _ContextField(label: 'Proyecto', value: context.projectName),
                      _ContextField(label: 'Cliente', value: context.clientName),
                      _ContextField(label: 'Direccion', value: context.address),
                      _ContextField(label: 'Ubicacion', value: context.location),
                      _ContextField(label: 'Universo', value: universeLabel),
                      _ContextField(label: 'Tipo de remodelacion', value: projectTypeLabel),
                    ],
                  ),
                ),
                loading: () => const LinearProgressIndicator(minHeight: 2),
                error: (_, _) => Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: RemaColors.surfaceLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: RemaColors.outlineVariant.withValues(alpha: 0.35)),
                  ),
                  child: const Text('No se pudo cargar el contexto del proyecto.'),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: canEditItems ? onAddItem : null,
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar concepto'),
                  ),
                  if (!canEditItems) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'La edición de conceptos se bloquea cuando la cotización ya fue concluida, aprobada o cerrada.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Concepto / Descripcion')),
                    DataColumn(label: Text('Unidad')),
                    DataColumn(label: Text('Cant.')),
                    DataColumn(label: Text('P.U.')),
                    DataColumn(label: Text('Importe')),
                    DataColumn(label: Text('Acciones')),
                  ],
                  rows: [
                    for (final item in items)
                      DataRow(cells: [
                        DataCell(
                          SizedBox(
                            width: 520,
                            child: Text(
                              item.concept,
                              softWrap: true,
                            ),
                          ),
                        ),
                        DataCell(Text(item.unit)),
                        DataCell(Text(item.quantity.toStringAsFixed(2))),
                        DataCell(Text(_money(item.unitPrice))),
                        DataCell(Text(_money(item.lineTotal))),
                        DataCell(
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: canEditItems ? () => onEditItem(item) : null,
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: canEditItems ? () => onDeleteItem(item) : null,
                              ),
                            ],
                          ),
                        ),
                      ]),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (ctx, constraints) {
                  final isMobile = constraints.maxWidth < 600;
                  final importeBox = Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      border: Border.all(color: RemaColors.outlineVariant.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('IMPORTE CON LETRA'),
                        const SizedBox(height: 8),
                        Text(_amountInText(quote.total)),
                      ],
                    ),
                  );
                  final totalsCol = Column(
                    children: [
                      _TotalRow(label: 'Subtotal', value: _money(quote.subtotal)),
                      const SizedBox(height: 8),
                      _TotalRow(label: 'IVA (16%)', value: _money(quote.tax)),
                      const Divider(height: 24),
                      _TotalRow(label: 'Total M.N.', value: _money(quote.total), isStrong: true),
                    ],
                  );
                  if (isMobile) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        importeBox,
                        const SizedBox(height: 16),
                        totalsCol,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: importeBox),
                      const SizedBox(width: 24),
                      SizedBox(width: 260, child: totalsCol),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value, this.isStrong = false});

  final String label;
  final String value;
  final bool isStrong;

  @override
  Widget build(BuildContext context) {
    final style = isStrong
        ? Theme.of(context).textTheme.titleLarge?.copyWith(color: RemaColors.primaryDark)
        : Theme.of(context).textTheme.bodyMedium;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label, style: style)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            style: style?.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class _ContextField extends StatelessWidget {
  const _ContextField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final display = value.trim().isEmpty ? 'Sin dato' : value.trim();
    return SizedBox(
      width: 210,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(display, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _LevantamientoEntryCard extends StatelessWidget {
  const _LevantamientoEntryCard({required this.entry});

  final SurveyEntryRecord entry;

  @override
  Widget build(BuildContext context) {
    final hasDescription = entry.description.trim().isNotEmpty;
    final hasEvidence = entry.evidencePreviewList.isNotEmpty;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: RemaColors.surfaceLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasDescription ? entry.description : 'Sin descripcion de texto en este registro.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (hasEvidence) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var index = 0; index < entry.evidencePreviewList.length; index++)
                  _EvidenceThumb(
                    imageBytes: entry.evidencePreviewList[index],
                    allImages: entry.evidencePreviewList,
                    initialIndex: index,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _EvidenceThumb extends StatelessWidget {
  const _EvidenceThumb({
    required this.imageBytes,
    required this.allImages,
    required this.initialIndex,
  });

  final Uint8List imageBytes;
  final List<Uint8List> allImages;
  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _openImagePreview(
        context,
        images: allImages,
        initialIndex: initialIndex,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 88,
          height: 88,
          child: Image.memory(imageBytes, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

Future<void> _openImagePreview(
  BuildContext context, {
  required List<Uint8List> images,
  required int initialIndex,
}) {
  final safeInitialIndex = images.isEmpty
      ? 0
      : initialIndex.clamp(0, images.length - 1);
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (context) => _EvidencePreviewDialog(
      images: images,
      initialIndex: safeInitialIndex,
    ),
  );
}

class _EvidencePreviewDialog extends StatefulWidget {
  const _EvidencePreviewDialog({
    required this.images,
    required this.initialIndex,
  });

  final List<Uint8List> images;
  final int initialIndex;

  @override
  State<_EvidencePreviewDialog> createState() => _EvidencePreviewDialogState();
}

class _EvidencePreviewDialogState extends State<_EvidencePreviewDialog> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    if (index < 0 || index >= widget.images.length) {
      return;
    }
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.shortestSide < 700;
    final hasMultiple = widget.images.length > 1;

    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Stack(
          children: [
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(color: Colors.transparent),
            ),
            Center(
              child: GestureDetector(
                onTap: () {},
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: widget.images.length,
                  onPageChanged: (index) {
                    setState(() => _currentIndex = index);
                  },
                  itemBuilder: (_, index) {
                    return InteractiveViewer(
                      minScale: 0.8,
                      maxScale: 4.0,
                      child: Image.memory(widget.images[index], fit: BoxFit.contain),
                    );
                  },
                ),
              ),
            ),
            if (isMobile)
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  tooltip: 'Cerrar',
                ),
              ),
            if (!isMobile && hasMultiple) ...[
              Positioned(
                left: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton(
                    onPressed: _currentIndex > 0 ? () => _goTo(_currentIndex - 1) : null,
                    icon: const Icon(Icons.chevron_left, size: 42, color: Colors.white),
                    tooltip: 'Anterior',
                  ),
                ),
              ),
              Positioned(
                right: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton(
                    onPressed: _currentIndex < widget.images.length - 1
                        ? () => _goTo(_currentIndex + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right, size: 42, color: Colors.white),
                    tooltip: 'Siguiente',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _money(double value) {
  final formatter = NumberFormat.currency(symbol: r'$', decimalDigits: 2, locale: 'en_US');
  return formatter.format(value);
}

String _date(DateTime value) => DateFormat('dd/MM/yyyy').format(value);

pw.Widget _pdfCell(String value, {bool isHeader = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(6),
    child: pw.Text(
      value,
      style: pw.TextStyle(
        fontSize: isHeader ? 9 : 8,
        fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
      softWrap: true,
    ),
  );
}

pw.Widget _pdfHeaderField(String label, String value) {
  final safe = value.trim().isEmpty ? '-' : value.trim();
  return pw.RichText(
    text: pw.TextSpan(
      children: [
        pw.TextSpan(
          text: '$label: ',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5),
        ),
        pw.TextSpan(
          text: safe,
          style: const pw.TextStyle(fontSize: 8.5),
        ),
      ],
    ),
  );
}

pw.Widget _pdfTotalRow(String label, String value, {bool strong = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: pw.TextStyle(fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal)),
        pw.Text(value, style: pw.TextStyle(fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal)),
      ],
    ),
  );
}

String _amountInText(double value) {
  return 'Monto total: ${_money(value)} M.N.';
}
