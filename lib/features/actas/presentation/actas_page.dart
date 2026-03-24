import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/theme/rema_colors.dart';
import '../../../core/utils/rema_feedback.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/rema_panels.dart';

enum _ActaRole { staff, admin }

class ActasPage extends StatefulWidget {
  const ActasPage({super.key});

  @override
  State<ActasPage> createState() => _ActasPageState();
}

class _ActasPageState extends State<ActasPage> {
  final _formatter = DateFormat('dd/MM/yyyy');

  final _clienteController = TextEditingController(text: 'Residencial Las Lomas S.A.');
  final _razonSocialController = TextEditingController(text: 'Residencial Las Lomas S.A. de C.V.');
  final _direccionController = TextEditingController(text: 'Blvd. Virreyes #405, Lomas de Chapultepec, CDMX');
  final _servicioController = TextEditingController(text: 'Suministro e instalacion de cristal templado para mampara');
  final _responsableController = TextEditingController(text: 'Arq. Roberto Mendez');
  final _tituloResponsableController = TextEditingController(text: 'Supervisor de Obra');
  final _puestoResponsableController = TextEditingController(text: 'Representante tecnico del cliente');

  final _fechaInicioController = TextEditingController();
  final _fechaConclusionController = TextEditingController();
  final _numeroPedidoController = TextEditingController();
  final _fechaAprobacionPedidoController = TextEditingController();

  _ActaRole _role = _ActaRole.staff;
  int _step = 0;

  _PickedMedia? _fotoIngreso;
  _PickedMedia? _fotoAntes;
  _PickedMedia? _fotoDespues;
  final List<_PickedMedia> _fotosDurante = [];

  bool get _isAdmin => _role == _ActaRole.admin;

  @override
  void dispose() {
    _clienteController.dispose();
    _razonSocialController.dispose();
    _direccionController.dispose();
    _servicioController.dispose();
    _responsableController.dispose();
    _tituloResponsableController.dispose();
    _puestoResponsableController.dispose();
    _fechaInicioController.dispose();
    _fechaConclusionController.dispose();
    _numeroPedidoController.dispose();
    _fechaAprobacionPedidoController.dispose();
    super.dispose();
  }

  Future<void> _pickSinglePhoto(void Function(_PickedMedia?) setTarget) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );

    if (!mounted || result == null || result.files.isEmpty) {
      return;
    }

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      showRemaMessage(context, 'No se pudo leer la imagen seleccionada.');
      return;
    }

    setState(() {
      setTarget(
        _PickedMedia(
          name: file.name,
          bytes: bytes,
          size: file.size,
        ),
      );
    });
  }

  Future<void> _pickMultipleDurante() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );

    if (!mounted || result == null || result.files.isEmpty) {
      return;
    }

    setState(() {
      _fotosDurante.addAll(
        result.files
            .where((file) => file.bytes != null)
            .map(
              (file) => _PickedMedia(
                name: file.name,
                bytes: file.bytes!,
                size: file.size,
              ),
            ),
      );
    });

    showRemaMessage(context, 'Se agregaron ${result.files.length} fotos de avance.');
  }

  Future<void> _selectDate(TextEditingController controller) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
      locale: const Locale('es'),
    );

    if (selected == null) {
      return;
    }

    setState(() {
      controller.text = _formatter.format(selected);
    });
  }

  bool _validateForPdf() {
    final missing = <String>[];

    if (_fechaInicioController.text.trim().isEmpty) {
      missing.add('Fecha de inicio');
    }
    if (_fechaConclusionController.text.trim().isEmpty) {
      missing.add('Fecha de conclusion');
    }
    if (_numeroPedidoController.text.trim().isEmpty) {
      missing.add('Numero de pedido');
    }
    if (_fechaAprobacionPedidoController.text.trim().isEmpty) {
      missing.add('Fecha de aprobacion del pedido');
    }

    if (missing.isNotEmpty) {
      showRemaMessage(
        context,
        'Faltan campos requeridos: ${missing.join(', ')}.',
      );
      return false;
    }

    return true;
  }

  Future<Uint8List> _buildPdfBytes() async {
    final pdf = pw.Document();

    pw.MemoryImage? ingresoImage;
    pw.MemoryImage? antesImage;
    pw.MemoryImage? despuesImage;
    final duranteImages = <pw.MemoryImage>[];

    if (_fotoIngreso != null) {
      ingresoImage = pw.MemoryImage(_fotoIngreso!.bytes);
    }
    if (_fotoAntes != null) {
      antesImage = pw.MemoryImage(_fotoAntes!.bytes);
    }
    if (_fotoDespues != null) {
      despuesImage = pw.MemoryImage(_fotoDespues!.bytes);
    }
    for (final media in _fotosDurante.take(4)) {
      duranteImages.add(pw.MemoryImage(media.bytes));
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(36),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'REMA ARQUITECTURA',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18),
                  ),
                  pw.Text(DateFormat('dd/MM/yyyy').format(DateTime.now())),
                ],
              ),
              pw.SizedBox(height: 22),
              pw.Center(
                child: pw.Text(
                  'ACTA ENTREGA - RECEPCION',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
                ),
              ),
              pw.SizedBox(height: 18),
              pw.Text(
                'A las ${DateFormat('HH:mm').format(DateTime.now())} hrs del ${DateFormat('dd/MM/yyyy').format(DateTime.now())}, se reunen en ${_clienteController.text}, ubicado en ${_direccionController.text}.',
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                'Servicio: ${_servicioController.text}.\nPedido No. ${_numeroPedidoController.text} aprobado el ${_fechaAprobacionPedidoController.text}.\nFacturado a: ${_razonSocialController.text}.',
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                'El trabajo inicio el ${_fechaInicioController.text} y concluyo el ${_fechaConclusionController.text}.',
              ),
              pw.SizedBox(height: 24),
              pw.Text('Se firma de conformidad por ambas partes.'),
              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _signatureBlock('RESPONSABLE', _puestoResponsableController.text),
                  _signatureBlock('SUPERVISOR', '${_tituloResponsableController.text} ${_responsableController.text}'),
                  _signatureBlock('ING. MIGUEL VAZQUEZ', 'GRUPO REMAA'),
                ],
              ),
            ],
          );
        },
      ),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(36),
        build: (context) {
          return [
            pw.Text(
              'REPORTE FOTOGRAFICO',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
            ),
            pw.SizedBox(height: 12),
            _photoSection('Ingreso a las instalaciones', ingresoImage),
            pw.SizedBox(height: 10),
            _photoSection('Antes', antesImage),
            pw.SizedBox(height: 10),
            pw.Text(
              'Durante',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final image in duranteImages)
                  pw.Container(
                    width: 240,
                    height: 140,
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300)),
                    child: pw.Image(image, fit: pw.BoxFit.cover),
                  ),
                if (duranteImages.isEmpty)
                  pw.Container(
                    width: 240,
                    height: 140,
                    alignment: pw.Alignment.center,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                      color: PdfColors.grey100,
                    ),
                    child: pw.Text('Sin fotos de avance'),
                  ),
              ],
            ),
            pw.SizedBox(height: 10),
            _photoSection('Despues', despuesImage),
          ];
        },
      ),
    );

    return pdf.save();
  }

  Future<void> _previewPdf() async {
    if (!_isAdmin) {
      showRemaMessage(context, 'Solo admin puede generar el acta final.');
      return;
    }
    if (!_validateForPdf()) {
      return;
    }

    final bytes = await _buildPdfBytes();
    if (!mounted) {
      return;
    }

    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> _downloadPdf() async {
    if (!_isAdmin) {
      showRemaMessage(context, 'Solo admin puede descargar el PDF final.');
      return;
    }
    if (!_validateForPdf()) {
      return;
    }

    final bytes = await _buildPdfBytes();
    final rawOrder = _numeroPedidoController.text.trim();
    final order = rawOrder.isEmpty ? 'sin_pedido' : rawOrder.replaceAll(' ', '_');

    await Printing.sharePdf(
      bytes: bytes,
      filename: 'acta_entrega_$order.pdf',
    );

    if (!mounted) {
      return;
    }
    showRemaMessage(context, 'Acta PDF lista para descarga/compartir.');
  }

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'Actas de Entrega',
      subtitle: 'Flujo final de cierre: cuerpo de acta y reporte fotografico.',
      trailing: Wrap(
        spacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _previewPdf,
            icon: const Icon(Icons.print_outlined),
            label: const Text('Previsualizar'),
          ),
          ElevatedButton.icon(
            onPressed: _downloadPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Descargar PDF'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RoleAndSteps(
            role: _role,
            step: _step,
            onRoleChanged: (role) => setState(() => _role = role),
            onStepChanged: (step) => setState(() => _step = step),
          ),
          const SizedBox(height: 20),
          if (_step == 0)
            _ActaBodyStep(
              isAdmin: _isAdmin,
              clienteController: _clienteController,
              razonSocialController: _razonSocialController,
              direccionController: _direccionController,
              servicioController: _servicioController,
              responsableController: _responsableController,
              tituloResponsableController: _tituloResponsableController,
              puestoResponsableController: _puestoResponsableController,
              fechaInicioController: _fechaInicioController,
              fechaConclusionController: _fechaConclusionController,
              numeroPedidoController: _numeroPedidoController,
              fechaAprobacionPedidoController: _fechaAprobacionPedidoController,
              onPickDate: _selectDate,
            )
          else
            _PhotoReportStep(
              isAdmin: _isAdmin,
              fotoIngreso: _fotoIngreso,
              fotoAntes: _fotoAntes,
              fotoDespues: _fotoDespues,
              fotosDurante: _fotosDurante,
              onPickIngreso: () => _pickSinglePhoto((value) => _fotoIngreso = value),
              onPickAntes: () => _pickSinglePhoto((value) => _fotoAntes = value),
              onPickDespues: () => _pickSinglePhoto((value) => _fotoDespues = value),
              onPickDurante: _pickMultipleDurante,
              onRemoveDurante: (item) => setState(() => _fotosDurante.remove(item)),
              onClearSingle: (stage) {
                setState(() {
                  switch (stage) {
                    case 'ingreso':
                      _fotoIngreso = null;
                      break;
                    case 'antes':
                      _fotoAntes = null;
                      break;
                    case 'despues':
                      _fotoDespues = null;
                      break;
                  }
                });
              },
            ),
        ],
      ),
    );
  }

  pw.Widget _photoSection(String title, pw.MemoryImage? image) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Container(
          width: double.infinity,
          height: 170,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            color: PdfColors.grey100,
          ),
          child: image != null
              ? pw.Image(image, fit: pw.BoxFit.cover)
              : pw.Center(child: pw.Text('Sin evidencia cargada')),
        ),
      ],
    );
  }

  pw.Widget _signatureBlock(String title, String subtitle) {
    return pw.Container(
      width: 165,
      padding: const pw.EdgeInsets.only(top: 18),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.black),
        ),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            title,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            subtitle,
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 8),
          ),
        ],
      ),
    );
  }
}

class _RoleAndSteps extends StatelessWidget {
  const _RoleAndSteps({
    required this.role,
    required this.step,
    required this.onRoleChanged,
    required this.onStepChanged,
  });

  final _ActaRole role;
  final int step;
  final ValueChanged<_ActaRole> onRoleChanged;
  final ValueChanged<int> onStepChanged;

  @override
  Widget build(BuildContext context) {
    return RemaPanel(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Cuerpo Acta'),
                  selected: step == 0,
                  onSelected: (_) => onStepChanged(0),
                ),
                ChoiceChip(
                  label: const Text('Reporte Fotografico'),
                  selected: step == 1,
                  onSelected: (_) => onStepChanged(1),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          DropdownButton<_ActaRole>(
            value: role,
            onChanged: (value) {
              if (value == null) {
                return;
              }
              onRoleChanged(value);
            },
            items: const [
              DropdownMenuItem(
                value: _ActaRole.staff,
                child: Text('Rol: Staff'),
              ),
              DropdownMenuItem(
                value: _ActaRole.admin,
                child: Text('Rol: Admin'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActaBodyStep extends StatelessWidget {
  const _ActaBodyStep({
    required this.isAdmin,
    required this.clienteController,
    required this.razonSocialController,
    required this.direccionController,
    required this.servicioController,
    required this.responsableController,
    required this.tituloResponsableController,
    required this.puestoResponsableController,
    required this.fechaInicioController,
    required this.fechaConclusionController,
    required this.numeroPedidoController,
    required this.fechaAprobacionPedidoController,
    required this.onPickDate,
  });

  final bool isAdmin;
  final TextEditingController clienteController;
  final TextEditingController razonSocialController;
  final TextEditingController direccionController;
  final TextEditingController servicioController;
  final TextEditingController responsableController;
  final TextEditingController tituloResponsableController;
  final TextEditingController puestoResponsableController;
  final TextEditingController fechaInicioController;
  final TextEditingController fechaConclusionController;
  final TextEditingController numeroPedidoController;
  final TextEditingController fechaAprobacionPedidoController;
  final ValueChanged<TextEditingController> onPickDate;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        RemaPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const RemaSectionHeader(title: 'Datos base (BBDD)'),
              const SizedBox(height: 20),
              _ActaField(label: 'Cliente', controller: clienteController),
              const SizedBox(height: 16),
              _ActaField(label: 'Razon social', controller: razonSocialController),
              const SizedBox(height: 16),
              _ActaField(label: 'Direccion', controller: direccionController),
              const SizedBox(height: 16),
              _ActaField(label: 'Descripcion del servicio', controller: servicioController, maxLines: 2),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _ActaField(
                      label: 'Responsable del cliente',
                      controller: responsableController,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActaField(
                      label: 'Titulo del responsable',
                      controller: tituloResponsableController,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _ActaField(label: 'Puesto del responsable', controller: puestoResponsableController),
            ],
          ),
        ),
        const SizedBox(height: 20),
        RemaPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const RemaSectionHeader(title: 'Campos manuales para cierre'),
              const SizedBox(height: 8),
              Text(
                'Variables manuales confirmadas: fecha inicio, fecha conclusion, numero pedido y fecha aprobacion.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: RemaColors.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _DateField(
                      label: 'Fecha de inicio',
                      controller: fechaInicioController,
                      enabled: true,
                      onTap: () => onPickDate(fechaInicioController),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DateField(
                      label: 'Fecha de conclusion',
                      controller: fechaConclusionController,
                      enabled: true,
                      onTap: () => onPickDate(fechaConclusionController),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _ActaField(
                      label: 'Numero de pedido',
                      controller: numeroPedidoController,
                      enabled: isAdmin,
                      helperText: isAdmin ? null : 'Solo admin puede capturar este campo.',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DateField(
                      label: 'Fecha aprobacion pedido',
                      controller: fechaAprobacionPedidoController,
                      enabled: isAdmin,
                      onTap: () => onPickDate(fechaAprobacionPedidoController),
                      helperText: isAdmin ? null : 'Solo admin puede capturar este campo.',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PhotoReportStep extends StatelessWidget {
  const _PhotoReportStep({
    required this.isAdmin,
    required this.fotoIngreso,
    required this.fotoAntes,
    required this.fotoDespues,
    required this.fotosDurante,
    required this.onPickIngreso,
    required this.onPickAntes,
    required this.onPickDespues,
    required this.onPickDurante,
    required this.onRemoveDurante,
    required this.onClearSingle,
  });

  final bool isAdmin;
  final _PickedMedia? fotoIngreso;
  final _PickedMedia? fotoAntes;
  final _PickedMedia? fotoDespues;
  final List<_PickedMedia> fotosDurante;
  final VoidCallback onPickIngreso;
  final VoidCallback onPickAntes;
  final VoidCallback onPickDespues;
  final VoidCallback onPickDurante;
  final ValueChanged<_PickedMedia> onRemoveDurante;
  final ValueChanged<String> onClearSingle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        RemaPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const RemaSectionHeader(title: 'Paginas 2-5 / Reporte Fotografico'),
              const SizedBox(height: 18),
              _SinglePhotoCard(
                title: 'Ingreso a las instalaciones',
                subtitle: 'Pagina 2',
                media: fotoIngreso,
                onPick: onPickIngreso,
                onClear: () => onClearSingle('ingreso'),
              ),
              const SizedBox(height: 12),
              _SinglePhotoCard(
                title: 'Antes (levantamiento)',
                subtitle: 'Pagina 3',
                media: fotoAntes,
                onPick: onPickAntes,
                onClear: () => onClearSingle('antes'),
              ),
              const SizedBox(height: 12),
              _SinglePhotoCard(
                title: 'Despues (entrega final)',
                subtitle: 'Pagina 5',
                media: fotoDespues,
                onPick: onPickDespues,
                onClear: () => onClearSingle('despues'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Durante (pagina 4): evidencia de staff durante ejecucion.',
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: onPickDurante,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('Agregar fotos'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final item in fotosDurante)
                    _ThumbPhoto(
                      media: item,
                      onRemove: () => onRemoveDurante(item),
                    ),
                ],
              ),
              if (fotosDurante.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(top: 6),
                  color: RemaColors.surfaceLow,
                  child: const Text('Sin evidencia DURANTE cargada.'),
                ),
              if (!isAdmin) ...[
                const SizedBox(height: 16),
                const Text(
                  'Modo Staff: puedes capturar evidencia. El cierre y emision PDF final son acciones de admin.',
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ActaField extends StatelessWidget {
  const _ActaField({
    required this.label,
    required this.controller,
    this.maxLines = 1,
    this.enabled = true,
    this.helperText,
  });

  final String label;
  final TextEditingController controller;
  final int maxLines;
  final bool enabled;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.controller,
    required this.onTap,
    this.enabled = true,
    this.helperText,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onTap;
  final bool enabled;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: true,
      enabled: enabled,
      onTap: enabled ? onTap : null,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        suffixIcon: const Icon(Icons.event),
      ),
    );
  }
}

class _SinglePhotoCard extends StatelessWidget {
  const _SinglePhotoCard({
    required this.title,
    required this.subtitle,
    required this.media,
    required this.onPick,
    required this.onClear,
  });

  final String title;
  final String subtitle;
  final _PickedMedia? media;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: RemaColors.surfaceLow,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$title · $subtitle',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              TextButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Cargar'),
              ),
            ],
          ),
          if (media == null)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Sin imagen seleccionada.'),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.memory(
                    media!.bytes,
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(child: Text(media!.name, overflow: TextOverflow.ellipsis)),
                    IconButton(
                      onPressed: onClear,
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Quitar imagen',
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ThumbPhoto extends StatelessWidget {
  const _ThumbPhoto({required this.media, required this.onRemove});

  final _PickedMedia media;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 144,
      decoration: BoxDecoration(
        color: RemaColors.surfaceLow,
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.memory(
              media.bytes,
              height: 92,
              width: 128,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            media.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 18),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _PickedMedia {
  const _PickedMedia({
    required this.name,
    required this.bytes,
    required this.size,
  });

  final String name;
  final Uint8List bytes;
  final int size;
}
