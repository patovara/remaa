import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/rema_colors.dart';
import '../../../core/utils/rema_feedback.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/rema_panels.dart';

class LevantamientoPage extends StatefulWidget {
  const LevantamientoPage({super.key});

  @override
  State<LevantamientoPage> createState() => _LevantamientoPageState();
}

class _LevantamientoPageState extends State<LevantamientoPage> {
  final _projectKeyController = TextEditingController(text: 'P-001');
  final _projectNameController = TextEditingController(text: 'Residencia Olivos');
  final _clientController = TextEditingController(text: 'Ing. Roberto Mendez');
  final _addressController = TextEditingController(
    text: 'Av. de la Reforma 222, Juarez, Cuauhtemoc, CDMX',
  );
  final _notesController = TextEditingController(
    text: 'Describa el estado actual del terreno, accesos, servicios disponibles y requerimientos especificos del cliente detectados durante la visita.',
  );

  DateTime _selectedDate = DateTime(2024, 10, 24);
  String _selectedArchitect = 'Arq. Daniel M.';
  bool _topographicSurvey = true;
  bool _specialPermits = false;
  final List<_PickedMedia> _photos = [];

  @override
  void dispose() {
    _projectKeyController.dispose();
    _projectNameController.dispose();
    _clientController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );

    if (!mounted || result == null || result.files.isEmpty) {
      return;
    }

    setState(() {
      _photos.addAll(
        result.files.map(
          (file) => _PickedMedia(
            name: file.name,
            bytes: file.bytes,
            size: file.size,
          ),
        ),
      );
    });

    showRemaMessage(context, 'Se agregaron ${result.files.length} imagenes al levantamiento.');
  }

  void _removePhoto(_PickedMedia photo) {
    setState(() => _photos.remove(photo));
    showRemaMessage(context, 'Se elimino ${photo.name}.');
  }

  Future<void> _copyCoordinates() async {
    await Clipboard.setData(
      const ClipboardData(text: '19.4326 N, 99.1332 W - CDMX, MX'),
    );
    if (!mounted) {
      return;
    }
    showRemaMessage(context, 'Coordenadas copiadas al portapapeles.');
  }

  void _finishSurvey() {
    showRemaMessage(
      context,
      'Levantamiento listo para continuar. Fotos cargadas: ${_photos.length}.',
      label: 'Presupuesto',
      onAction: () => context.go('/presupuesto'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'Levantamiento de Proyecto',
      subtitle: 'Registro tecnico de obra, evidencia y georreferencia inicial.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 1120;
          final details = _ProjectDetailsPanel(
            selectedDate: _selectedDate,
            onDateChanged: (value) => setState(() => _selectedDate = value),
            projectKeyController: _projectKeyController,
            selectedArchitect: _selectedArchitect,
            onArchitectChanged: (value) => setState(() => _selectedArchitect = value),
            projectNameController: _projectNameController,
            clientController: _clientController,
          );
          final media = _EvidencePanel(
            photos: _photos,
            onAddPhotos: _pickPhotos,
            onRemove: _removePhoto,
          );
          final location = _LocationPanel(
            addressController: _addressController,
            onCopyCoordinates: _copyCoordinates,
          );
          final notes = _DescriptionPanel(
            notesController: _notesController,
            topographicSurvey: _topographicSurvey,
            onTopographicChanged: (value) => setState(() => _topographicSurvey = value),
            specialPermits: _specialPermits,
            onSpecialPermitsChanged: (value) => setState(() => _specialPermits = value),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Column(
                        children: [
                          details,
                          const SizedBox(height: 24),
                          media,
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 7,
                      child: Column(
                        children: [
                          location,
                          const SizedBox(height: 24),
                          notes,
                        ],
                      ),
                    ),
                  ],
                )
              else ...[
                details,
                const SizedBox(height: 20),
                location,
                const SizedBox(height: 20),
                notes,
                const SizedBox(height: 20),
                media,
              ],
              const SizedBox(height: 28),
              _BottomActions(
                onQuote: () => context.go('/presupuesto'),
                onFinish: _finishSurvey,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProjectDetailsPanel extends StatelessWidget {
  const _ProjectDetailsPanel({
    required this.selectedDate,
    required this.onDateChanged,
    required this.projectKeyController,
    required this.selectedArchitect,
    required this.onArchitectChanged,
    required this.projectNameController,
    required this.clientController,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateChanged;
  final TextEditingController projectKeyController;
  final String selectedArchitect;
  final ValueChanged<String> onArchitectChanged;
  final TextEditingController projectNameController;
  final TextEditingController clientController;

  @override
  Widget build(BuildContext context) {
    return RemaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RemaSectionHeader(title: 'Detalles del Proyecto'),
          const SizedBox(height: 24),
          const _FieldLabel(label: 'Fecha de registro'),
          const SizedBox(height: 8),
          InputDatePickerFormField(
            firstDate: DateTime(2020),
            lastDate: DateTime(2035),
            initialDate: selectedDate,
            onDateSubmitted: onDateChanged,
            onDateSaved: onDateChanged,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _UnderlinedField(
                  label: 'Clave proyecto',
                  controller: projectKeyController,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: _DropdownField(
                  label: 'Responsable',
                  value: selectedArchitect,
                  items: const ['Arq. Daniel M.', 'Arq. Sofia R.', 'Arq. Elena G.'],
                  onChanged: onArchitectChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _UnderlinedField(
            label: 'Nombre del proyecto',
            controller: projectNameController,
          ),
          const SizedBox(height: 20),
          _UnderlinedField(
            label: 'Cliente',
            controller: clientController,
            suffixIcon: Icons.person_search,
          ),
        ],
      ),
    );
  }
}

class _EvidencePanel extends StatelessWidget {
  const _EvidencePanel({
    required this.photos,
    required this.onAddPhotos,
    required this.onRemove,
  });

  final List<_PickedMedia> photos;
  final VoidCallback onAddPhotos;
  final ValueChanged<_PickedMedia> onRemove;

  @override
  Widget build(BuildContext context) {
    return RemaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RemaSectionHeader(
            title: 'Evidencia Fotografica',
            trailing: Text(
              '${photos.length} ARCHIVOS',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final photo in photos)
                _PhotoTile(
                  photo: photo,
                  onRemove: () => onRemove(photo),
                ),
              _AddPhotoTile(onTap: onAddPhotos),
            ],
          ),
        ],
      ),
    );
  }
}

class _LocationPanel extends StatelessWidget {
  const _LocationPanel({
    required this.addressController,
    required this.onCopyCoordinates,
  });

  final TextEditingController addressController;
  final VoidCallback onCopyCoordinates;

  @override
  Widget build(BuildContext context) {
    return RemaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RemaSectionHeader(
            title: 'Ubicacion y Georreferencia',
            trailing: TextButton.icon(
              onPressed: onCopyCoordinates,
              icon: const Icon(Icons.content_copy, size: 16),
              label: const Text('Copiar coordenadas'),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            height: 320,
            decoration: BoxDecoration(
              color: RemaColors.surfaceHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          RemaColors.surfaceHighest,
                          RemaColors.surfaceLow,
                        ],
                      ),
                    ),
                  ),
                ),
                const Center(
                  child: CircleAvatar(
                    radius: 24,
                    backgroundColor: RemaColors.primaryDark,
                    child: Icon(Icons.location_on, color: Colors.white),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    color: Colors.white.withValues(alpha: 0.92),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('19.4326 N, 99.1332 W'),
                        Text('CDMX, MX'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _UnderlinedField(
            label: 'Direccion completa',
            controller: addressController,
          ),
        ],
      ),
    );
  }
}

class _DescriptionPanel extends StatelessWidget {
  const _DescriptionPanel({
    required this.notesController,
    required this.topographicSurvey,
    required this.onTopographicChanged,
    required this.specialPermits,
    required this.onSpecialPermitsChanged,
  });

  final TextEditingController notesController;
  final bool topographicSurvey;
  final ValueChanged<bool> onTopographicChanged;
  final bool specialPermits;
  final ValueChanged<bool> onSpecialPermitsChanged;

  @override
  Widget build(BuildContext context) {
    return RemaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RemaSectionHeader(title: 'Descripcion del Proyecto'),
          const SizedBox(height: 24),
          const _FieldLabel(label: 'Notas y observaciones de campo'),
          const SizedBox(height: 10),
          TextField(
            controller: notesController,
            minLines: 6,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: 'Detalle tecnico y requerimientos detectados durante la visita...',
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _CheckOption(
                label: 'Levantamiento topografico requerido',
                value: topographicSurvey,
                onChanged: onTopographicChanged,
              ),
              _CheckOption(
                label: 'Permisos especiales detectados',
                value: specialPermits,
                onChanged: onSpecialPermitsChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({required this.onQuote, required this.onFinish});

  final VoidCallback onQuote;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton(
            onPressed: onQuote,
            child: const Text('Agregar a la cotizacion'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onFinish,
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.photo, required this.onRemove});

  final _PickedMedia photo;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: photo.bytes != null
                        ? Image.memory(photo.bytes!, fit: BoxFit.cover)
                        : Container(
                            color: RemaColors.surfaceLow,
                            alignment: Alignment.center,
                            child: const Icon(Icons.image_outlined),
                          ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Material(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: onRemove,
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.close, size: 16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            photo.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            _formatBytes(photo.size),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 160,
        height: 160,
        decoration: BoxDecoration(
          color: RemaColors.surfaceLow,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: RemaColors.outlineVariant),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_outlined, size: 32, color: RemaColors.onSurfaceVariant),
            SizedBox(height: 8),
            Text('Anadir'),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 1.8,
          ),
    );
  }
}

class _UnderlinedField extends StatelessWidget {
  const _UnderlinedField({
    required this.label,
    required this.controller,
    this.suffixIcon,
  });

  final String label;
  final TextEditingController controller;
  final IconData? suffixIcon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: label),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          decoration: InputDecoration(suffixIcon: suffixIcon != null ? Icon(suffixIcon) : null),
        ),
      ],
    );
  }
}

class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: label),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: value,
          decoration: const InputDecoration(),
          items: [
            for (final item in items)
              DropdownMenuItem<String>(value: item, child: Text(item)),
          ],
          onChanged: (newValue) {
            if (newValue != null) {
              onChanged(newValue);
            }
          },
        ),
      ],
    );
  }
}

class _CheckOption extends StatelessWidget {
  const _CheckOption({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: value,
          onChanged: (newValue) => onChanged(newValue ?? false),
        ),
        Text(label),
      ],
    );
  }
}

class _PickedMedia {
  const _PickedMedia({
    required this.name,
    required this.size,
    this.bytes,
  });

  final String name;
  final int size;
  final Uint8List? bytes;
}

String _formatBytes(int size) {
  if (size < 1024) {
    return '$size B';
  }
  final kb = size / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(1)} KB';
  }
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(1)} MB';
}
