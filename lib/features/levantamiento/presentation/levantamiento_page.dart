import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/rema_colors.dart';
import '../../../core/utils/image_optimizer.dart';
import '../../../core/utils/rema_feedback.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/rema_panels.dart';
import '../../../core/config/supabase_bootstrap.dart';
import '../../clientes/data/client_metadata_repository.dart';
import '../../cotizaciones/domain/concept_generation.dart';
import '../../cotizaciones/domain/quote_models.dart';
import '../../cotizaciones/presentation/concepts_catalog_controller.dart';
import '../../cotizaciones/presentation/quotes_controller.dart';
import '../../clientes/presentation/clientes_mock_data.dart';
import 'levantamiento_state.dart';

class LevantamientoPage extends ConsumerStatefulWidget {
  const LevantamientoPage({super.key, this.initialClientId});

  final String? initialClientId;

  @override
  ConsumerState<LevantamientoPage> createState() => _LevantamientoPageState();
}

class _LevantamientoPageState extends ConsumerState<LevantamientoPage> {
  final _metadataRepository = ClientMetadataRepository();
  final _projectKeyController = TextEditingController();
  final _projectNameController = TextEditingController();
  final _clientController = TextEditingController();
  final _addressController = TextEditingController();
  final _notesController = TextEditingController();
  List<ClientRecord> _clientOptions = const [];
  bool _isLoadingClients = false;
  String? _pendingClientIdFromRoute;
  String? _clientErrorText;

  DateTime _selectedDate = DateTime.now();
  String? _selectedClientId;
  String? _selectedProjectId;
  String? _selectedUniverseId;
  String? _selectedProjectTypeId;
  bool _isCreatingQuote = false;
  bool _isProcessingPhotos = false;
  final List<_PickedMedia> _photos = [];
  ProviderSubscription<ActiveLevantamientoSession?>? _activeSessionSubscription;

  @override
  void initState() {
    super.initState();
    _pendingClientIdFromRoute = widget.initialClientId?.trim();
    final active = ref.read(activeLevantamientoProvider);
    final draft = ref.read(levantamientoDraftProvider);

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
      if (active.evidencePreviewList.isNotEmpty) {
        _photos.addAll([
          for (var index = 0; index < active.evidencePreviewList.length; index++)
            _PickedMedia(
              name: 'Evidencia ${index + 1}',
              size: active.evidencePreviewList[index].length,
              bytes: active.evidencePreviewList[index],
            ),
        ]);
      }
      if (active.entries.isNotEmpty) {
        _notesController.text = active.entries.last.description;
      }
    } else if (draft != null) {
      if (draft.projectKey?.isNotEmpty == true) {
        _projectKeyController.text = draft.projectKey!;
      }
      if (draft.projectName?.isNotEmpty == true) {
        _projectNameController.text = draft.projectName!;
      }
      if (draft.clientName?.isNotEmpty == true) {
        _clientController.text = draft.clientName!;
      }
      if (draft.address?.isNotEmpty == true) {
        _addressController.text = draft.address!;
      }
      if (draft.notes?.isNotEmpty == true) {
        _notesController.text = draft.notes!;
      }
      _selectedClientId = draft.clientId;
      _selectedUniverseId = draft.universeId;
      _selectedProjectTypeId = draft.projectTypeId;
      if (draft.photos.isNotEmpty) {
        _photos.addAll([
          for (final photo in draft.photos)
            _PickedMedia(
              name: photo.name,
              size: photo.size,
              bytes: photo.bytes,
            ),
        ]);
      }
    }

    _projectKeyController.addListener(_persistDraftSnapshot);
    _projectNameController.addListener(_persistDraftSnapshot);
    _addressController.addListener(_persistDraftSnapshot);
    _notesController.addListener(_persistDraftSnapshot);

    _activeSessionSubscription = ref.listenManual<ActiveLevantamientoSession?>(
      activeLevantamientoProvider,
      (previous, next) {
        if (previous != null && previous.isActive && next == null) {
          _resetForNewSurvey();
        }
      },
    );

    _loadClientOptions();
  }

  @override
  void didUpdateWidget(covariant LevantamientoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextClientId = widget.initialClientId?.trim();
    final oldClientId = oldWidget.initialClientId?.trim();
    if (nextClientId != null && nextClientId.isNotEmpty && nextClientId != oldClientId) {
      _pendingClientIdFromRoute = nextClientId;
      _selectClientById(nextClientId);
    }
  }

  @override
  void dispose() {
    _activeSessionSubscription?.close();
    _projectKeyController.removeListener(_persistDraftSnapshot);
    _projectNameController.removeListener(_persistDraftSnapshot);
    _addressController.removeListener(_persistDraftSnapshot);
    _notesController.removeListener(_persistDraftSnapshot);
    _projectKeyController.dispose();
    _projectNameController.dispose();
    _clientController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _resetForNewSurvey() {
    if (!mounted) {
      return;
    }

    setState(() {
      _projectKeyController.clear();
      _projectNameController.clear();
      _clientController.clear();
      _addressController.clear();
      _notesController.clear();
      _selectedClientId = null;
      _selectedProjectId = null;
      _selectedUniverseId = null;
      _selectedProjectTypeId = null;
      _clientErrorText = null;
      _photos.clear();
    });
  }

  bool _hasStructuredKeyContext() {
    return (_selectedClientId ?? '').trim().isNotEmpty &&
        (_selectedProjectTypeId ?? '').trim().isNotEmpty;
  }

  Future<void> _refreshStructuredProjectKeyIfNeeded({
    bool announce = false,
  }) async {
    final active = ref.read(activeLevantamientoProvider);
    if (_selectedProjectId != null || (active != null && active.isActive)) {
      return;
    }

    final current = _projectKeyController.text.trim().toUpperCase();
    if (current.startsWith('RM-')) {
      return;
    }

    if (!_hasStructuredKeyContext()) {
      if (current.startsWith('PRJ')) {
        _projectKeyController.clear();
        _persistDraftSnapshot();
      }
      return;
    }

    final generated = await _ensureProjectKey();
    if (!mounted || generated.trim().isEmpty || !announce) {
      return;
    }

    showRemaMessage(context, 'Folio de proyecto generado: ${generated.trim()}');
  }

  Future<void> _pickPhotos() async {
    const maxPhotosPerEntry = 2;
    final remaining = maxPhotosPerEntry - _photos.length;
    if (remaining <= 0) {
      showRemaMessage(context, 'Maximo 2 fotos por cada descripcion.');
      return;
    }

    setState(() => _isProcessingPhotos = true);
    try {
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
      final rejectedMessages = <String>[];
      for (final file in acceptedFiles) {
        final bytes = file.bytes;
        if (bytes == null || bytes.isEmpty) {
          continue;
        }
        try {
          final optimized = await optimizeImageForDocument(
            inputBytes: bytes,
            fileName: file.name,
            profile: ImageOptimizationProfile.gridDocument,
          );
          normalizedMedia.add(
            _PickedMedia(
              name: optimized.fileName,
              bytes: optimized.bytes,
              size: optimized.bytes.length,
              mimeType: optimized.mimeType,
            ),
          );
        } on ImageOptimizationException catch (error) {
          rejectedMessages.add('${file.name}: ${error.message}');
        }
      }

      if (normalizedMedia.isNotEmpty) {
        setState(() {
          _photos.addAll(normalizedMedia);
        });
        _persistDraftSnapshot();
      }

      if (acceptedFiles.length < selectedFiles.length) {
        showRemaMessage(context, 'Solo se permiten 2 fotos por descripcion.');
        return;
      }
      if (normalizedMedia.isNotEmpty && rejectedMessages.isEmpty) {
        showRemaMessage(
          context,
          'Se agregaron ${normalizedMedia.length} imagenes optimizadas al levantamiento.',
        );
        return;
      }
      if (normalizedMedia.isNotEmpty && rejectedMessages.isNotEmpty) {
        showRemaMessage(
          context,
          'Se agregaron ${normalizedMedia.length} imagenes optimizadas. ${rejectedMessages.first}',
        );
        return;
      }
      if (rejectedMessages.isNotEmpty) {
        showRemaMessage(context, rejectedMessages.first);
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingPhotos = false);
      }
    }
  }

  void _persistDraftSnapshot() {
    ref.read(levantamientoDraftProvider.notifier).update(
          projectKey: _projectKeyController.text,
          projectName: _projectNameController.text,
          clientId: _selectedClientId,
          clientName: _clientController.text,
          address: _addressController.text,
          notes: _notesController.text,
          universeId: _selectedUniverseId,
          projectTypeId: _selectedProjectTypeId,
          photos: [
            for (final photo in _photos)
              if (photo.bytes != null && photo.bytes!.isNotEmpty)
                DraftLevantamientoPhoto(
                  name: photo.name,
                  size: photo.size,
                  bytes: photo.bytes!,
                ),
          ],
        );
  }

  void _removePhoto(_PickedMedia photo) {
    setState(() => _photos.remove(photo));
    _persistDraftSnapshot();
    showRemaMessage(context, 'Se elimino ${photo.name}.');
  }

  void _prepareForNextCapture() {
    if (!mounted) {
      return;
    }
    setState(() {
      _notesController.clear();
      _photos.clear();
      _clientErrorText = null;
    });
    _persistDraftSnapshot();
  }

  Future<List<_PickedMedia>> _pickEvidenceForEdit({required int maxPhotos}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );

    if (!mounted || result == null || result.files.isEmpty) {
      return const <_PickedMedia>[];
    }

    final selectedFiles = result.files.take(maxPhotos).toList();
    final normalizedMedia = <_PickedMedia>[];
    for (final file in selectedFiles) {
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        continue;
      }
      try {
        final optimized = await optimizeImageForDocument(
          inputBytes: bytes,
          fileName: file.name,
          profile: ImageOptimizationProfile.gridDocument,
        );
        normalizedMedia.add(
          _PickedMedia(
            name: optimized.fileName,
            bytes: optimized.bytes,
            size: optimized.bytes.length,
            mimeType: optimized.mimeType,
          ),
        );
      } on ImageOptimizationException catch (error) {
        if (mounted) {
          showRemaMessage(context, '${file.name}: ${error.message}');
        }
      }
    }
    return normalizedMedia;
  }

  List<String> _existingEvidencePaths(SurveyEntryRecord entry) {
    if (entry.evidencePaths.isNotEmpty) {
      return entry.evidencePaths;
    }
    return [
      for (final meta in entry.evidenceMetadata)
        if (meta.objectPath.trim().isNotEmpty) meta.objectPath.trim(),
    ];
  }

  Future<void> _editCapturedEntry({
    required String projectId,
    required String? quoteId,
    required SurveyEntryRecord entry,
  }) async {
    final entryId = entry.id;
    if (entryId == null || entryId.trim().isEmpty) {
      showRemaMessage(context, 'Esta entrada aun no tiene identificador para editarse.');
      return;
    }

    final descriptionController = TextEditingController(text: entry.description);
    final replacementPhotos = <_PickedMedia>[];
    var clearEvidence = false;

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Editar anotacion'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: descriptionController,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: 'Descripcion',
                        hintText: 'Actualiza la descripcion del levantamiento',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Evidencias actuales: ${entry.evidencePreviewList.length}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final bytes in entry.evidencePreviewList)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: SizedBox(
                              width: 56,
                              height: 56,
                              child: Image.memory(bytes, fit: BoxFit.cover),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      value: clearEvidence,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Eliminar evidencias actuales'),
                      onChanged: (value) {
                        setDialogState(() {
                          clearEvidence = value ?? false;
                          if (clearEvidence) {
                            replacementPhotos.clear();
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      onPressed: clearEvidence
                          ? null
                          : () async {
                              final selected = await _pickEvidenceForEdit(maxPhotos: 2);
                              if (selected.isEmpty) {
                                return;
                              }
                              setDialogState(() {
                                replacementPhotos
                                  ..clear()
                                  ..addAll(selected.take(2));
                              });
                            },
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(
                        replacementPhotos.isEmpty
                            ? 'Reemplazar evidencias (opcional)'
                            : 'Reemplazar evidencias (${replacementPhotos.length})',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Guardar cambios'),
                ),
              ],
            );
          },
        );
      },
    );

    if (accepted != true) {
      descriptionController.dispose();
      return;
    }

    final replacementInputs = replacementPhotos
        .where((photo) => photo.bytes != null && photo.bytes!.isNotEmpty)
        .map(
          (photo) => SurveyEvidenceInput(
            bytes: photo.bytes!,
            originalName: photo.name,
            fileSizeBytes: photo.size,
            mimeType: photo.mimeType ?? _guessMimeType(photo.name),
          ),
        )
        .toList();

    final updated = await ref.read(quotesProvider.notifier).updateSurveyEntry(
          projectId: projectId,
          entryId: entryId,
          quoteId: quoteId,
          description: descriptionController.text.trim(),
          replacementEvidenceInputs:
              replacementInputs.isEmpty && !clearEvidence ? null : replacementInputs,
          clearEvidence: clearEvidence,
          existingEvidencePaths: _existingEvidencePaths(entry),
        );

    descriptionController.dispose();

    if (!mounted) {
      return;
    }

    ref.invalidate(projectSurveyEntriesProvider(projectId));
    if (updated == null) {
      showRemaMessage(context, 'No se pudo actualizar la anotacion.');
      return;
    }
    showRemaMessage(context, 'Anotacion actualizada correctamente.');
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

    if (active != null && active.isActive && active.quoteId != null) {
      await _syncActiveQuoteContextAndEntries(active);
      _prepareForNextCapture();
      if (!mounted) {
        return;
      }
      showRemaMessage(
        context,
        'Entrada agregada a la cotizacion activa. Captura la siguiente descripcion y evidencia.',
        label: 'Abrir presupuesto',
        onAction: () => context.go('/presupuesto/${active.quoteId}'),
      );
      return;
    }

    final resolvedClient = _resolveValidatedClientSelection();
    if (resolvedClient == null) {
      showRemaMessage(
        context,
        'Selecciona un cliente existente o crea uno nuevo antes de continuar.',
      );
      return;
    }

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
      ref.read(levantamientoDraftProvider.notifier).clear();
      _prepareForNextCapture();

      showRemaMessage(
        context,
        'Levantamiento asociado a ${quote.quoteNumber}. Clave bloqueada y formulario listo para la siguiente entrada.',
        label: 'Abrir presupuesto',
        onAction: () => context.go('/presupuesto/${quote.id}'),
      );
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
    if (current.startsWith('RM-')) {
      return current;
    }

    try {
      final key = await ref.read(quotesProvider.notifier).reserveProjectKey(
            clientId: _selectedClientId,
            projectTypeId: _selectedProjectTypeId,
          );
      if (!mounted) {
        return key;
      }
      _projectKeyController.text = key;
      return key;
    } catch (_) {
      if (current.isNotEmpty) {
        return current;
      }
      final fallback = 'PRJ${DateTime.now().millisecondsSinceEpoch}';
      if (mounted && _projectKeyController.text.trim().isEmpty) {
        _projectKeyController.text = fallback;
      }
      _persistDraftSnapshot();
      return fallback;
    }
  }

  Future<void> _loadClientOptions() async {
    setState(() => _isLoadingClients = true);
    final base = <ClientRecord>[];
    final supabase = SupabaseBootstrap.client;
    if (supabase != null) {
      try {
        List<dynamic> rows;
        try {
          rows = await supabase
              .from('clients')
              .select('id, business_name, contact_name, notes, email, phone, address_line, city')
              .order('business_name');
        } catch (_) {
          rows = await supabase
              .from('clients')
              .select('id, business_name, notes, email, phone, address_line, city')
              .order('business_name');
        }
        final knownIds = <String>{};
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
          final contactName = _metadataRepository.resolveContactName(
            contactName: row['contact_name'] as String?,
            notes: row['notes'] as String?,
          );
          base.add(
            ClientRecord(
              id: id,
              name: name,
              contactName: contactName,
              sector: 'Cliente',
              badge: 'Activo',
              activeProjects: '00',
              months: '--',
              icon: Icons.apartment,
              contactEmail: (row['email'] as String? ?? '').trim(),
              phone: (row['phone'] as String? ?? '').trim(),
              address: addr.isEmpty ? 'Sin direccion' : addr,
              responsibles: const [],
            ),
          );
        }
      } catch (_) {}
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _clientOptions = base;
      _isLoadingClients = false;
    });
    final pendingClientId = _pendingClientIdFromRoute;
    if (pendingClientId != null && pendingClientId.isNotEmpty) {
      _pendingClientIdFromRoute = null;
      await _selectClientById(pendingClientId);
    }
  }

  Future<void> _selectClientById(String clientId) async {
    final local = _clientOptions.where((item) => item.id == clientId).cast<ClientRecord?>().firstWhere(
          (item) => item != null,
          orElse: () => null,
        );
    if (local != null) {
      _applySelectedClient(local);
      return;
    }

    final supabase = SupabaseBootstrap.client;
    if (supabase == null || !_isUuid(clientId)) {
      return;
    }

    try {
      Map<String, dynamic>? row;
      try {
        row = await supabase
            .from('clients')
            .select('id, business_name, contact_name, notes, email, phone, address_line, city')
            .eq('id', clientId)
            .maybeSingle();
      } catch (_) {
        row = await supabase
            .from('clients')
            .select('id, business_name, notes, email, phone, address_line, city')
            .eq('id', clientId)
            .maybeSingle();
      }
      if (!mounted || row == null) {
        return;
      }
      final contactName = _metadataRepository.resolveContactName(
        contactName: row['contact_name'] as String?,
        notes: row['notes'] as String?,
      );
      final client = ClientRecord(
        id: row['id'] as String? ?? clientId,
        name: (row['business_name'] as String? ?? '').trim(),
        contactName: contactName,
        sector: 'Cliente',
        badge: 'Activo',
        activeProjects: '00',
        months: '--',
        icon: Icons.apartment,
        contactEmail: (row['email'] as String? ?? '').trim(),
        phone: (row['phone'] as String? ?? '').trim(),
        address: [
          row['address_line'] as String? ?? '',
          row['city'] as String? ?? '',
        ].where((s) => s.isNotEmpty).join(', ').trim().isEmpty
            ? 'Sin direccion'
            : [
                row['address_line'] as String? ?? '',
                row['city'] as String? ?? '',
              ].where((s) => s.isNotEmpty).join(', '),
        responsibles: const [],
      );
      setState(() {
        if (_clientOptions.every((item) => item.id != client.id)) {
          _clientOptions = [..._clientOptions, client];
        }
      });
      _applySelectedClient(client);
    } catch (_) {}
  }

  void _applySelectedClient(ClientRecord selected) {
    if (!mounted) {
      return;
    }
    final active = ref.read(activeLevantamientoProvider);
    final address = selected.address.trim();
    setState(() {
      _clientController.text = selected.name;
      _selectedClientId = selected.id;
      _clientErrorText = null;
      if (address.isNotEmpty && address.toLowerCase() != 'sin direccion') {
        _addressController.text = address;
      }
    });
    _persistDraftSnapshot();

    final existingKey = _projectKeyController.text.trim();
    final sessionKey = active?.projectKey?.trim() ?? '';
    if (existingKey.isEmpty && sessionKey.isNotEmpty) {
      _projectKeyController.text = sessionKey;
    } else {
      _refreshStructuredProjectKeyIfNeeded(announce: existingKey.isEmpty);
    }

    if (active != null && active.isActive) {
      ref.read(activeLevantamientoProvider.notifier).updateSnapshot(
        clientId: selected.id,
        clientName: selected.name,
        address: address.isNotEmpty ? address : null,
        projectKey: _projectKeyController.text.trim(),
      );
    }
  }

  void _handleClientQueryChanged(String value) {
    _clientController.text = value;
    final current = _clientOptions.where((item) => item.id == _selectedClientId).cast<ClientRecord?>().firstWhere(
          (item) => item != null,
          orElse: () => null,
        );
    if (current != null && current.name != value) {
      setState(() {
        _selectedClientId = null;
        _selectedProjectId = null;
        _clientErrorText = null;
      });
      _refreshStructuredProjectKeyIfNeeded();
      return;
    }

    if (_clientErrorText != null) {
      setState(() => _clientErrorText = null);
    }
    _persistDraftSnapshot();
  }

  ClientRecord? _resolveValidatedClientSelection() {
    final selectedClientId = _selectedClientId?.trim();
    if (selectedClientId != null && selectedClientId.isNotEmpty) {
      final selected = _clientOptions.where((item) => item.id == selectedClientId).cast<ClientRecord?>().firstWhere(
            (item) => item != null,
            orElse: () => null,
          );
      if (selected != null) {
        if (_clientErrorText != null) {
          setState(() => _clientErrorText = null);
        }
        return selected;
      }
    }

    final typedValue = _normalizeClientLookup(_clientController.text);
    if (typedValue.isEmpty) {
      setState(() => _clientErrorText = 'Selecciona un cliente existente o crea uno nuevo.');
      return null;
    }

    final exactMatches = [
      for (final client in _clientOptions)
        if (_normalizeClientLookup(client.name) == typedValue ||
            _normalizeClientLookup(client.displayContactName) == typedValue)
          client,
    ];

    if (exactMatches.length == 1) {
      final match = exactMatches.first;
      _applySelectedClient(match);
      return match;
    }

    setState(() {
      _selectedClientId = null;
      _clientErrorText = exactMatches.isEmpty
          ? 'El cliente no existe. Seleccionalo de la lista o crea uno nuevo.'
          : 'Hay varias coincidencias. Selecciona el cliente desde la lista.';
    });
    return null;
  }

  String _normalizeClientLookup(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<void> _goToNewClient() async {
    final active = ref.read(activeLevantamientoProvider);
    final projectDataLocked = active != null && active.isActive && active.quoteId != null;
    if (projectDataLocked) {
      showRemaMessage(
        context,
        'Cliente bloqueado mientras la cotizacion en curso siga activa. Finaliza el levantamiento para editarlo.',
      );
      return;
    }
    final createdClientId = await context.push<String>('/nuevo-cliente?returnTo=pop');
    if (!mounted || createdClientId == null || createdClientId.trim().isEmpty) {
      return;
    }
    await _loadClientOptions();
    if (!mounted) {
      return;
    }
    await _selectClientById(createdClientId.trim());
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

    ref.read(activeLevantamientoProvider.notifier).clear();
    ref.read(levantamientoDraftProvider.notifier).clear();
    showRemaMessage(
      context,
      'Levantamiento finalizado. Se reinicio el formulario y se genero una nueva clave de proyecto.',
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
          mimeType: photo.mimeType ?? _guessMimeType(photo.name),
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

  List<ProjectTypeCatalogItem> _projectTypesForUniverse({
    required ConceptCatalogSnapshot? catalog,
    required String? universeId,
    required List<ProjectTypeCatalogItem> fallback,
  }) {
    if (catalog == null || universeId == null || universeId.trim().isEmpty) {
      return fallback;
    }

    final compatible = [
      for (final item in catalog.projectTypesForUniverse(universeId))
        if (fallback.any((allowed) => allowed.id == item.id)) item,
    ];
    return compatible.isNotEmpty ? compatible : fallback;
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
    required ConceptCatalogSnapshot? catalog,
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
      final compatibleProjectTypes = _projectTypesForUniverse(
        catalog: catalog,
        universeId: nextUniverseId,
        fallback: projectTypes,
      );
      if (nextProjectTypeId == null ||
          !compatibleProjectTypes.any((item) => item.id == nextProjectTypeId)) {
        nextProjectTypeId = compatibleProjectTypes.isNotEmpty
            ? compatibleProjectTypes.first.id
            : (projectTypes.isNotEmpty ? projectTypes.first.id : null);
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
      _persistDraftSnapshot();
    });
  }

  @override
  Widget build(BuildContext context) {
    final catalogState = ref.watch(conceptsCatalogProvider);
    final activeLevantamiento = ref.watch(activeLevantamientoProvider);
    final catalogSnapshot = catalogState.valueOrNull;
    final activeProjectId = activeLevantamiento?.projectId.trim() ?? '';
    final projectIdForEntries = activeProjectId.isNotEmpty
      ? activeProjectId
      : ((_selectedProjectId ?? '').trim().isNotEmpty ? _selectedProjectId!.trim() : null);
    final surveyEntriesAsync = projectIdForEntries == null
      ? const AsyncData<List<SurveyEntryRecord>>(<SurveyEntryRecord>[])
      : ref.watch(projectSurveyEntriesProvider(projectIdForEntries));

    final universes = catalogSnapshot?.universes ?? const <UniverseCatalogItem>[];
    final projectTypes = _allowedProjectTypes(
      catalogSnapshot?.projectTypes ?? const <ProjectTypeCatalogItem>[],
    );
    final availableProjectTypes = _projectTypesForUniverse(
      catalog: catalogSnapshot,
      universeId: _selectedUniverseId,
      fallback: projectTypes,
    );

    _primeSelections(
      catalog: catalogSnapshot,
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
            clientOptions: _clientOptions,
            isLoadingClients: _isLoadingClients,
            clientErrorText: _clientErrorText,
            selectedClientId: _selectedClientId,
            onClientChanged: _handleClientQueryChanged,
            onClientSelected: _applySelectedClient,
            onAddClient: _goToNewClient,
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
                    final compatibleProjectTypes = _projectTypesForUniverse(
                      catalog: catalogSnapshot,
                      universeId: value,
                      fallback: projectTypes,
                    );
                    setState(() {
                      _selectedUniverseId = value;
                      if (!compatibleProjectTypes.any(
                        (item) => item.id == _selectedProjectTypeId,
                      )) {
                        _selectedProjectTypeId = compatibleProjectTypes.isNotEmpty
                            ? compatibleProjectTypes.first.id
                            : null;
                      }
                    });
                    _persistDraftSnapshot();
                  },
            projectTypes: availableProjectTypes,
            selectedProjectTypeId: _selectedProjectTypeId,
            onProjectTypeChanged: universeLocked
                ? null
              : (value) {
                setState(() => _selectedProjectTypeId = value);
                _persistDraftSnapshot();
                _refreshStructuredProjectKeyIfNeeded();
                },
            showCatalogWarning: catalogState.hasError,
            universeLocked: universeLocked,
            projectDataLocked: projectDataLocked,
          );
          final media = _EvidencePanel(
            photos: _photos,
            isProcessing: _isProcessingPhotos,
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
              if (projectIdForEntries != null) ...[
                const SizedBox(height: 24),
                _CapturedEntriesPanel(
                  entriesAsync: surveyEntriesAsync,
                  onEdit: (entry) => _editCapturedEntry(
                    projectId: projectIdForEntries,
                    quoteId: activeLevantamiento?.quoteId,
                    entry: entry,
                  ),
                ),
              ],
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
    required this.clientOptions,
    required this.isLoadingClients,
    required this.clientErrorText,
    required this.selectedClientId,
    required this.onClientChanged,
    required this.onClientSelected,
    required this.onAddClient,
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
  final List<ClientRecord> clientOptions;
  final bool isLoadingClients;
  final String? clientErrorText;
  final String? selectedClientId;
  final ValueChanged<String> onClientChanged;
  final ValueChanged<ClientRecord> onClientSelected;
  final VoidCallback onAddClient;
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
          _ClientAutocompleteField(
            label: 'Cliente',
            valueText: clientController.text,
            clients: clientOptions,
            isLoading: isLoadingClients,
            errorText: clientErrorText,
            enabled: !projectDataLocked,
            selectedClientId: selectedClientId,
            onChanged: onClientChanged,
            onSelected: onClientSelected,
            onAddClient: onAddClient,
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
    required this.isProcessing,
    required this.onAddPhotos,
    required this.onRemove,
  });

  final List<_PickedMedia> photos;
  final bool isProcessing;
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
              _AddPhotoTile(
                isProcessing: isProcessing,
                onTap: isProcessing ? null : onAddPhotos,
              ),
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

class _CapturedEntriesPanel extends StatelessWidget {
  const _CapturedEntriesPanel({
    required this.entriesAsync,
    required this.onEdit,
  });

  final AsyncValue<List<SurveyEntryRecord>> entriesAsync;
  final ValueChanged<SurveyEntryRecord> onEdit;

  @override
  Widget build(BuildContext context) {
    return RemaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RemaSectionHeader(title: 'Anotaciones capturadas'),
          const SizedBox(height: 16),
          entriesAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            ),
            error: (error, _) => Text(
              'No se pudieron cargar las anotaciones: $error',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            data: (entries) {
              if (entries.isEmpty) {
                return Text(
                  'Todavia no hay anotaciones registradas para este levantamiento.',
                  style: Theme.of(context).textTheme.bodySmall,
                );
              }

              return Column(
                children: [
                  for (var index = 0; index < entries.length; index++) ...[
                    _CapturedEntryTile(
                      index: index + 1,
                      entry: entries[index],
                      onEdit: () => onEdit(entries[index]),
                    ),
                    if (index < entries.length - 1) const Divider(height: 24),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CapturedEntryTile extends StatelessWidget {
  const _CapturedEntryTile({
    required this.index,
    required this.entry,
    required this.onEdit,
  });

  final int index;
  final SurveyEntryRecord entry;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final title = 'Entrada $index';
    final createdAt = entry.createdAt;
    final caption = createdAt == null
        ? title
        : '$title · ${createdAt.day.toString().padLeft(2, '0')}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.year}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                caption,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            TextButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Editar'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          entry.description.trim().isEmpty
              ? 'Sin descripcion.'
              : entry.description.trim(),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (entry.evidencePreviewList.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final bytes in entry.evidencePreviewList)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: Image.memory(bytes, fit: BoxFit.cover),
                  ),
                ),
            ],
          ),
        ],
      ],
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
  const _AddPhotoTile({required this.onTap, required this.isProcessing});

  final VoidCallback? onTap;
  final bool isProcessing;

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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isProcessing)
              const SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            else
              const Icon(Icons.add_a_photo_outlined, size: 32, color: RemaColors.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(isProcessing ? 'Cargando...' : 'Anadir'),
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

class _ClientAutocompleteField extends StatelessWidget {
  const _ClientAutocompleteField({
    required this.label,
    required this.valueText,
    required this.clients,
    required this.isLoading,
    required this.errorText,
    required this.enabled,
    required this.selectedClientId,
    required this.onChanged,
    required this.onSelected,
    required this.onAddClient,
  });

  final String label;
  final String valueText;
  final List<ClientRecord> clients;
  final bool isLoading;
  final String? errorText;
  final bool enabled;
  final String? selectedClientId;
  final ValueChanged<String> onChanged;
  final ValueChanged<ClientRecord> onSelected;
  final VoidCallback onAddClient;

  @override
  Widget build(BuildContext context) {
    final currentClient = clients.where((item) => item.id == selectedClientId).cast<ClientRecord?>().firstWhere(
          (item) => item != null,
          orElse: () => null,
        );
    final hasMatches = valueText.trim().isEmpty || clients.any((item) => item.matchesSearchQuery(valueText));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: label),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 720;
            final field = Autocomplete<ClientRecord>(
              key: ValueKey('${selectedClientId ?? ''}::$valueText::${clients.length}'),
              initialValue: TextEditingValue(text: valueText),
              displayStringForOption: (option) => option.name,
              optionsBuilder: (textEditingValue) {
                final query = textEditingValue.text.trim();
                if (!enabled) {
                  return const Iterable<ClientRecord>.empty();
                }
                final ranked = [
                  for (final client in clients)
                    if (client.matchesSearchQuery(query)) client,
                ];
                ranked.sort((left, right) {
                  final leftStarts = left.name.toLowerCase().startsWith(query.toLowerCase()) ? 0 : 1;
                  final rightStarts = right.name.toLowerCase().startsWith(query.toLowerCase()) ? 0 : 1;
                  if (leftStarts != rightStarts) {
                    return leftStarts.compareTo(rightStarts);
                  }
                  return left.name.compareTo(right.name);
                });
                return ranked.take(8);
              },
              onSelected: onSelected,
              fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
                if (textController.text != valueText) {
                  textController.value = TextEditingValue(
                    text: valueText,
                    selection: TextSelection.collapsed(offset: valueText.length),
                  );
                }
                return TextField(
                  controller: textController,
                  focusNode: focusNode,
                  enabled: enabled,
                  onChanged: onChanged,
                  decoration: InputDecoration(
                    hintText: 'Busca por razon social o nombre de contacto',
                    errorText: errorText,
                    suffixIcon: isLoading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : const Icon(Icons.search),
                  ),
                );
              },
              optionsViewBuilder: (context, onOptionSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(8),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 280),
                      child: ListView(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        children: [
                          for (final option in options)
                            ListTile(
                              title: Text(option.name),
                              subtitle: Text(
                                option.displayContactName.isEmpty
                                    ? option.address
                                    : '${option.displayContactName} | ${option.address}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => onOptionSelected(option),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  field,
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: enabled ? onAddClient : null,
                    icon: const Icon(Icons.add_business_outlined),
                    label: const Text('Nuevo cliente'),
                  ),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: field),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: enabled ? onAddClient : null,
                  icon: const Icon(Icons.add_business_outlined),
                  label: const Text('Nuevo cliente'),
                ),
              ],
            );
          },
        ),
        if (currentClient != null && currentClient.displayContactName.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Contacto: ${currentClient.displayContactName}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ] else if (!isLoading && enabled && !hasMatches && valueText.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Sin coincidencias. Puedes crear un cliente nuevo.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: RemaColors.onSurfaceVariant,
                ),
          ),
        ],
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
    this.mimeType,
  });

  final String name;
  final int size;
  final Uint8List? bytes;
  final String? mimeType;
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
    final base = <ClientRecord>[];
    final supabase = SupabaseBootstrap.client;
    if (supabase != null) {
      try {
        final rows = await supabase
            .from('clients')
            .select('id, business_name, email, phone, address_line, city')
            .order('business_name');
        final mergedByName = <String, ClientRecord>{};
        for (final row in rows) {
          final id = (row['id'] as String? ?? '').trim();
          final name = (row['business_name'] as String? ?? '').trim();
          if (id.isEmpty || name.isEmpty) {
            continue;
          }
          final addr = [
            row['address_line'] as String? ?? '',
            row['city'] as String? ?? '',
          ].where((s) => s.isNotEmpty).join(', ');
          mergedByName[_normalizedClientKey(name)] = ClientRecord(
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
          );
        }
        base
          ..clear()
          ..addAll(mergedByName.values);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _all = base;
      _filtered = base;
      _isLoading = false;
    });
  }

  String _normalizedClientKey(String value) => value.trim().toLowerCase();

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
