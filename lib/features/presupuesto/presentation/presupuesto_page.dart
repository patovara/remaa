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
      subtitle: 'Vista formal de cotización ajustada para revisión y envío.',
      trailing: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (currentQuote != null && currentQuote.isDraft)
            Tooltip(
              message: 'Marcar cotización como concluida',
              child: FilledButton.icon(
                onPressed: () => _changeQuoteStatus(
                  context,
                  ref,
                  currentQuote,
                  QuoteStatus.concluded,
                ),
                icon: const Icon(Icons.task_alt_outlined),
                label: const Text('Concluir'),
              ),
            ),
          if (currentQuote != null && currentQuote.isConcluded)
            Tooltip(
              message: 'Reabrir cotización como borrador',
              child: OutlinedButton.icon(
                onPressed: () => _changeQuoteStatus(
                  context,
                  ref,
                  currentQuote,
                  QuoteStatus.draft,
                ),
                icon: const Icon(Icons.undo),
                label: const Text('Reabrir'),
              ),
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
            tooltip: 'Detalles del proyecto',
          ),
          IconButton(
            onPressed: currentQuote != null && currentItems != null
                ? () => _printQuote(context, ref: ref, quote: currentQuote, items: currentItems)
                : null,
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Imprimir cotización',
          ),
          IconButton(
            onPressed: currentQuote != null && currentItems != null
                ? () => _downloadQuote(context, ref: ref, quote: currentQuote, items: currentItems)
                : null,
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Descargar cotización',
          ),
          IconButton(
            onPressed: currentQuote != null && currentItems != null
                ? () => _shareQuote(context, ref: ref, quote: currentQuote, items: currentItems)
                : null,
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Compartir cotización',
          ),
        ],
      ),
      child: quotesState.when(
        data: (quotes) {
          final quote = _findQuote(quotes, quoteId);
          if (quote == null) {
            return const RemaPanel(child: Text('No se encontró la cotización solicitada.'));
          }

          return itemsState.when(
            data: (items) => _BudgetView(
              quote: quote,
              items: items,
              canEditItems: quote.canEditItems,
              contextState: ref.watch(quoteContextProvider(quote.projectId)),
              usdRateState: ref.watch(quoteUsdRateProvider),
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
              onDeleteItem: (item) => _confirmDeleteItem(context, ref, quote, item),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => RemaPanel(
              child: Column(
                children: [
                  const Text('No se pudieron cargar los conceptos de la cotización.'),
                  const SizedBox(height: 8),
                  Text(error.toString()),
                ],
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => RemaPanel(
          child: Text('No se pudo cargar la cotización: $error'),
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
      final currentItems = await ref.read(quoteItemsProvider(quote.id).future);

      await ref.read(quotesProvider.notifier).updateStatus(
            quoteId: quote.id,
            status: nextStatus,
          );

      final updatedQuote = _findQuote(
            ref.read(quotesProvider).valueOrNull ?? const <QuoteRecord>[],
            quote.id,
          ) ??
          quote.copyWith(status: nextStatus);

      // Al concluir, generar PDF y subirlo automáticamente como approval_pdf
      if (nextStatus == QuoteStatus.concluded && currentItems.isNotEmpty) {
        try {
          final pdfBytes = await _buildQuotePdf(
            ref: ref,
            quote: updatedQuote,
            items: currentItems,
            freezeUsdSnapshot: true,
          );
          final fileName =
              'cotizacion_${_sanitizeFolioForFileName(updatedQuote.quoteNumber)}_${DateTime.now().millisecondsSinceEpoch}.pdf';
          await ref.read(quotesProvider.notifier).attachApprovalPdf(
                quoteId: updatedQuote.id,
                bytes: pdfBytes,
                fileName: fileName,
              );
        } catch (_) {
          // No bloquea el flujo si el PDF falla
        }
      }

      if (!context.mounted) {
        return;
      }
      final message = switch (nextStatus) {
        QuoteStatus.concluded => 'Cotización concluida.',
        QuoteStatus.draft => 'Cotización reabierta para edición.',
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
      showRemaMessage(context, 'Catálogo no disponible aún.');
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
      showRemaMessage(context, 'Concepto guardado en cotización.');
    }
  }

  Future<void> _confirmDeleteItem(
    BuildContext context,
    WidgetRef ref,
    QuoteRecord quote,
    QuoteItemRecord item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar concepto'),
        content: Text(
          'Se eliminará este concepto de la cotización:\n\n${item.concept}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    await ref.read(quoteItemsProvider(quote.id).notifier).remove(item.id);
    if (context.mounted) {
      showRemaMessage(context, 'Concepto eliminado de la cotización.');
    }
  }

  Future<void> _printQuote(
    BuildContext context, {
    required WidgetRef ref,
    required QuoteRecord quote,
    required List<QuoteItemRecord> items,
  }) async {
    final bytes = await _buildQuotePdf(
      ref: ref,
      quote: quote,
      items: items,
      freezeUsdSnapshot: false,
    );
    final folio = _displayQuoteFolio(quote.quoteNumber);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      format: PdfPageFormat.letter,
      name: 'cotizacion_${_sanitizeFolioForFileName(folio)}.pdf',
    );
  }

  Future<void> _downloadQuote(
    BuildContext context, {
    required WidgetRef ref,
    required QuoteRecord quote,
    required List<QuoteItemRecord> items,
  }) async {
    final bytes = await _buildQuotePdf(
      ref: ref,
      quote: quote,
      items: items,
      freezeUsdSnapshot: false,
    );
    final folio = _displayQuoteFolio(quote.quoteNumber);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'cotizacion_${_sanitizeFolioForFileName(folio)}.pdf',
    );
    if (context.mounted) {
      showRemaMessage(context, 'Cotización lista para descarga.');
    }
  }

  Future<void> _shareQuote(
    BuildContext context, {
    required WidgetRef ref,
    required QuoteRecord quote,
    required List<QuoteItemRecord> items,
  }) async {
    final bytes = await _buildQuotePdf(
      ref: ref,
      quote: quote,
      items: items,
      freezeUsdSnapshot: false,
    );
    final folio = _displayQuoteFolio(quote.quoteNumber);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'cotizacion_${_sanitizeFolioForFileName(folio)}.pdf',
    );
    if (context.mounted) {
      showRemaMessage(context, 'Cotización lista para compartir.');
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
    required bool freezeUsdSnapshot,
  }) async {
    final currencyState = await _resolveQuoteCurrency(
      ref: ref,
      quote: quote,
      freezeSnapshot: freezeUsdSnapshot,
    );
    final quoteForPdf = currencyState.quote;
    final usdRate = currencyState.rate?.rate ?? quoteForPdf.finalExchangeRate;
    final pdf = pw.Document();
    final logo = await _loadHeaderLogo();
    final watermark = await _loadWatermarkImage();
    final money = NumberFormat.currency(symbol: r'$', decimalDigits: 2, locale: 'en_US');
    final dateLabel = quoteForPdf.validUntil != null ? _date(quoteForPdf.validUntil!) : _date(DateTime.now());
    final quoteContext =
      await ref.read(quotesProvider.notifier).fetchQuoteContext(projectId: quoteForPdf.projectId);
    final catalog = await ref.read(conceptsCatalogProvider.future);
    final activeLevantamiento = ref.read(activeLevantamientoProvider);
    final persistedEntries = await ref
        .read(projectSurveyEntriesProvider(quote.projectId).future)
        .catchError((_) => const <SurveyEntryRecord>[]);
    final activeMatchesQuote =
        activeLevantamiento != null && activeLevantamiento.quoteId == quoteForPdf.id;
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
      quoteForPdf.universeId,
      [for (final item in catalog.universes) (item.id, item.name)],
    );
    final projectTypeLabel = _labelById(
      quoteForPdf.projectTypeId,
      [for (final item in catalog.projectTypes) (item.id, item.name)],
    );
    final evidenceEntries = mergedEntries
        .where((entry) => entry.evidencePreviewList.any((bytes) => bytes.isNotEmpty))
        .toList();
    if (evidenceEntries.isEmpty && activeLevantamiento?.quoteId == quoteForPdf.id) {
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

    final parsedItems = [
      for (final item in items)
        (item: item, concept: _splitConceptForPdf(item.concept)),
    ];
    final includeClauses = <String>[];
    for (final parsed in parsedItems) {
      final include = parsed.concept.includeText;
      if (include == null) {
        continue;
      }
      if (!includeClauses.contains(include)) {
        includeClauses.add(include);
      }
    }
    final includeSummary = includeClauses.isEmpty
        ? null
        : includeClauses.length == 1
            ? 'INCLUYE: ${includeClauses.first}'
            : 'INCLUYE:\n${includeClauses.map((entry) => '• $entry').join('\n')}';

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.letter,
          margin: const pw.EdgeInsets.all(28),
          buildBackground: watermark != null
              ? (_) => pw.Positioned.fill(
                    child: pw.Center(
                      child: pw.Opacity(
                        opacity: 0.1, //se ajusto la opacidad para que la marca de agua sea más sutil
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
              pw.Expanded(
                child: pw.Column(
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
                    pw.SizedBox(height: 6),
                    pw.Text(
                      CompanyProfile.legalName,
                      style: const pw.TextStyle(fontSize: 8.6),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'TEL: ${CompanyProfile.phone}',
                      style: const pw.TextStyle(fontSize: 8.6),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('COTIZACIÓN', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                  pw.Text('Folio: ${_displayQuoteFolio(quoteForPdf.quoteNumber)}'),
                  pw.Text('Fecha: $dateLabel'),
                  pw.Text('Estado: ${quoteForPdf.status.toUpperCase()}'),
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
                    pw.Expanded(child: _pdfHeaderField('Dirección', quoteContext.address)),
                    pw.SizedBox(width: 8),
                    pw.Expanded(child: _pdfHeaderField('Ubicación', quoteContext.location)),
                  ],
                ),
                pw.SizedBox(height: 6),
                pw.Row(
                  children: [
                    pw.Expanded(child: _pdfHeaderField('Universo', universeLabel)),
                    pw.SizedBox(width: 8),
                    pw.Expanded(child: _pdfHeaderField('Tipo de remodelación', projectTypeLabel)),
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
                    _pdfCell(
                      parsedItems
                          .firstWhere((parsed) => parsed.item.id == item.id)
                          .concept
                          .mainText,
                    ),
                    _pdfCell(item.unit),
                    _pdfCell(item.quantity.toStringAsFixed(2)),
                    _pdfCurrencyCell(
                      primary: money.format(item.unitPrice),
                      secondary: usdRate == null ? null : _usdFromRate(item.unitPrice, usdRate),
                    ),
                    _pdfCurrencyCell(
                      primary: money.format(item.lineTotal),
                      secondary: usdRate == null ? null : _usdFromRate(item.lineTotal, usdRate),
                    ),
                  ],
                ),
              if (includeSummary != null)
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    _pdfCell(includeSummary),
                    _pdfCell(''),
                    _pdfCell(''),
                    _pdfCell(''),
                    _pdfCell(''),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.SizedBox(
              width: 240,
              child: _pdfTotalsTable(
                subtotal: money.format(quoteForPdf.subtotal),
                tax: money.format(quoteForPdf.tax),
                total: money.format(quoteForPdf.total),
                subtotalUsd: quoteForPdf.finalSubtotalUsd != null
                    ? _usdRoundedLabel(quoteForPdf.finalSubtotalUsd!)
                    : (usdRate == null ? null : _usdFromRate(quoteForPdf.subtotal, usdRate)),
                taxUsd: quoteForPdf.finalTaxUsd != null
                    ? _usdRoundedLabel(quoteForPdf.finalTaxUsd!)
                    : (usdRate == null ? null : _usdFromRate(quoteForPdf.tax, usdRate)),
                totalUsd: quoteForPdf.finalTotalUsd != null
                    ? _usdRoundedLabel(quoteForPdf.finalTotalUsd!)
                    : (usdRate == null ? null : _usdFromRate(quoteForPdf.total, usdRate)),
              ),
            ),
          ),
          pw.SizedBox(height: 12),
          _pdfGeneralConceptsAndBankData(),
        ],
      ),
    );

    return Uint8List.fromList(await pdf.save());
  }

  Future<({QuoteRecord quote, QuoteCurrencyRate? rate})> _resolveQuoteCurrency({
    required WidgetRef ref,
    required QuoteRecord quote,
    required bool freezeSnapshot,
  }) async {
    if (quote.hasFinalExchangeSnapshot) {
      return (
        quote: quote,
        rate: QuoteCurrencyRate(
          base: quote.finalExchangeBase ?? 'MXN',
          target: quote.finalExchangeTarget ?? 'USD',
          rate: quote.finalExchangeRate!,
          provider: quote.finalExchangeProvider ?? 'snapshot',
          fetchedAt: quote.finalExchangeCapturedAt ?? DateTime.now(),
          isFallback: false,
        ),
      );
    }

    try {
      final rate = await ref.read(quotesProvider.notifier).fetchUsdRate();
      if (!freezeSnapshot) {
        return (quote: quote, rate: rate);
      }

      final updated = await ref.read(quotesProvider.notifier).persistFinalUsdSnapshot(
            quoteId: quote.id,
            rate: rate,
          );
      return (quote: updated, rate: rate);
    } catch (_) {
      return (quote: quote, rate: null);
    }
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
          'Registro fotográfico',
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
//Aquí están los datos generales y bancarios que se muestran al final del PDF, debajo de los totales. Se mantiene un diseño de dos columnas, con los conceptos generales a la izquierda y los datos bancarios a la derecha.
pw.Widget _pdfGeneralConceptsAndBankData() {
  final leftStyle = pw.TextStyle(fontSize: 5, color: PdfColors.grey800);
  final rightStyle = pw.TextStyle(fontSize: 5.5, color: PdfColors.black);

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        flex: 3,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'CONCEPTOS GENERALES:',
              style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text('1.- ESTE ES UN PRESUPUESTO BASADO EN LA INFORMACIÓN QUE SE NOS PROPORCIONO.', style: leftStyle),
            pw.SizedBox(height: 2),
            pw.Text('2.- PRECIOS SUJETOS A CAMBIOS SIN PREVIO AVISO.', style: leftStyle),
            pw.SizedBox(height: 2),
            pw.Text('3.- CONDICIONES DE PAGO ( costos + iva )', style: leftStyle),
            pw.Text('    ( DE ACUERDO A LOS ACUERDOS EN CONTRATO )', style: leftStyle),
            pw.SizedBox(height: 2),
            pw.Text('4.- TIEMPO DE ENTREGA', style: leftStyle),
            pw.Text('    ( CALENDARIO DE OBRA POR DISPOSICIÓN DE ÁREAS )', style: leftStyle),
            pw.SizedBox(height: 2),
            pw.Text('5.- FORMAS DE PAGO', style: leftStyle),
            pw.Text('    ( TRANSFERENCIA ELECTRONICA ) + ( EFECTIVO )', style: leftStyle),
            pw.SizedBox(height: 2),
            pw.Text('6.- VIGENCIA DE COSTOS', style: leftStyle),
            pw.Text('    ( 5 DÍAS )', style: leftStyle),
          ],
        ),
      ),
      pw.SizedBox(width: 24),
      pw.Expanded(
        flex: 2,
        child: pw.Align(
          alignment: pw.Alignment.topRight,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'DATOS BANCARIOS FACTURACION',
                style: pw.TextStyle(
                  fontSize: 7,
                  fontWeight: pw.FontWeight.bold,
                  decoration: pw.TextDecoration.underline,
                ),
                textAlign: pw.TextAlign.right,
              ),
              pw.SizedBox(height: 4),
              pw.Text('SOLUCIONES INTEGRALES SUSTENTABLES', style: rightStyle, textAlign: pw.TextAlign.right),
              pw.Text('INTELIGENTES Y DINAMICAS REMA, S.A.S. DE C.V.', style: rightStyle, textAlign: pw.TextAlign.right),
              pw.SizedBox(height: 10),
              pw.Text('SANTANDER', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
              pw.Text('65-50868153-1', style: rightStyle),
              pw.Text('014691 655086815 315', style: rightStyle),
            ],
          ),
        ),
      ),
    ],
  );
}

class _BudgetView extends ConsumerStatefulWidget {
  const _BudgetView({
    required this.quote,
    required this.items,
    required this.canEditItems,
    required this.contextState,
    required this.usdRateState,
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
  final AsyncValue<QuoteCurrencyRate> usdRateState;
  final String universeLabel;
  final String projectTypeLabel;
  final VoidCallback onAddItem;
  final ValueChanged<QuoteItemRecord> onEditItem;
  final ValueChanged<QuoteItemRecord> onDeleteItem;

  @override
  ConsumerState<_BudgetView> createState() => _BudgetViewState();
}

class _BudgetViewState extends ConsumerState<_BudgetView> {
  late final ScrollController _tableScrollController;

  @override
  void initState() {
    super.initState();
    _tableScrollController = ScrollController();
  }

  @override
  void dispose() {
    _tableScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final estimatedRate = widget.quote.hasFinalExchangeSnapshot
      ? widget.quote.finalExchangeRate
      : widget.usdRateState.valueOrNull?.rate;
    final subtotalUsd = widget.quote.finalSubtotalUsd != null
      ? _usdRoundedLabel(widget.quote.finalSubtotalUsd!)
      : (estimatedRate == null ? null : _usdFromRate(widget.quote.subtotal, estimatedRate));
    final taxUsd = widget.quote.finalTaxUsd != null
      ? _usdRoundedLabel(widget.quote.finalTaxUsd!)
      : (estimatedRate == null ? null : _usdFromRate(widget.quote.tax, estimatedRate));
    final totalUsd = widget.quote.finalTotalUsd != null
      ? _usdRoundedLabel(widget.quote.finalTotalUsd!)
      : (estimatedRate == null ? null : _usdFromRate(widget.quote.total, estimatedRate));

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
                        'COTIZACIÓN',
                        style: Theme.of(context).textTheme.headlineLarge?.copyWith(color: RemaColors.primaryDark),
                      ),
                      const SizedBox(height: 6),
                      Text('FOLIO: ${_displayQuoteFolio(widget.quote.quoteNumber)}'),
                      Text('FECHA: ${_date(widget.quote.validUntil ?? DateTime.now())}'),
                      Text('ESTADO: ${widget.quote.status.toUpperCase()}'),
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
              widget.contextState.when(
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
                      _ContextField(label: 'Dirección', value: context.address),
                      _ContextField(label: 'Ubicación', value: context.location),
                      _ContextField(label: 'Universo', value: widget.universeLabel),
                      _ContextField(label: 'Tipo de remodelación', value: widget.projectTypeLabel),
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
                    onPressed: widget.canEditItems ? widget.onAddItem : null,
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar concepto'),
                  ),
                  if (!widget.canEditItems) ...[
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
              LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < 600;
                  final conceptColumnWidth = isMobile ? 520.0 : (constraints.maxWidth * 0.42).clamp(340.0, 520.0);
                  final dataTable = DataTable(
                    dataRowMinHeight: 56,
                    dataRowMaxHeight: 220,
                    columnSpacing: isMobile ? 20 : 12,
                    columns: const [
                      DataColumn(label: Text('Concepto / Descripcion')),
                      DataColumn(label: Text('Unidad')),
                      DataColumn(label: Text('Cant.')),
                      DataColumn(label: Text('P.U.')),
                      DataColumn(label: Text('Importe')),
                      DataColumn(label: Text('Acciones')),
                    ],
                    rows: [
                      for (final item in widget.items)
                        DataRow(cells: [
                          DataCell(
                            SizedBox(
                              width: conceptColumnWidth,
                              child: Text(
                                _cleanConceptText(item.concept),
                                softWrap: true,
                              ),
                            ),
                          ),
                          DataCell(Text(item.unit)),
                          DataCell(Text(item.quantity.toStringAsFixed(2))),
                          DataCell(
                            _MoneyWithUsd(
                              mxn: _money(item.unitPrice),
                              usd: estimatedRate == null ? null : _usdFromRate(item.unitPrice, estimatedRate),
                            ),
                          ),
                          DataCell(
                            _MoneyWithUsd(
                              mxn: _money(item.lineTotal),
                              usd: estimatedRate == null ? null : _usdFromRate(item.lineTotal, estimatedRate),
                            ),
                          ),
                          DataCell(
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: widget.canEditItems ? () => widget.onEditItem(item) : null,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: widget.canEditItems ? () => widget.onDeleteItem(item) : null,
                                ),
                              ],
                            ),
                          ),
                        ]),
                    ],
                  );

                  final table = isMobile
                      ? SingleChildScrollView(
                          controller: _tableScrollController,
                          scrollDirection: Axis.horizontal,
                          child: dataTable,
                        )
                      : SizedBox(width: double.infinity, child: dataTable);

                  if (isMobile) {
                    return table;
                  }

                  return table;
                },
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
                        Text(_amountInText(widget.quote.total)),
                      ],
                    ),
                  );
                  final totalsCol = Column(
                    children: [
                      _TotalRow(
                        label: 'Subtotal',
                        value: _money(widget.quote.subtotal),
                        secondaryValue: subtotalUsd,
                      ),
                      const SizedBox(height: 8),
                      _TotalRow(
                        label: 'IVA (16%)',
                        value: _money(widget.quote.tax),
                        secondaryValue: taxUsd,
                      ),
                      const Divider(height: 24),
                      _TotalRow(
                        label: 'Total M.N.',
                        value: _money(widget.quote.total),
                        secondaryValue: totalUsd,
                        isStrong: true,
                      ),
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
              const SizedBox(height: 20),
              const _GeneralConceptsAndBankDataSection(),
            ],
          ),
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.secondaryValue,
    this.isStrong = false,
  });

  final String label;
  final String value;
  final String? secondaryValue;
  final bool isStrong;

  @override
  Widget build(BuildContext context) {
    final style = isStrong
        ? Theme.of(context).textTheme.titleLarge?.copyWith(color: RemaColors.primaryDark)
        : Theme.of(context).textTheme.bodyMedium;
    final secondaryStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: RemaColors.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          fontSize: isStrong ? 13 : 12,
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label, style: style)),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: style?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.right,
              ),
              if (secondaryValue != null) ...[
                const SizedBox(height: 2),
                Text(secondaryValue!, style: secondaryStyle),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MoneyWithUsd extends StatelessWidget {
  const _MoneyWithUsd({required this.mxn, this.usd});

  final String mxn;
  final String? usd;

  @override
  Widget build(BuildContext context) {
    final usdStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: RemaColors.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(mxn),
        if (usd != null) ...[
          const SizedBox(height: 2),
          Text(usd!, style: usdStyle),
        ],
      ],
    );
  }
}

class _GeneralConceptsAndBankDataSection extends StatelessWidget {
  const _GeneralConceptsAndBankDataSection();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 800;

        final concepts = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CONCEPTOS GENERALES:',
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text('1.- ESTE ES UN PRESUPUESTO BASADO EN LA INFORMACIÓN QUE SE NOS PROPORCIONO.', style: textTheme.bodyMedium),
            const SizedBox(height: 2),
            Text('2.- PRECIOS SUJETOS A CAMBIOS SIN PREVIO AVISO.', style: textTheme.bodyMedium),
            const SizedBox(height: 2),
            Text('3.- CONDICIONES DE PAGO ( costos + iva )', style: textTheme.bodyMedium),
            Text('( DE ACUERDO A LOS ACUERDOS EN CONTRATO )', style: textTheme.bodyMedium),
            const SizedBox(height: 2),
            Text('4.- TIEMPO DE ENTREGA', style: textTheme.bodyMedium),
            Text('( CALENDARIO DE OBRA POR DISPOSICIÓN DE ÁREAS )', style: textTheme.bodyMedium),
            const SizedBox(height: 2),
            Text('5.- FORMAS DE PAGO', style: textTheme.bodyMedium),
            Text('( TRANSFERENCIA ELECTRONICA ) + ( EFECTIVO )', style: textTheme.bodyMedium),
            const SizedBox(height: 2),
            Text('6.- VIGENCIA DE COSTOS', style: textTheme.bodyMedium),
            Text('( 5 DÍAS )', style: textTheme.bodyMedium),
          ],
        );

        final bank = Column(
          crossAxisAlignment: isMobile ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            Text(
              'DATOS BANCARIOS FACTURACIÓN',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                decoration: TextDecoration.underline,
              ),
              textAlign: isMobile ? TextAlign.left : TextAlign.right,
            ),
            const SizedBox(height: 8),
            Text(
              'SOLUCIONES INTEGRALES SUSTENTABLES\nINTELIGENTES Y DINAMICAS REMA, S.A.S. DE C.V.',
              style: textTheme.bodyMedium,
              textAlign: isMobile ? TextAlign.left : TextAlign.right,
            ),
            const SizedBox(height: 10),
            Text(
              'SANTANDER',
              style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              textAlign: isMobile ? TextAlign.left : TextAlign.right,
            ),
            Text('65-50868153-1', style: textTheme.bodyMedium),
            Text('014691 655086815 315', style: textTheme.bodyMedium),
          ],
        );

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: RemaColors.surfaceLow,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: RemaColors.outlineVariant.withValues(alpha: 0.35)),
          ),
          child: isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    concepts,
                    const SizedBox(height: 18),
                    bank,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: concepts),
                    const SizedBox(width: 24),
                    Expanded(flex: 2, child: bank),
                  ],
                ),
        );
      },
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
            hasDescription ? entry.description : 'Sin descripción de texto en este registro.',
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

String _displayQuoteFolio(String value) {
  final normalized = value.trim().toUpperCase();
  if (normalized.isEmpty) {
    return value.trim();
  }
  String? structured;
  for (final match in RegExp(r'RM-[A-Z]{3}[0-9]{2,}-[A-Z]{4}-PRJ[0-9]{4,}').allMatches(normalized)) {
    structured = match.group(0);
  }
  return structured ?? value.trim();
}

String _sanitizeFolioForFileName(String folio) {
  final cleaned = folio.trim().replaceAll(RegExp(r'[^A-Za-z0-9-]'), '_');
  return cleaned.isEmpty ? 'sin_folio' : cleaned;
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
    barrierDismissible: true,
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

    // Material(transparency) en lugar de Scaffold para que el barrier de showDialog
    // sea visible y clicable. Scaffold llenaba la pantalla con color opaco bloqueando
    // el dismiss-on-outside y los eventos del mouse para InteractiveViewer.
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).pop(),
          child: Stack(
            children: [
              Positioned.fill(
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
                      child: Center(
                        child: Image.memory(widget.images[index], fit: BoxFit.contain),
                      ),
                    );
                  },
                ),
              ),
              // Botón X siempre visible (mobile y desktop)
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black45,
                    shape: const CircleBorder(),
                  ),
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
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black45,
                        shape: const CircleBorder(),
                      ),
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
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black45,
                        shape: const CircleBorder(),
                      ),
                      tooltip: 'Siguiente',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _money(double value) {
  final formatter = NumberFormat.currency(symbol: r'$', decimalDigits: 2, locale: 'en_US');
  return formatter.format(value);
}

String _usdFromRate(double valueMxn, double rate) {
  final usd = (valueMxn * rate).ceil();
  return '$usd USD';
}

String _usdRoundedLabel(double value) {
  return '${value.ceil()} USD';
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

pw.Widget _pdfCurrencyCell({
  required String primary,
  String? secondary,
}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(6),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(
          primary,
          style: const pw.TextStyle(fontSize: 8),
          textAlign: pw.TextAlign.right,
        ),
        if (secondary != null)
          pw.Text(
            secondary,
            style: const pw.TextStyle(fontSize: 6.6, color: PdfColors.grey700),
            textAlign: pw.TextAlign.right,
          ),
      ],
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

pw.Widget _pdfTotalsTable({
  required String subtotal,
  required String tax,
  required String total,
  String? subtotalUsd,
  String? taxUsd,
  String? totalUsd,
}) {
  return pw.Table(
    border: pw.TableBorder.all(width: 0.6, color: PdfColors.black),
    columnWidths: {
      0: const pw.FlexColumnWidth(1.25),
      1: const pw.FlexColumnWidth(1),
    },
    children: [
      _pdfTotalsTableRow(label: 'Subtotal', value: subtotal, secondaryValue: subtotalUsd),
      _pdfTotalsTableRow(label: 'IVA (16%)', value: tax, secondaryValue: taxUsd),
      _pdfTotalsTableRow(label: 'Total', value: total, secondaryValue: totalUsd, strong: true),
    ],
  );
}

pw.TableRow _pdfTotalsTableRow({
  required String label,
  required String value,
  String? secondaryValue,
  bool strong = false,
}) {
  final textStyle = pw.TextStyle(
    fontSize: 9,
    fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
  );
  final secondaryStyle = pw.TextStyle(
    fontSize: strong ? 8.2 : 7.8,
    color: PdfColors.grey700,
    fontWeight: pw.FontWeight.bold,
  );
  final rowDecoration = strong
      ? const pw.BoxDecoration(color: PdfColors.grey300)
      : const pw.BoxDecoration();
  return pw.TableRow(
    decoration: rowDecoration,
    children: [
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: pw.Text(label, style: textStyle),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(value, style: textStyle),
            if (secondaryValue != null) pw.Text(secondaryValue, style: secondaryStyle),
          ],
        ),
      ),
    ],
  );
}

class _PdfConceptSplit {
  const _PdfConceptSplit({required this.mainText, this.includeText});

  final String mainText;
  final String? includeText;
}

_PdfConceptSplit _splitConceptForPdf(String rawConcept) {
  final normalized = _cleanConceptText(rawConcept);
  if (normalized.isEmpty) {
    return const _PdfConceptSplit(mainText: '-');
  }

  final upper = normalized.toUpperCase();
  final includeIndex = upper.indexOf('INCLUYE');
  if (includeIndex < 0) {
    return _PdfConceptSplit(mainText: normalized);
  }

  final mainPart = normalized.substring(0, includeIndex).trim();
  var includePart = normalized.substring(includeIndex).trim();
  includePart = includePart.replaceFirst(
    RegExp(r'^INCLUYE\s*:?\s*', caseSensitive: false),
    '',
  );
  includePart = includePart.replaceAll(RegExp(r'\s+'), ' ').trim();

  return _PdfConceptSplit(
    mainText: mainPart.isEmpty ? '-' : mainPart,
    includeText: includePart.isEmpty ? null : includePart,
  );
}

String _cleanConceptText(String rawConcept) {
  var text = rawConcept.replaceAll('\r\n', '\n').trim();
  if (text.isEmpty) {
    return '-';
  }

  // Remove parenthetical fragments already represented in structured columns.
  text = text.replaceAll(RegExp(r'\([^\)]*\)'), ' ');

  // Remove explicit unit fragments because unit is shown in its own table column.
  text = text.replaceAll(RegExp(r'\bunidad\s*:\s*[^\n\.,;]+[\.,;]?', caseSensitive: false), ' ');

  // Normalize spacing while preserving line breaks.
  text = text
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((line) => line.isNotEmpty)
      .join('\n');

  return text.isEmpty ? '-' : text;
}

String _amountInText(double value) {
  return 'Monto total: ${_money(value)} M.N.';
}
