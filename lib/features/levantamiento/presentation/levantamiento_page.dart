import 'package:file_picker/file_picker.dart';
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
  static const List<String> _defaultResponsibles = [
    'Arq. Daniel M.',
    'Arq. Sofia R.',
    'Arq. Elena G.',
  ];

  final _projectKeyController = TextEditingController();
  final _projectNameController = TextEditingController(text: 'Residencia Olivos');
  final _clientController = TextEditingController(text: 'Ing. Roberto Mendez');
  final _addressController = TextEditingController(
    text: 'Av. de la Reforma 222, Juarez, Cuauhtemoc, CDMX',
  );
  final _notesController = TextEditingController(
    text: 'Describa el estado actual del terreno, accesos, servicios disponibles y requerimientos especificos del cliente detectados durante la visita.',
  );

  DateTime _selectedDate = DateTime.now();
  String _selectedArchitect = _defaultResponsibles.first;
  List<String> _responsibleOptions = List<String>.from(_defaultResponsibles);
  String? _selectedClientId;
  String? _boundProjectId;
  String? _selectedProjectId;
  String? _selectedUniverseId;
  String? _selectedProjectTypeId;
  bool _isCreatingQuote = false;
  bool _isCreatingProject = false;
  final List<_PickedMedia> _photos = [];

  @override
  void initState() {
    super.initState();
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

  Future<void> _goToQuote() async {
    final active = ref.read(activeLevantamientoProvider);
    final selectedUniverseId = _selectedUniverseId;
    final selectedProjectId = _selectedProjectId;
    final selectedProjectTypeId = _selectedProjectTypeId;

    if (selectedUniverseId == null || selectedProjectId == null || selectedProjectTypeId == null) {
      showRemaMessage(context, 'Selecciona proyecto, universo y tipo de proyecto para continuar.');
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
      context.go('/presupuesto/${active.quoteId}');
      return;
    }

    setState(() => _isCreatingQuote = true);
    try {
      final projectName = _projectNameController.text.trim();
      final manager = _selectedArchitect.trim();
      final address = _addressController.text.trim();
      final notes = _notesController.text.trim();
      final projectKey = await _ensureProjectKey();

      await ref.read(quotesProvider.notifier).updateProjectContext(
            projectId: selectedProjectId,
            name: projectName.isEmpty ? 'Proyecto sin nombre' : projectName,
            managerName: manager,
            address: address,
            description: notes,
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
          );

      showRemaMessage(context, 'Levantamiento asociado a ${quote.quoteNumber}.');
      context.go('/presupuesto/${quote.id}');
    } finally {
      if (mounted) {
        setState(() => _isCreatingQuote = false);
      }
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
    final selected = await showDialog<ClientRecord>(
      context: context,
      builder: (_) => const _ClientSelectorDialog(),
    );
    if (selected != null && mounted) {
      setState(() {
        _clientController.text = selected.name;
        _selectedClientId = selected.id;
      });
      await _loadResponsiblesForClient(
        clientId: selected.id,
        localFallback: selected.responsibles,
      );
    }
  }

  Future<void> _loadResponsiblesForClient({
    required String? clientId,
    List<ClientResponsibleRecord> localFallback = const [],
  }) async {
    final localNames = [
      for (final record in localFallback)
        if (record.fullName.trim().isNotEmpty) record.fullName.trim(),
    ];

    if (localNames.isNotEmpty || clientId == null || clientId.isEmpty) {
      _applyResponsibles(localNames);
      return;
    }

    if (!_isUuid(clientId) || SupabaseBootstrap.client == null) {
      _applyResponsibles(const []);
      return;
    }

    try {
      final rows = await SupabaseBootstrap.client!
          .from('client_responsibles')
          .select('full_name')
          .eq('client_id', clientId)
          .order('created_at', ascending: true);
      final names = [
        for (final row in rows)
          ((row['full_name'] as String?) ?? '').trim(),
      ].where((item) => item.isNotEmpty).toList();
      _applyResponsibles(names);
    } catch (_) {
      _applyResponsibles(const []);
    }
  }

  void _applyResponsibles(List<String> values) {
    final next = values.isEmpty ? List<String>.from(_defaultResponsibles) : values;
    if (!mounted) {
      return;
    }
    setState(() {
      _responsibleOptions = next;
      if (!next.contains(_selectedArchitect)) {
        _selectedArchitect = next.first;
      }
    });
  }

  Future<void> _handleProjectChanged(String projectId, List<ProjectLookup> projects) async {
    setState(() => _selectedProjectId = projectId);
    await _bindProjectDetails(projectId, projects);
  }

  Future<void> _bindProjectDetails(String? projectId, List<ProjectLookup> projects) async {
    if (projectId == null || _boundProjectId == projectId) {
      return;
    }
    _boundProjectId = projectId;

    ProjectLookup? selected;
    for (final project in projects) {
      if (project.id == projectId) {
        selected = project;
        break;
      }
    }
    if (selected == null) {
      return;
    }
    final selectedProject = selected;

    if (mounted) {
      setState(() {
        if (selectedProject.name.trim().isNotEmpty) {
          _projectNameController.text = selectedProject.name;
        }
        if ((selectedProject.siteAddress ?? '').trim().isNotEmpty) {
          _addressController.text = selectedProject.siteAddress!.trim();
        }
        if ((selectedProject.description ?? '').trim().isNotEmpty) {
          _notesController.text = selectedProject.description!.trim();
        }
        if ((selectedProject.managerName ?? '').trim().isNotEmpty) {
          _selectedArchitect = selectedProject.managerName!.trim();
        }
        _selectedClientId = selectedProject.clientId;
      });
    }

    if (_selectedClientId == null || _selectedClientId!.isEmpty) {
      _applyResponsibles(const []);
      return;
    }

    await _bindClientById(_selectedClientId!);
  }

  Future<void> _bindClientById(String clientId) async {
    final local = findClientById(clientId);
    if (local != null) {
      if (mounted) {
        setState(() => _clientController.text = local.name);
      }
      await _loadResponsiblesForClient(clientId: clientId, localFallback: local.responsibles);
      return;
    }

    if (!_isUuid(clientId) || SupabaseBootstrap.client == null) {
      await _loadResponsiblesForClient(clientId: clientId);
      return;
    }

    try {
      final row = await SupabaseBootstrap.client!
          .from('clients')
          .select('business_name')
          .eq('id', clientId)
          .maybeSingle();
      final name = ((row?['business_name'] as String?) ?? '').trim();
      if (mounted && name.isNotEmpty) {
        setState(() => _clientController.text = name);
      }
    } catch (_) {}

    await _loadResponsiblesForClient(clientId: clientId);
  }

  Future<void> _createProjectFromCurrentData() async {
    if (_selectedClientId == null || _selectedClientId!.trim().isEmpty) {
      showRemaMessage(context, 'Selecciona un cliente antes de crear el proyecto.');
      return;
    }

    setState(() => _isCreatingProject = true);
    try {
      final code = await _ensureProjectKey();
      final project = await ref.read(quotesProvider.notifier).createProject(
            input: NewProjectInput(
              code: code,
              name: _projectNameController.text.trim().isEmpty
                  ? 'Proyecto sin nombre'
                  : _projectNameController.text.trim(),
              clientId: _selectedClientId,
              siteAddress: _addressController.text.trim(),
              description: _notesController.text.trim(),
              managerName: _selectedArchitect.trim(),
            ),
          );

      if (!mounted) {
        return;
      }
      setState(() {
        _selectedProjectId = project.id;
        _boundProjectId = project.id;
      });
      ref.invalidate(quoteProjectsProvider);
      showRemaMessage(context, 'Proyecto ${project.code} creado y seleccionado.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      showRemaMessage(context, 'No se pudo crear el proyecto: $error');
    } finally {
      if (mounted) {
        setState(() => _isCreatingProject = false);
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

  List<ProjectTypeCatalogItem> _allowedProjectTypes(
    List<ProjectTypeCatalogItem> items,
  ) {
    bool isAllowed(String raw) {
      final value = raw.toLowerCase().trim();
      return value == 'mantenimiento' || value == 'construccion' || value == 'remodelacion';
    }

    return [for (final item in items) if (isAllowed(item.name)) item];
  }

  void _primeSelections({
    required List<ProjectLookup> projects,
    required List<UniverseCatalogItem> universes,
    required List<ProjectTypeCatalogItem> projectTypes,
    required ActiveLevantamientoSession? active,
  }) {
    String? nextProjectId = _selectedProjectId;
    String? nextUniverseId = _selectedUniverseId;
    String? nextProjectTypeId = _selectedProjectTypeId;

    if (active != null && active.isActive) {
      nextProjectId = active.projectId;
      nextUniverseId = active.universeId;
      nextProjectTypeId = active.projectTypeId;
    } else {
      if (nextProjectId == null && projects.isNotEmpty) {
        nextProjectId = projects.first.id;
      }
      if (nextUniverseId == null && universes.isNotEmpty) {
        nextUniverseId = universes.first.id;
      }
      if (nextProjectTypeId == null && projectTypes.isNotEmpty) {
        nextProjectTypeId = projectTypes.first.id;
      }
    }

    final changed = nextProjectId != _selectedProjectId ||
        nextUniverseId != _selectedUniverseId ||
        nextProjectTypeId != _selectedProjectTypeId;

    if (!changed) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedProjectId = nextProjectId;
        _selectedUniverseId = nextUniverseId;
        _selectedProjectTypeId = nextProjectTypeId;
      });
      _bindProjectDetails(nextProjectId, projects);
    });
  }

  @override
  Widget build(BuildContext context) {
    final catalogState = ref.watch(conceptsCatalogProvider);
    final projectsState = ref.watch(quoteProjectsProvider);
    final activeLevantamiento = ref.watch(activeLevantamientoProvider);

    final universes = catalogState.valueOrNull?.universes ?? const <UniverseCatalogItem>[];
    final projectTypes = _allowedProjectTypes(
      catalogState.valueOrNull?.projectTypes ?? const <ProjectTypeCatalogItem>[],
    );
    final projects = projectsState.valueOrNull ?? const <ProjectLookup>[];

    _primeSelections(
      projects: projects,
      universes: universes,
      projectTypes: projectTypes,
      active: activeLevantamiento,
    );

    final universeLocked = activeLevantamiento != null && activeLevantamiento.isActive;

    return PageFrame(
      title: 'Levantamiento de Proyecto',
      subtitle: 'Registro tecnico de obra, evidencia y georreferencia inicial.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 1120;
          final details = _ProjectDetailsPanel(
            selectedDate: _selectedDate,
            projectKeyController: _projectKeyController,
            selectedArchitect: _selectedArchitect,
            responsibleOptions: _responsibleOptions,
            onArchitectChanged: (value) => setState(() => _selectedArchitect = value),
            projectNameController: _projectNameController,
            clientController: _clientController,
            onClientTap: _openClientSelector,
            projects: projects,
            selectedProjectId: _selectedProjectId,
            onProjectChanged: universeLocked
                ? null
              : (value) => _handleProjectChanged(value, projects),
            onCreateProject: _isCreatingProject ? null : _createProjectFromCurrentData,
            creatingProject: _isCreatingProject,
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
            showProjectsWarning: projectsState.hasError,
            universeLocked: universeLocked,
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
    required this.selectedArchitect,
    required this.responsibleOptions,
    required this.onArchitectChanged,
    required this.projectNameController,
    required this.clientController,
    required this.onClientTap,
    required this.projects,
    required this.selectedProjectId,
    required this.onProjectChanged,
    required this.onCreateProject,
    required this.creatingProject,
    required this.universes,
    required this.selectedUniverseId,
    required this.onUniverseChanged,
    required this.projectTypes,
    required this.selectedProjectTypeId,
    required this.onProjectTypeChanged,
    required this.showCatalogWarning,
    required this.showProjectsWarning,
    required this.universeLocked,
  });

  final DateTime selectedDate;
  final TextEditingController projectKeyController;
  final String selectedArchitect;
  final List<String> responsibleOptions;
  final ValueChanged<String> onArchitectChanged;
  final TextEditingController projectNameController;
  final TextEditingController clientController;
  final VoidCallback onClientTap;
  final List<ProjectLookup> projects;
  final String? selectedProjectId;
  final ValueChanged<String>? onProjectChanged;
  final VoidCallback? onCreateProject;
  final bool creatingProject;
  final List<UniverseCatalogItem> universes;
  final String? selectedUniverseId;
  final ValueChanged<String>? onUniverseChanged;
  final List<ProjectTypeCatalogItem> projectTypes;
  final String? selectedProjectTypeId;
  final ValueChanged<String>? onProjectTypeChanged;
  final bool showCatalogWarning;
  final bool showProjectsWarning;
  final bool universeLocked;

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
                  items: responsibleOptions,
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
            onSuffixTap: onClientTap,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: selectedProjectId,
                  decoration: const InputDecoration(labelText: 'Proyecto de levantamiento'),
                  items: [
                    for (final project in projects)
                      DropdownMenuItem<String>(
                        value: project.id,
                        child: Text(project.label),
                      ),
                  ],
                  onChanged: onProjectChanged == null
                      ? null
                      : (value) {
                          if (value != null) {
                            onProjectChanged!(value);
                          }
                        },
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: onCreateProject,
                icon: creatingProject
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_business_outlined),
                label: const Text('Nuevo proyecto'),
              ),
            ],
          ),
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
          if (showCatalogWarning || showProjectsWarning) ...[
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
              border: Border.all(
                color: Colors.grey.withValues(alpha: 0.3),
                width: 1,
              ),
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
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircleAvatar(
                        radius: 24,
                        backgroundColor: RemaColors.primaryDark,
                        child: Icon(Icons.location_on, color: Colors.white),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Mapa pendiente de integracion',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Ingresa coordenadas manualmente en el campo inferior',
                        style: TextStyle(
                          color: Colors.grey.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
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
            label: 'Direccion completa (o DD.DDDD, DD.DDDD para coordenadas)',
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
            'Esta descripcion se conserva para contexto tecnico del levantamiento y debe reflejarse en la cotizacion.',
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
    this.suffixIcon,
    this.onSuffixTap,
  });

  final String label;
  final TextEditingController controller;
  final IconData? suffixIcon;
  final VoidCallback? onSuffixTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: label),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          decoration: InputDecoration(
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
