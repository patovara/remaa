import 'package:file_picker/file_picker.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/rema_colors.dart';
import '../../../core/utils/rema_feedback.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/rema_panels.dart';
import '../../../core/config/supabase_bootstrap.dart';
import '../../cotizaciones/domain/concept_generation.dart';
import '../../cotizaciones/domain/quote_models.dart';
import '../../cotizaciones/presentation/concepts_catalog_controller.dart';
import '../../cotizaciones/presentation/quotes_controller.dart';
import '../../clientes/presentation/clientes_mock_data.dart';
import 'levantamiento_state.dart';

class LevantamientoPage extends ConsumerStatefulWidget {
  const LevantamientoPage({super.key});

  @override
  ConsumerState<LevantamientoPage> createState() => _LevantamientoPageState();
}

class _LevantamientoPageState extends ConsumerState<LevantamientoPage> {
  final _projectKeyController = TextEditingController();
  final _projectNameController = TextEditingController();
  final _clientController = TextEditingController();
  final _addressController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  String? _selectedClientId;
  String? _selectedProjectId;
  String? _selectedUniverseId;
  String? _selectedProjectTypeId;
  bool _isCreatingQuote = false;
  final List<_PickedMedia> _photos = [];

  @override
  void initState() {
    super.initState();
    // Restaurar campos del formulario si hay una sesión activa
    final active = ref.read(activeLevantamientoProvider);
    if (active != null && active.isActive) {
      if (active.projectKey?.isNotEmpty == true) {
        _projectKeyController.text = active.projectKey!;
      }
      if (active.projectName?.isNotEmpty == true) {
        _projectNameController.text = active.projectName!;
      }
      if (active.clientName?.isNotEmpty == true) {
        _clientController.text = active.clientName!;
      }
      if (active.address?.isNotEmpty == true) {
        _addressController.text = active.address!;
      }
      _selectedClientId = active.clientId;
      _selectedProjectId = active.projectId;
      if (active.entries.isNotEmpty) {
        _notesController.text = active.entries.last.description;
      }
    }
  }

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
    const maxPhotosPerEntry = 2;
    final remaining = maxPhotosPerEntry - _photos.length;
    if (remaining <= 0) {
      showRemaMessage(context, 'Maximo 2 fotos por cada descripcion.');
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );

    if (!mounted || result == null || result.files.isEmpty) {
      return;
    }

    final selectedFiles = result.files.toList();
    final acceptedFiles = selectedFiles.take(remaining).toList();
    final normalizedMedia = <_PickedMedia>[];
    for (final file in acceptedFiles) {
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        continue;
      }
      final optimized = await _optimizeImageBytes(bytes);
      normalizedMedia.add(
        _PickedMedia(
          name: file.name,
          bytes: optimized,
          size: optimized.length,
        ),
      );
    }

    setState(() {
      _photos.addAll(normalizedMedia);
    });

    if (acceptedFiles.length < selectedFiles.length) {
      showRemaMessage(context, 'Solo se permiten 2 fotos por descripcion.');
      return;
    }
    showRemaMessage(context, 'Se agregaron ${acceptedFiles.length} imagenes al levantamiento.');
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

  Future<void> _goToQuote() async {
    final active = ref.read(activeLevantamientoProvider);
    final selectedUniverseId = _selectedUniverseId;
    final selectedProjectTypeId = _selectedProjectTypeId;

    if (selectedUniverseId == null || selectedProjectTypeId == null) {
      showRemaMessage(context, 'Selecciona universo y tipo de proyecto para continuar.');
      return;
    }

    if (active != null && active.isActive && active.universeId != selectedUniverseId) {
      showRemaMessage(
        context,
        'Ya hay un levantamiento activo en otro universo. Finalizalo antes de cambiar.',
      );
      return;
    }

    if (active != null && active.isActive && active.quoteId != null) {
      await _syncActiveQuoteContextAndEntries(active);
      context.go('/presupuesto/${active.quoteId}');
      return;
    }

    setState(() => _isCreatingQuote = true);
    try {
      final selectedProjectId =
          await _resolveProjectIdForQuote() ?? _selectedProjectId;
      if (selectedProjectId == null || selectedProjectId.isEmpty) {
        if (mounted) {
          showRemaMessage(context, 'No se pudo preparar el proyecto para la cotizacion.');
        }
        return;
      }

      final projectName = _projectNameController.text.trim();
      final manager = '';
      final address = _addressController.text.trim();
      final notes = _notesController.text.trim();
      final projectKey = await _ensureProjectKey();
      final entry = _buildCurrentEntry();
      final composedDescription = _composeDescriptions(
        entries: entry == null ? const <SurveyEntryRecord>[] : <SurveyEntryRecord>[entry],
        fallbackDescription: notes,
      );

      if (entry != null) {
        final evidenceInputs = _currentEvidenceInputs();
        await ref.read(quotesProvider.notifier).appendSurveyEntry(
              projectId: selectedProjectId,
              description: entry.description,
          evidenceInputs: evidenceInputs,
            );
      }

      await ref.read(quotesProvider.notifier).updateProjectContext(
            projectId: selectedProjectId,
            name: projectName.isEmpty ? 'Proyecto sin nombre' : projectName,
            managerName: manager,
            address: address,
        description: composedDescription,
            clientId: _selectedClientId,
          );

      final quote = await ref.read(quotesProvider.notifier).createDraft(
            projectId: selectedProjectId,
            universeId: selectedUniverseId,
            projectTypeId: selectedProjectTypeId,
            projectKey: projectKey,
          );

      if (!mounted) {
        return;
      }

      ref.read(activeLevantamientoProvider.notifier).activate(
            projectId: selectedProjectId,
            universeId: selectedUniverseId,
            projectTypeId: selectedProjectTypeId,
            quoteId: quote.id,
            projectKey: _projectKeyController.text.trim(),
            projectName: _projectNameController.text.trim(),
            clientId: _selectedClientId,
            clientName: _clientController.text.trim(),
            address: _addressController.text.trim(),
            evidenceCount: _photos.length,
            evidencePreviewList: _previewPhotos(),
            entries: entry == null ? const <SurveyEntryRecord>[] : <SurveyEntryRecord>[entry],
          );

      showRemaMessage(context, 'Levantamiento asociado a ${quote.quoteNumber}.');
      context.go('/presupuesto/${quote.id}');
    } finally {
      if (mounted) {
        setState(() => _isCreatingQuote = false);
      }
    }
  }

  Future<String?> _resolveProjectIdForQuote() async {
    final selectedId = _selectedProjectId?.trim();
    if (selectedId != null && selectedId.isNotEmpty) {
      return selectedId;
    }

    final active = ref.read(activeLevantamientoProvider);
    if (active != null && active.projectId.trim().isNotEmpty) {
      final activeProjectId = active.projectId.trim();
      if (mounted) {
        setState(() => _selectedProjectId = activeProjectId);
      }
      return activeProjectId;
    }

    try {
      final code = await _ensureProjectKey();
      final created = await ref.read(quotesProvider.notifier).createProject(
            input: NewProjectInput(
              code: code,
              name: _projectNameController.text.trim().isEmpty
                  ? 'Proyecto sin nombre'
                  : _projectNameController.text.trim(),
              clientId: _selectedClientId,
              siteAddress: _addressController.text.trim(),
              description: _notesController.text.trim(),
              managerName: null,
            ),
          );

      if (mounted) {
        setState(() => _selectedProjectId = created.id);
      }
      return created.id;
    } catch (error) {
      if (mounted) {
        showRemaMessage(context, 'No se pudo crear el proyecto: $error');
      }
      return null;
    }
  }

  Future<String> _ensureProjectKey() async {
    final current = _projectKeyController.text.trim().toUpperCase();
    if (current.startsWith('PRJ')) {
      return current;
    }

    try {
      final key = await ref.read(quotesProvider.notifier).reserveProjectKey();
      if (!mounted) {
        return key;
      }
      _projectKeyController.text = key;
      return key;
    } catch (_) {
      const fallback = 'PRJ001';
      if (mounted && _projectKeyController.text.trim().isEmpty) {
        _projectKeyController.text = fallback;
      }
      return fallback;
    }
  }

  Future<void> _openClientSelector() async {
    final active = ref.read(activeLevantamientoProvider);
    final projectDataLocked = active != null && active.isActive && active.quoteId != null;
    if (projectDataLocked) {
      showRemaMessage(
        context,
        'Cliente bloqueado mientras la cotizacion en curso siga activa. Finaliza el levantamiento para editarlo.',
      );
      return;
    }

    final selected = await showDialog<ClientRecord>(
      context: context,
      builder: (_) => const _ClientSelectorDialog(),
    );
    if (selected != null && mounted) {
      final address = selected.address.trim();
      setState(() {
        _clientController.text = selected.name;
        _selectedClientId = selected.id;
        if (address.isNotEmpty && address.toLowerCase() != 'sin dirección') {
          _addressController.text = address;
        }
      });

      // Solo generar folio nuevo si no tenemos uno ya (evita duplicar PRJ001→PRJ002)
      final existingKey = _projectKeyController.text.trim();
      final sessionKey = active?.projectKey?.trim() ?? '';
      if (existingKey.isEmpty && sessionKey.isNotEmpty) {
        // Restaurar clave de sesión antes de intentar generar una nueva
        _projectKeyController.text = sessionKey;
      } else if (existingKey.isEmpty) {
        await _ensureProjectKey();
        if (!mounted) return;
        final generated = _projectKeyController.text.trim();
        if (generated.isNotEmpty) {
          showRemaMessage(context, 'Folio de proyecto generado: $generated');
        }
      }

      // Actualizar snapshot con datos del nuevo cliente
      if (active != null && active.isActive) {
        ref.read(activeLevantamientoProvider.notifier).updateSnapshot(
          clientId: selected.id,
          clientName: selected.name,
          address: address.isNotEmpty ? address : null,
          projectKey: _projectKeyController.text.trim(),
        );
      }
    }
  }

  bool _isUuid(String value) {
    final uuidPattern = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    );
    return uuidPattern.hasMatch(value);
  }

  void _finishSurvey() {
    final active = ref.read(activeLevantamientoProvider);
    if (active == null || !active.isActive) {
      showRemaMessage(context, 'No hay un levantamiento activo para finalizar.');
      return;
    }

    ref.read(activeLevantamientoProvider.notifier).finish();
    showRemaMessage(
      context,
      'Levantamiento finalizado. Fotos cargadas: ${_photos.length}. Ya puedes iniciar otro universo.',
      label: active.quoteId != null ? 'Presupuesto' : null,
      onAction: active.quoteId != null
          ? () => context.go('/presupuesto/${active.quoteId}')
          : null,
      duration: const Duration(seconds: 8),
    );
  }

  SurveyEntryRecord? _buildCurrentEntry() {
    final description = _notesController.text.trim();
    final evidenceInputs = _currentEvidenceInputs();
    final evidence = [for (final input in evidenceInputs) input.bytes];
    final metadata = [
      for (var index = 0; index < evidenceInputs.length; index++)
        SurveyEvidenceMeta(
          objectPath: '',
          originalName: evidenceInputs[index].originalName,
          fileSizeBytes: evidenceInputs[index].fileSizeBytes,
          sortOrder: index,
          mimeType: evidenceInputs[index].mimeType,
        ),
    ];
    if (description.isEmpty && evidence.isEmpty) {
      return null;
    }
    return SurveyEntryRecord(
      description: description,
      evidencePreviewList: evidence,
      evidenceMetadata: metadata,
    );
  }

  List<SurveyEvidenceInput> _currentEvidenceInputs() {
    final inputs = <SurveyEvidenceInput>[];
    for (final photo in _photos) {
      final bytes = photo.bytes;
      if (bytes == null || bytes.isEmpty) {
        continue;
      }
      inputs.add(
        SurveyEvidenceInput(
          bytes: bytes,
          originalName: photo.name,
          fileSizeBytes: photo.size,
          mimeType: _guessMimeType(photo.name),
        ),
      );
      if (inputs.length == 2) {
        break;
      }
    }
    return inputs;
  }

  String _guessMimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    return 'image/jpeg';
  }

  Future<Uint8List> _optimizeImageBytes(Uint8List input) async {
    try {
      final codec = await ui.instantiateImageCodec(
        input,
        targetWidth: 600,
      );
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        return input;
      }
      return data.buffer.asUint8List();
    } catch (_) {
      return input;
    }
  }

  String _composeDescriptions({
    required List<SurveyEntryRecord> entries,
    required String fallbackDescription,
  }) {
    final unique = <String>{};
    final ordered = <String>[];

    for (final entry in entries) {
      final text = entry.description.trim();
      if (text.isNotEmpty && unique.add(text)) {
        ordered.add(text);
      }
    }

    final fallback = fallbackDescription.trim();
    if (fallback.isNotEmpty && unique.add(fallback)) {
      ordered.add(fallback);
    }

    if (ordered.isEmpty) {
      return '';
    }
    return ordered.join('\n\n---\n\n');
  }

  Future<void> _syncActiveQuoteContextAndEntries(ActiveLevantamientoSession active) async {
    final notifier = ref.read(activeLevantamientoProvider.notifier);
    final entry = _buildCurrentEntry();
    if (entry != null) {
      final evidenceInputs = _currentEvidenceInputs();
      await ref.read(quotesProvider.notifier).appendSurveyEntry(
            projectId: active.projectId,
            quoteId: active.quoteId,
            description: entry.description,
            evidenceInputs: evidenceInputs,
          );
      notifier.addEntry(
        description: entry.description,
        evidencePreviewList: entry.evidencePreviewList,
        evidenceMetadata: entry.evidenceMetadata,
      );
    }

    final updated = ref.read(activeLevantamientoProvider) ?? active;
    final description = _composeDescriptions(
      entries: updated.entries,
      fallbackDescription: _notesController.text.trim(),
    );
    if (description.isEmpty) {
      return;
    }

    final projectName = (updated.projectName ?? _projectNameController.text).trim();
    final address = (updated.address ?? _addressController.text).trim();
    await ref.read(quotesProvider.notifier).updateProjectContext(
          projectId: updated.projectId,
          name: projectName.isEmpty ? 'Proyecto sin nombre' : projectName,
          managerName: '',
          address: address,
          description: description,
          clientId: updated.clientId ?? _selectedClientId,
        );
  }

  List<ProjectTypeCatalogItem> _allowedProjectTypes(
    List<ProjectTypeCatalogItem> items,
  ) {
    bool isAllowed(String raw) {
      final value = raw.toLowerCase().trim();
      return value == 'mantenimiento' || value == 'construccion' || value == 'remodelacion';
    }

    return [for (final item in items) if (isAllowed(item.name)) item];
  }

  List<Uint8List> _previewPhotos() {
    final previews = <Uint8List>[];
    for (final photo in _photos) {
      if (photo.bytes != null && photo.bytes!.isNotEmpty) {
        previews.add(photo.bytes!);
      }
    }
    return previews;
  }

  void _primeSelections({
    required List<UniverseCatalogItem> universes,
    required List<ProjectTypeCatalogItem> projectTypes,
    required ActiveLevantamientoSession? active,
  }) {
    String? nextUniverseId = _selectedUniverseId;
    String? nextProjectTypeId = _selectedProjectTypeId;

    if (active != null && active.isActive) {
      nextUniverseId = active.universeId;
      nextProjectTypeId = active.projectTypeId;
    } else {
      if (nextUniverseId == null && universes.isNotEmpty) {
        nextUniverseId = universes.first.id;
      }
      if (nextProjectTypeId == null && projectTypes.isNotEmpty) {
        nextProjectTypeId = projectTypes.first.id;
      }
    }

    final changed = nextUniverseId != _selectedUniverseId ||
        nextProjectTypeId != _selectedProjectTypeId;

    if (!changed) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedUniverseId = nextUniverseId;
        _selectedProjectTypeId = nextProjectTypeId;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final catalogState = ref.watch(conceptsCatalogProvider);
    final activeLevantamiento = ref.watch(activeLevantamientoProvider);

    final universes = catalogState.valueOrNull?.universes ?? const <UniverseCatalogItem>[];
    final projectTypes = _allowedProjectTypes(
      catalogState.valueOrNull?.projectTypes ?? const <ProjectTypeCatalogItem>[],
    );

    _primeSelections(
      universes: universes,
      projectTypes: projectTypes,
      active: activeLevantamiento,
    );

    final universeLocked = activeLevantamiento != null && activeLevantamiento.isActive;
    final projectDataLocked =
        activeLevantamiento != null && activeLevantamiento.isActive && activeLevantamiento.quoteId != null;

    return PageFrame(
      title: 'Levantamiento de Proyecto',
      subtitle: 'Registro tecnico de obra, evidencia y georreferencia inicial.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 1120;
          final details = _ProjectDetailsPanel(
            selectedDate: _selectedDate,
            projectKeyController: _projectKeyController,
            projectNameController: _projectNameController,
            clientController: _clientController,
            onClientTap: _openClientSelector,
            universes: universes,
            selectedUniverseId: _selectedUniverseId,
            onUniverseChanged: universeLocked
                ? null
                : (value) {
                    if (!ref
                        .read(activeLevantamientoProvider.notifier)
                        .canUseUniverse(value)) {
                      showRemaMessage(
                        context,
                        'Universo bloqueado por levantamiento activo.',
                      );
                      return;
                    }
                    setState(() => _selectedUniverseId = value);
                  },
            projectTypes: projectTypes,
            selectedProjectTypeId: _selectedProjectTypeId,
            onProjectTypeChanged: universeLocked
                ? null
                : (value) => setState(() => _selectedProjectTypeId = value),
            showCatalogWarning: catalogState.hasError,
            universeLocked: universeLocked,
            projectDataLocked: projectDataLocked,
          );
          final media = _EvidencePanel(
            photos: _photos,
            onAddPhotos: _pickPhotos,
            onRemove: _removePhoto,
          );
          final location = _LocationPanel(
            addressController: _addressController,
          );
          final notes = _DescriptionPanel(
            notesController: _notesController,
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
                onQuote: _isCreatingQuote ? null : _goToQuote,
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
    required this.projectKeyController,
    required this.projectNameController,
    required this.clientController,
    required this.onClientTap,
    required this.universes,
    required this.selectedUniverseId,
    required this.onUniverseChanged,
    required this.projectTypes,
    required this.selectedProjectTypeId,
    required this.onProjectTypeChanged,
    required this.showCatalogWarning,
    required this.universeLocked,
    required this.projectDataLocked,
  });

  final DateTime selectedDate;
  final TextEditingController projectKeyController;
  final TextEditingController projectNameController;
  final TextEditingController clientController;
  final VoidCallback onClientTap;
  final List<UniverseCatalogItem> universes;
  final String? selectedUniverseId;
  final ValueChanged<String>? onUniverseChanged;
  final List<ProjectTypeCatalogItem> projectTypes;
  final String? selectedProjectTypeId;
  final ValueChanged<String>? onProjectTypeChanged;
  final bool showCatalogWarning;
  final bool universeLocked;
  final bool projectDataLocked;

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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: RemaColors.surfaceLow),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 18, color: RemaColors.primaryDark),
                const SizedBox(width: 10),
                Text(_formatDate(selectedDate)),
                const Spacer(),
                Text(
                  'Bloqueada',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _UnderlinedField(
            label: 'Clave proyecto',
            controller: projectKeyController,
            enabled: !projectDataLocked,
          ),
          const SizedBox(height: 20),
          _UnderlinedField(
            label: 'Nombre del proyecto',
            controller: projectNameController,
            enabled: !projectDataLocked,
          ),
          const SizedBox(height: 20),
          _UnderlinedField(
            label: 'Cliente',
            controller: clientController,
            suffixIcon: Icons.person_search,
            onSuffixTap: projectDataLocked ? null : onClientTap,
            enabled: !projectDataLocked,
          ),
          if (projectDataLocked) ...[
            const SizedBox(height: 8),
            Text(
              'Cliente, clave y nombre del proyecto bloqueados hasta finalizar el levantamiento activo.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: RemaColors.onSurfaceVariant,
                  ),
            ),
          ],
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: selectedUniverseId,
            decoration: InputDecoration(
              labelText: universeLocked ? 'Universo (bloqueado por levantamiento activo)' : 'Universo',
            ),
            items: [
              for (final universe in universes)
                DropdownMenuItem<String>(
                  value: universe.id,
                  child: Text(universe.name),
                ),
            ],
            onChanged: onUniverseChanged == null
                ? null
                : (value) {
                    if (value != null) {
                      onUniverseChanged!(value);
                    }
                  },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: selectedProjectTypeId,
            decoration: const InputDecoration(labelText: 'Tipo de proyecto'),
            items: [
              for (final projectType in projectTypes)
                DropdownMenuItem<String>(
                  value: projectType.id,
                  child: Text(projectType.name),
                ),
            ],
            onChanged: onProjectTypeChanged == null
                ? null
                : (value) {
                    if (value != null) {
                      onProjectTypeChanged!(value);
                    }
                  },
          ),
          if (showCatalogWarning) ...[
            const SizedBox(height: 12),
            Text(
              'Algunos catalogos no cargaron. Se usara fallback local cuando aplique.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: RemaColors.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

String _formatDate(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  final year = value.year.toString();
  return '$day/$month/$year';
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
  });

  final TextEditingController addressController;

  @override
  Widget build(BuildContext context) {
    return RemaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RemaSectionHeader(title: 'Ubicacion'),
          const SizedBox(height: 24),
          _UnderlinedField(
            label: 'Direccion completa',
            controller: addressController,
          ),
          const SizedBox(height: 12),
          Text(
            'Mapa y georreferencia deshabilitados temporalmente.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _DescriptionPanel extends StatelessWidget {
  const _DescriptionPanel({
    required this.notesController,
  });

  final TextEditingController notesController;

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
          const SizedBox(height: 12),
          Text(
            'Esta descripcion se guarda solo como apoyo interno para preparar la cotizacion.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({required this.onQuote, required this.onFinish});

  final VoidCallback? onQuote;
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
    this.enabled = true,
    this.suffixIcon,
    this.onSuffixTap,
    this.hintText,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;
  final IconData? suffixIcon;
  final VoidCallback? onSuffixTap;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: label),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          enabled: enabled,
          decoration: InputDecoration(
            hintText: hintText ?? 'Ingresa $label',
            suffixIcon: suffixIcon != null
                ? onSuffixTap != null
                    ? IconButton(icon: Icon(suffixIcon), onPressed: onSuffixTap)
                    : Icon(suffixIcon)
                : null,
          ),
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
    final effectiveItems = items.contains(value) ? items : [value, ...items];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: label),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: value,
          items: [
            for (final item in effectiveItems)
              DropdownMenuItem<String>(
                value: item,
                child: Text(item),
              ),
          ],
          onChanged: (selected) {
            if (selected != null) {
              onChanged(selected);
            }
          },
        ),
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

// ─── Client selector dialog ───────────────────────────────────────────────────

class _ClientSelectorDialog extends StatefulWidget {
  const _ClientSelectorDialog();

  @override
  State<_ClientSelectorDialog> createState() => _ClientSelectorDialogState();
}

class _ClientSelectorDialogState extends State<_ClientSelectorDialog> {
  final _searchController = TextEditingController();
  List<ClientRecord> _all = const [];
  List<ClientRecord> _filtered = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadClients() async {
    final base = List<ClientRecord>.from(mockClients);
    final supabase = SupabaseBootstrap.client;
    if (supabase != null) {
      try {
        final rows = await supabase
            .from('clients')
            .select('id, business_name, email, phone, address_line, city')
            .order('business_name');
        final knownIds = base.map((c) => c.id).toSet();
        for (final row in rows) {
          final id = (row['id'] as String? ?? '').trim();
          final name = (row['business_name'] as String? ?? '').trim();
          if (id.isEmpty || name.isEmpty || knownIds.contains(id)) {
            continue;
          }
          final addr = [
            row['address_line'] as String? ?? '',
            row['city'] as String? ?? '',
          ].where((s) => s.isNotEmpty).join(', ');
          base.add(ClientRecord(
            id: id,
            name: name,
            sector: 'Cliente',
            badge: 'Activo',
            activeProjects: '00',
            months: '--',
            icon: Icons.apartment,
            contactEmail: (row['email'] as String? ?? '').trim(),
            phone: (row['phone'] as String? ?? '').trim(),
            address: addr.isEmpty ? 'Sin dirección' : addr,
            responsibles: const [],
          ));
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _all = base;
      _filtered = base;
      _isLoading = false;
    });
  }

  void _onSearch(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty ? _all : [for (final c in _all) if (c.name.toLowerCase().contains(q)) c];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 480,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Text('Seleccionar cliente', style: Theme.of(context).textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Buscar por nombre',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: _onSearch,
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filtered.isEmpty
                      ? const Center(child: Text('Sin resultados'))
                      : ListView.builder(
                          itemCount: _filtered.length,
                          itemBuilder: (ctx, i) {
                            final c = _filtered[i];
                            return ListTile(
                              leading: Icon(c.icon),
                              title: Text(c.name),
                              subtitle: Text(c.sector),
                              onTap: () => Navigator.of(ctx).pop(c),
                            );
                          },
                        ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 16, 12),
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
