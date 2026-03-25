import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'quote_item_editor_dialog.dart';

class PresupuestoPage extends ConsumerWidget {
  const PresupuestoPage({super.key, required this.quoteId});

  final String quoteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quotesState = ref.watch(quotesProvider);
    final itemsState = ref.watch(quoteItemsProvider(quoteId));
    final catalogState = ref.watch(conceptsCatalogProvider);
    final currentQuote = _findQuote(quotesState.valueOrNull ?? const [], quoteId);
    final currentItems = itemsState.valueOrNull;

    return PageFrame(
      title: 'Presupuesto',
      subtitle: 'Vista formal de cotizacion ajustada para revision y envio.',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: currentQuote != null && currentItems != null
                ? () => _printQuote(context, quote: currentQuote, items: currentItems)
                : null,
            icon: const Icon(Icons.print_outlined),
          ),
          IconButton(
            onPressed: currentQuote != null && currentItems != null
                ? () => _downloadQuote(context, quote: currentQuote, items: currentItems)
                : null,
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            onPressed: currentQuote != null && currentItems != null
                ? () => _shareQuote(context, quote: currentQuote, items: currentItems)
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

  QuoteRecord? _findQuote(List<QuoteRecord> quotes, String id) {
    for (final quote in quotes) {
      if (quote.id == id) {
        return quote;
      }
    }
    return null;
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
    required QuoteRecord quote,
    required List<QuoteItemRecord> items,
  }) async {
    final bytes = await _buildQuotePdf(quote: quote, items: items);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      format: PdfPageFormat.letter,
      name: 'cotizacion_${quote.quoteNumber}.pdf',
    );
  }

  Future<void> _downloadQuote(
    BuildContext context, {
    required QuoteRecord quote,
    required List<QuoteItemRecord> items,
  }) async {
    final bytes = await _buildQuotePdf(quote: quote, items: items);
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
    required QuoteRecord quote,
    required List<QuoteItemRecord> items,
  }) async {
    final bytes = await _buildQuotePdf(quote: quote, items: items);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'cotizacion_${quote.quoteNumber}.pdf',
    );
    if (context.mounted) {
      showRemaMessage(context, 'Cotizacion lista para compartir.');
    }
  }

  Future<Uint8List> _buildQuotePdf({
    required QuoteRecord quote,
    required List<QuoteItemRecord> items,
  }) async {
    final pdf = pw.Document();
    final money = NumberFormat.currency(symbol: r'$', decimalDigits: 2, locale: 'en_US');
    final dateLabel = quote.validUntil != null ? _date(quote.validUntil!) : _date(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      CompanyProfile.brandName,
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(CompanyProfile.legalName, style: const pw.TextStyle(fontSize: 9)),
                    pw.SizedBox(height: 4),
                    pw.Text('TEL: ${CompanyProfile.phone}', style: const pw.TextStyle(fontSize: 9)),
                  ],
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
}

class _BudgetView extends StatelessWidget {
  const _BudgetView({
    required this.quote,
    required this.items,
    required this.onAddItem,
    required this.onEditItem,
    required this.onDeleteItem,
  });

  final QuoteRecord quote;
  final List<QuoteItemRecord> items;
  final VoidCallback onAddItem;
  final ValueChanged<QuoteItemRecord> onEditItem;
  final ValueChanged<QuoteItemRecord> onDeleteItem;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: RemaPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Image.asset('assets/images/logo_remaa.png', height: 56),
                        const SizedBox(height: 16),
                        Text(CompanyProfile.brandName, style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text(CompanyProfile.legalName),
                        Text('TEL: ${CompanyProfile.phone}'),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
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
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: onAddItem,
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar concepto'),
                  ),
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
                                onPressed: () => onEditItem(item),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => onDeleteItem(item),
                              ),
                            ],
                          ),
                        ),
                      ]),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
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
                    ),
                  ),
                  const SizedBox(width: 24),
                  SizedBox(
                    width: 260,
                    child: Column(
                      children: [
                        _TotalRow(label: 'Subtotal', value: _money(quote.subtotal)),
                        const SizedBox(height: 8),
                        _TotalRow(label: 'IVA (16%)', value: _money(quote.tax)),
                        const Divider(height: 24),
                        _TotalRow(label: 'Total M.N.', value: _money(quote.total), isStrong: true),
                      ],
                    ),
                  ),
                ],
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
