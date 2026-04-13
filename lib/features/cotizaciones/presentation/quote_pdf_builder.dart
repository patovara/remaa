import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/config/company_profile.dart';
import '../domain/quote_models.dart';

/// Genera el PDF de una cotización sin dependencias de WidgetRef.
/// Retorna los bytes del PDF o null si hay error.
Future<Uint8List?> buildQuotePdfBytes({
  required QuoteRecord quote,
  required List<QuoteItemRecord> items,
  required QuoteContextInfo context,
  required List<SurveyEntryRecord> surveyEntries,
  required String universeLabel,
  required String projectTypeLabel,
}) async {
  try {
    final pdf = pw.Document();
    final logo = await _loadAssetImage('assets/images/logo_remaa.png');
    final watermark = await _loadAssetImage('assets/images/marca_agua_remaa.png');
    final money = NumberFormat.currency(symbol: r'$', decimalDigits: 2, locale: 'en_US');
    final dateLabel = quote.validUntil != null ? _formatDate(quote.validUntil!) : _formatDate(DateTime.now());

    // Filter entries with evidence
    final evidenceEntries = surveyEntries
        .where((entry) => entry.evidencePreviewList.any((bytes) => bytes.isNotEmpty))
        .toList();

    // Build items for PDF display
    final parsedItems = [
      for (final item in items)
        (item: item, concept: _splitConceptForPdf(item.concept)),
    ];

    // Collect include clauses
    final includeClauses = <String>[];
    for (final parsed in parsedItems) {
      final include = parsed.concept.includeText;
      if (include == null) continue;
      if (!includeClauses.contains(include)) {
        includeClauses.add(include);
      }
    }
    final includeSummary = includeClauses.isEmpty
        ? null
        : includeClauses.length == 1
            ? 'INCLUYE: ${includeClauses.first}'
            : 'INCLUYE:\n${includeClauses.map((entry) => '• $entry').join('\n')}';

    // Build PDF
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
        build: (pdfContext) => [
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
                    pw.Expanded(child: _pdfHeaderField('Proyecto', context.projectName)),
                    pw.SizedBox(width: 8),
                    pw.Expanded(child: _pdfHeaderField('Cliente', context.clientName)),
                  ],
                ),
                pw.SizedBox(height: 6),
                pw.Row(
                  children: [
                    pw.Expanded(child: _pdfHeaderField('Dirección', context.address)),
                    pw.SizedBox(width: 8),
                    pw.Expanded(child: _pdfHeaderField('Ubicación', context.location)),
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
            _buildPdfEvidenceBlocks(entries: evidenceEntries),
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
                    _pdfCell(money.format(item.unitPrice)),
                    _pdfCell(money.format(item.lineTotal)),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Row(
                    children: [
                      pw.Text('SUBTOTAL:', style: const pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(width: 20),
                      pw.SizedBox(
                        width: 100,
                        child: pw.Text(
                          money.format(quote.subtotal),
                          textAlign: pw.TextAlign.right,
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                  pw.Row(
                    children: [
                      pw.Text('IVA (16%):', style: const pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(width: 20),
                      pw.SizedBox(
                        width: 100,
                        child: pw.Text(
                          money.format(quote.tax),
                          textAlign: pw.TextAlign.right,
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                  pw.Divider(thickness: 1),
                  pw.Row(
                    children: [
                      pw.Text('TOTAL:', style: const pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(width: 20),
                      pw.SizedBox(
                        width: 100,
                        child: pw.Text(
                          money.format(quote.total),
                          textAlign: pw.TextAlign.right,
                          style: const pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          _pdfGeneralConceptsAndBankData(),
        ],
      ),
    );

    return Uint8List.fromList(await pdf.save());
  } catch (error) {
    print('Error generando PDF: $error');
    return null;
  }
}

Future<pw.MemoryImage?> _loadAssetImage(String assetPath) async {
  try {
    final data = await rootBundle.load(assetPath);
    return pw.MemoryImage(data.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

String _formatDate(DateTime date) {
  final f = DateFormat('dd/MM/yyyy', 'es');
  return f.format(date);
}

pw.Widget _pdfHeaderField(String label, String value) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(label, style: pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
      pw.Text(value, style: const pw.TextStyle(fontSize: 9)),
    ],
  );
}

pw.Widget _pdfCell(String text, {bool isHeader = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    child: pw.Text(
      text,
      style: isHeader ? pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold) : const pw.TextStyle(fontSize: 8.5),
      maxLines: 3,
      overflow: pw.TextOverflow.clip,
    ),
  );
}

pw.Widget _buildPdfEvidenceBlocks({
  required List<SurveyEntryRecord> entries,
}) {
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

pw.Widget _pdfGeneralConceptsAndBankData() {
  final leftStyle = pw.TextStyle(fontSize: 8.5, color: PdfColors.grey800);
  final rightStyle = pw.TextStyle(fontSize: 9, color: PdfColors.black);

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
              style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
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
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  decoration: pw.TextDecoration.underline,
                ),
                textAlign: pw.TextAlign.right,
              ),
              pw.SizedBox(height: 4),
              pw.Text('SOLUCIONES INTEGRALES SUSTENTABLES', style: rightStyle, textAlign: pw.TextAlign.right),
              pw.Text('INTELIGENTES Y DINAMICAS REMA, S.A.S. DE C.V.', style: rightStyle, textAlign: pw.TextAlign.right),
              pw.SizedBox(height: 10),
              pw.Text('SANTANDER', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
              pw.Text('65-50868153-1', style: rightStyle),
              pw.Text('014691 655086815 315', style: rightStyle),
            ],
          ),
        ),
      ),
    ],
  );
}

/// Estructura simple para dividir concepto en partes renderizables
class _ConceptParts {
  final String mainText;
  final String? includeText;

  _ConceptParts({required this.mainText, this.includeText});
}

_ConceptParts _splitConceptForPdf(String concept) {
  final parts = concept.split('[INCLUYE]');
  if (parts.length == 2) {
    return _ConceptParts(mainText: parts[0].trim(), includeText: parts[1].trim());
  }
  return _ConceptParts(mainText: concept.trim());
}
