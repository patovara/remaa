import 'package:flutter/material.dart';

import '../../../core/theme/rema_colors.dart';
import '../../../core/utils/rema_feedback.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/rema_panels.dart';

class PresupuestoPage extends StatelessWidget {
  const PresupuestoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'Presupuesto',
      subtitle: 'Vista formal de cotizacion ajustada para impresion y revision.',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => showRemaMessage(context, 'Impresion lista para integrarse con la web.'),
            icon: const Icon(Icons.print_outlined),
          ),
          IconButton(
            onPressed: () => showRemaMessage(context, 'Descarga PDF pendiente de integracion.'),
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            onPressed: () => showRemaMessage(context, 'Compartir presupuesto listo para conectar con backend.'),
            icon: const Icon(Icons.share_outlined),
          ),
        ],
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
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
                          Text('REMA ARQUITECTURA S.A. DE C.V.', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 4),
                          const Text('RFC: RAR1234567A1 | TEL: +52 55 1234 5678'),
                          const Text('Av. de los Arquitectos 100, Col. Centro, CDMX'),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('COTIZACION', style: Theme.of(context).textTheme.headlineLarge?.copyWith(color: RemaColors.primaryDark)),
                        const SizedBox(height: 6),
                        const Text('FOLIO: #QT-2024-089'),
                        const Text('FECHA: 24 DE MAYO, 2024'),
                        const Text('VENCE: 08 DE JUNIO, 2024'),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: const [
                    Expanded(
                      child: _HighlightBlock(
                        title: 'Cliente',
                        heading: 'RESIDENCIAL LAS LOMAS S.A.',
                        body: 'Atn: Arq. Roberto Mendez\nBlvd. Virreyes #405, Lomas de Chapultepec, CDMX.',
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: _HighlightBlock(
                        title: 'Proyecto',
                        heading: 'REMODELACION DE PENTHOUSE',
                        body: 'Ubicacion: Torre Norte, Piso 22\nClave: REMA-PH-22 | Area: 185.00 m2',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Concepto / Descripcion')),
                      DataColumn(label: Text('Unidad')),
                      DataColumn(label: Text('Cant.')),
                      DataColumn(label: Text('P.U.')),
                      DataColumn(label: Text('Importe')),
                    ],
                    rows: const [
                      DataRow(cells: [
                        DataCell(Text('Mampara de cristal templado')),
                        DataCell(Text('Pza')),
                        DataCell(Text('2.00')),
                        DataCell(Text('\$14,250.00')),
                        DataCell(Text('\$28,500.00')),
                      ]),
                      DataRow(cells: [
                        DataCell(Text('Levantamiento y digitalizacion')),
                        DataCell(Text('Lote')),
                        DataCell(Text('1.00')),
                        DataCell(Text('\$12,500.00')),
                        DataCell(Text('\$12,500.00')),
                      ]),
                      DataRow(cells: [
                        DataCell(Text('Proyecto ejecutivo de remodelacion')),
                        DataCell(Text('m2')),
                        DataCell(Text('185.00')),
                        DataCell(Text('\$350.00')),
                        DataCell(Text('\$64,750.00')),
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
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('IMPORTE CON LETRA'),
                            SizedBox(height: 8),
                            Text('Ciento veintidos mil seiscientos setenta pesos 00/100 M.N.'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    SizedBox(
                      width: 240,
                      child: Column(
                        children: const [
                          _TotalRow(label: 'Subtotal', value: '\$105,750.00'),
                          SizedBox(height: 8),
                          _TotalRow(label: 'IVA (16%)', value: '\$16,920.00'),
                          Divider(height: 24),
                          _TotalRow(label: 'Total M.N.', value: '\$122,670.00', isStrong: true),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  color: RemaColors.surfaceLow,
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Conceptos Generales y Condiciones'),
                      SizedBox(height: 12),
                      Text('• Precios no incluyen mobiliario ni equipamiento no especificado.'),
                      Text('• Tiempo de entrega: 4 semanas a partir de anticipo.'),
                      Text('• Vigencia de cotizacion: 15 dias naturales tras emision.'),
                      Text('• Pago: anticipo 50%, resto contra entrega de etapas.'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HighlightBlock extends StatelessWidget {
  const _HighlightBlock({required this.title, required this.heading, required this.body});

  final String title;
  final String heading;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFFFFF2CC),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 6),
          Text(heading, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 18)),
          const SizedBox(height: 6),
          Text(body),
        ],
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
        Expanded(
          child: Text(label, style: style),
        ),
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
