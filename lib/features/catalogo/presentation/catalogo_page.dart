import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/admin_access.dart';
import '../../../core/theme/rema_colors.dart';
import '../../../core/utils/file_download.dart';
import '../../../core/utils/rema_feedback.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/rema_panels.dart';
import '../../cotizaciones/domain/concept_generation.dart';
import '../domain/catalog_admin_models.dart';
import 'catalog_admin_controller.dart';

class CatalogoPage extends ConsumerStatefulWidget {
  const CatalogoPage({super.key});

  @override
  ConsumerState<CatalogoPage> createState() => _CatalogoPageState();
}

class _CatalogoPageState extends ConsumerState<CatalogoPage> {
  String? _selectedUniverseId;
  String? _selectedProjectTypeId;
  String? _selectedTemplateId;
  String? _selectedImportProjectTypeId;
  String _templateSearch = '';
  final TextEditingController _bulkPercentController = TextEditingController(text: '0');
  CatalogImportSummary? _lastImportSummary;
  String? _lastImportFileName;
  bool _isImporting = false;

  @override
  void dispose() {
    _bulkPercentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);
    final catalogAsync = ref.watch(catalogAdminProvider);

    if (!isAdmin) {
      return const PageFrame(
        title: 'Catálogo',
        subtitle: 'Acceso restringido al catálogo administrativo.',
        child: RemaPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Acceso restringido'),
              SizedBox(height: 12),
              Text('Solo usuarios admin pueden consultar o modificar el catálogo de conceptos.'),
            ],
          ),
        ),
      );
    }

    return PageFrame(
      title: 'Catálogo',
      subtitle: 'Administración de universos, tipos, conceptos, atributos y carga masiva CSV.',
      trailing: FilledButton.icon(
        onPressed: () => ref.read(catalogAdminProvider.notifier).reload(),
        icon: const Icon(Icons.refresh),
        label: const Text('Recargar'),
      ),
      child: catalogAsync.when(
        data: (snapshot) {
          _syncSelections(snapshot);
          final effectiveSelectedUniverseId = snapshot.universes.any(
            (item) => item.id == _selectedUniverseId,
          )
              ? _selectedUniverseId
              : (snapshot.universes.isEmpty ? null : snapshot.universes.first.id);
          final effectiveSelectedProjectTypeId = snapshot.projectTypes.any(
            (item) => item.id == _selectedProjectTypeId,
          )
              ? _selectedProjectTypeId
              : (snapshot.projectTypes.isEmpty ? null : snapshot.projectTypes.first.id);
          final effectiveImportProjectTypeId = snapshot.projectTypes.any(
            (item) => item.id == _selectedImportProjectTypeId,
          )
              ? _selectedImportProjectTypeId
              : (snapshot.projectTypes.isEmpty ? null : snapshot.projectTypes.first.id);
          final visibleTemplates = effectiveSelectedUniverseId == null
              ? snapshot.templates
              : snapshot.templatesForUniverse(effectiveSelectedUniverseId);
          final effectiveSelectedTemplateId = visibleTemplates.any(
            (item) => item.id == _selectedTemplateId,
          )
              ? _selectedTemplateId
              : (visibleTemplates.isEmpty ? null : visibleTemplates.first.id);
          final visibleAttributes = effectiveSelectedTemplateId == null
              ? const <ConceptAttributeCatalogItem>[]
              : snapshot.attributesForTemplate(effectiveSelectedTemplateId);

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SummaryStrip(snapshot: snapshot),
                const SizedBox(height: 24),
                _UniversesPanel(
                  snapshot: snapshot,
                  onCreate: _createUniverse,
                  onEdit: _editUniverse,
                  onDelete: _deleteUniverse,
                ),
                const SizedBox(height: 24),
                _ProjectTypesPanel(
                  snapshot: snapshot,
                  onCreate: _createProjectType,
                  onEdit: _editProjectType,
                  onDelete: _deleteProjectType,
                ),
                const SizedBox(height: 24),
                _TemplatesPanel(
                  snapshot: snapshot,
                  selectedUniverseId: effectiveSelectedUniverseId,
                  selectedProjectTypeId: effectiveSelectedProjectTypeId,
                  search: _templateSearch,
                  bulkPercentController: _bulkPercentController,
                  visibleTemplates: visibleTemplates,
                  onUniverseChanged: (value) => setState(() {
                    _selectedUniverseId = value;
                    _selectedTemplateId = null;
                  }),
                  onProjectTypeChanged: (value) => setState(() => _selectedProjectTypeId = value),
                  onSearchChanged: (value) => setState(() => _templateSearch = value.trim().toLowerCase()),
                  onBulkAdjust: _bulkAdjustPrices,
                  onCreate: _createTemplate,
                  onEdit: _editTemplate,
                  onDelete: _deleteTemplate,
                ),
                const SizedBox(height: 24),
                _AttributesPanel(
                  snapshot: snapshot,
                  selectedTemplateId: effectiveSelectedTemplateId,
                  visibleTemplates: visibleTemplates,
                  visibleAttributes: visibleAttributes,
                  onTemplateChanged: (value) => setState(() => _selectedTemplateId = value),
                  onCreateAttribute: _createAttribute,
                  onEditAttribute: _editAttribute,
                  onDeleteAttribute: _deleteAttribute,
                  onCreateOption: _createOption,
                  onEditOption: _editOption,
                  onDeleteOption: _deleteOption,
                ),
                const SizedBox(height: 24),
                _ImportPanel(
                  projectTypes: snapshot.projectTypes,
                  selectedProjectTypeId: effectiveImportProjectTypeId,
                  onProjectTypeChanged: (value) => setState(() => _selectedImportProjectTypeId = value),
                  onImport: _importCsv,
                  onDownloadTemplate: _downloadCsvTemplate,
                  isImporting: _isImporting,
                  lastSummary: _lastImportSummary,
                  lastFileName: _lastImportFileName,
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => RemaPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('No se pudo cargar el catálogo administrativo.'),
              const SizedBox(height: 8),
              Text(error.toString()),
            ],
          ),
        ),
      ),
    );
  }

  void _syncSelections(ConceptCatalogSnapshot snapshot) {
    var changed = false;
    var nextUniverseId = _selectedUniverseId;
    var nextProjectTypeId = _selectedProjectTypeId;
    var nextTemplateId = _selectedTemplateId;
    var nextImportProjectTypeId = _selectedImportProjectTypeId;

    if (nextUniverseId == null || !snapshot.universes.any((item) => item.id == nextUniverseId)) {
      nextUniverseId = snapshot.universes.isEmpty ? null : snapshot.universes.first.id;
      changed = true;
    }

    if (nextProjectTypeId == null || !snapshot.projectTypes.any((item) => item.id == nextProjectTypeId)) {
      nextProjectTypeId = snapshot.projectTypes.isEmpty ? null : snapshot.projectTypes.first.id;
      changed = true;
    }

    final templatesForUniverse = nextUniverseId == null
        ? snapshot.templates
        : snapshot.templatesForUniverse(nextUniverseId);
    if (nextTemplateId == null || !templatesForUniverse.any((item) => item.id == nextTemplateId)) {
      nextTemplateId = templatesForUniverse.isEmpty ? null : templatesForUniverse.first.id;
      changed = true;
    }

    if (nextImportProjectTypeId == null || !snapshot.projectTypes.any((item) => item.id == nextImportProjectTypeId)) {
      nextImportProjectTypeId = snapshot.projectTypes.isEmpty ? null : snapshot.projectTypes.first.id;
      changed = true;
    }

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
        _selectedTemplateId = nextTemplateId;
        _selectedImportProjectTypeId = nextImportProjectTypeId;
      });
    });
  }

  Future<void> _createUniverse() async {
    final name = await _showNameDialog(
      title: 'Nuevo universo',
      label: 'Nombre del universo',
    );
    if (name == null) {
      return;
    }
    await _runMutation(
      action: () => ref.read(catalogAdminProvider.notifier).createUniverse(name),
      successMessage: 'Universo creado.',
    );
  }

  Future<void> _editUniverse(UniverseCatalogItem universe) async {
    final name = await _showNameDialog(
      title: 'Editar universo',
      label: 'Nombre del universo',
      initialValue: universe.name,
    );
    if (name == null) {
      return;
    }
    await _runMutation(
      action: () => ref.read(catalogAdminProvider.notifier).updateUniverse(id: universe.id, name: name),
      successMessage: 'Universo actualizado.',
    );
  }

  Future<void> _deleteUniverse(UniverseCatalogItem universe) async {
    final confirmed = await _confirmDelete('Eliminar universo', 'Se eliminara ${universe.name} si no tiene dependencias.');
    if (confirmed != true) {
      return;
    }
    await _runMutation(
      action: () => ref.read(catalogAdminProvider.notifier).deleteUniverse(universe.id),
      successMessage: 'Universo eliminado.',
    );
  }

  Future<void> _createProjectType() async {
    final result = await showDialog<_ProjectTypeFormResult>(
      context: context,
      builder: (_) => const _ProjectTypeDialog(),
    );
    if (result == null) {
      return;
    }
    await _runMutation(
      action: () => ref.read(catalogAdminProvider.notifier).createProjectType(
            name: result.name,
            actionBase: result.actionBase,
          ),
      successMessage: 'Tipo de proyecto creado.',
    );
  }

  Future<void> _editProjectType(ProjectTypeCatalogItem projectType) async {
    final result = await showDialog<_ProjectTypeFormResult>(
      context: context,
      builder: (_) => _ProjectTypeDialog(initial: projectType),
    );
    if (result == null) {
      return;
    }
    await _runMutation(
      action: () => ref.read(catalogAdminProvider.notifier).updateProjectType(
            id: projectType.id,
            name: result.name,
            actionBase: result.actionBase,
          ),
      successMessage: 'Tipo de proyecto actualizado.',
    );
  }

  Future<void> _deleteProjectType(ProjectTypeCatalogItem projectType) async {
    final confirmed = await _confirmDelete(
      'Eliminar tipo de proyecto',
      'Se eliminara ${projectType.name} si no tiene dependencias.',
    );
    if (confirmed != true) {
      return;
    }
    await _runMutation(
      action: () => ref.read(catalogAdminProvider.notifier).deleteProjectType(projectType.id),
      successMessage: 'Tipo de proyecto eliminado.',
    );
  }

  Future<void> _createTemplate() async {
    final snapshot = ref.read(catalogAdminProvider).valueOrNull;
    if (snapshot == null || snapshot.universes.isEmpty || snapshot.projectTypes.isEmpty) {
      showRemaMessage(context, 'Primero captura al menos un universo y un tipo de proyecto.');
      return;
    }
    final result = await showDialog<_ConceptFormResult>(
      context: context,
      builder: (_) => _ConceptDialog(
        universes: snapshot.universes,
        projectTypes: snapshot.projectTypes,
        initialUniverseId: _selectedUniverseId,
        initialProjectTypeId: _selectedProjectTypeId,
      ),
    );
    if (result == null) {
      return;
    }
    await _runMutation(
      action: () => ref.read(catalogAdminProvider.notifier).createTemplate(
            universeId: result.universeId,
            projectTypeId: result.projectTypeId,
            name: result.name,
            baseDescription: result.baseDescription,
            defaultUnit: result.defaultUnit,
            basePrice: result.basePrice,
          ),
      successMessage: 'Concepto creado.',
    );
  }

  Future<void> _editTemplate(ConceptTemplateCatalogItem template) async {
    final snapshot = ref.read(catalogAdminProvider).valueOrNull;
    if (snapshot == null) {
      return;
    }
    final result = await showDialog<_ConceptFormResult>(
      context: context,
      builder: (_) => _ConceptDialog(
        universes: snapshot.universes,
        projectTypes: snapshot.projectTypes,
        initial: template,
        initialUniverseId: template.universeId,
        initialProjectTypeId: template.projectTypeId,
      ),
    );
    if (result == null) {
      return;
    }
    await _runMutation(
      action: () => ref.read(catalogAdminProvider.notifier).updateTemplate(
            id: template.id,
            universeId: result.universeId,
            projectTypeId: result.projectTypeId,
            name: result.name,
            baseDescription: result.baseDescription,
            defaultUnit: result.defaultUnit,
            basePrice: result.basePrice,
          ),
      successMessage: 'Concepto actualizado.',
    );
  }

  Future<void> _deleteTemplate(ConceptTemplateCatalogItem template) async {
    final confirmed = await _confirmDelete(
      'Eliminar concepto',
      'Se eliminara ${template.name} si no tiene atributos dependientes.',
    );
    if (confirmed != true) {
      return;
    }
    if (_selectedTemplateId == template.id) {
      setState(() => _selectedTemplateId = null);
    }
    await _runMutation(
      action: () => ref.read(catalogAdminProvider.notifier).deleteTemplate(template.id),
      successMessage: 'Concepto eliminado.',
    );
  }

  Future<void> _createAttribute() async {
    final templateId = _selectedTemplateId;
    if (templateId == null) {
      showRemaMessage(context, 'Selecciona primero un concepto.');
      return;
    }
    final name = await _showNameDialog(title: 'Nuevo atributo', label: 'Nombre del atributo');
    if (name == null) {
      return;
    }
    await _runMutation(
      action: () => ref.read(catalogAdminProvider.notifier).createAttribute(templateId: templateId, name: name),
      successMessage: 'Atributo creado.',
    );
  }

  Future<void> _editAttribute(ConceptAttributeCatalogItem attribute) async {
    final name = await _showNameDialog(
      title: 'Editar atributo',
      label: 'Nombre del atributo',
      initialValue: attribute.name,
    );
    if (name == null) {
      return;
    }
    await _runMutation(
      action: () => ref.read(catalogAdminProvider.notifier).updateAttribute(
            id: attribute.id,
            templateId: attribute.templateId,
            name: name,
          ),
      successMessage: 'Atributo actualizado.',
    );
  }

  Future<void> _deleteAttribute(ConceptAttributeCatalogItem attribute) async {
    final confirmed = await _confirmDelete(
      'Eliminar atributo',
      'Se eliminara ${attribute.name} si no tiene opciones dependientes.',
    );
    if (confirmed != true) {
      return;
    }
    await _runMutation(
      action: () => ref.read(catalogAdminProvider.notifier).deleteAttribute(attribute.id),
      successMessage: 'Atributo eliminado.',
    );
  }

  Future<void> _createOption(ConceptAttributeCatalogItem attribute) async {
    final value = await _showNameDialog(title: 'Nueva opción', label: 'Valor', initialValue: '');
    if (value == null) {
      return;
    }
    await _runMutation(
      action: () => ref.read(catalogAdminProvider.notifier).createOption(attributeId: attribute.id, value: value),
      successMessage: 'Opción creada.',
    );
  }

  Future<void> _editOption(AttributeOptionCatalogItem option) async {
    final value = await _showNameDialog(
      title: 'Editar opción',
      label: 'Valor',
      initialValue: option.value,
    );
    if (value == null) {
      return;
    }
    await _runMutation(
      action: () => ref.read(catalogAdminProvider.notifier).updateOption(
            id: option.id,
            attributeId: option.attributeId,
            value: value,
          ),
      successMessage: 'Opción actualizada.',
    );
  }

  Future<void> _deleteOption(AttributeOptionCatalogItem option) async {
    final confirmed = await _confirmDelete('Eliminar opción', 'Se eliminara la opción ${option.value}.');
    if (confirmed != true) {
      return;
    }
    await _runMutation(
      action: () => ref.read(catalogAdminProvider.notifier).deleteOption(option.id),
      successMessage: 'Opción eliminada.',
    );
  }

  Future<void> _importCsv() async {
    final projectTypeId = _selectedImportProjectTypeId;
    if (projectTypeId == null) {
      showRemaMessage(context, 'Selecciona el tipo de proyecto destino para la importación.');
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: true,
    );
    if (!mounted || result == null || result.files.isEmpty) {
      return;
    }

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      showRemaMessage(context, 'No se pudo leer el archivo CSV.');
      return;
    }

    setState(() => _isImporting = true);
    try {
      final content = utf8.decode(bytes);
      final summary = await ref.read(catalogAdminProvider.notifier).importCsv(
            csvContent: content,
        defaultProjectTypeId: projectTypeId,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _lastImportSummary = summary;
        _lastImportFileName = file.name;
      });
      showRemaMessage(
        context,
        summary.hasErrors
            ? 'Importación completada con observaciones. Revisa el resumen.'
            : 'Importación CSV completada correctamente.',
      );
    } catch (error) {
      if (mounted) {
        showRemaMessage(context, 'No se pudo importar el CSV: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Future<void> _downloadCsvTemplate() async {
    final content = _buildCatalogCsvTemplate();
    final saved = await saveTextFile(
      fileName: 'catalogo_plantilla.csv',
      content: content,
      dialogTitle: 'Guardar plantilla CSV',
    );
    if (!mounted) {
      return;
    }
    showRemaMessage(
      context,
      saved ? 'Plantilla CSV lista para descarga.' : 'No se pudo descargar la plantilla CSV.',
    );
  }

  String _buildCatalogCsvTemplate() {
    const rows = <List<String>>[
      <String>[
        'universe',
        'concept',
        'unit',
        'base_price',
        'attribute',
        'option',
        'project_type',
        'base_description',
      ],
      <String>[
        'Vidrio/Aluminio',
        'Canceleria de aluminio',
        'm2',
        '1850',
        'vidrio',
        'Claro 6mm',
        'Remodelacion',
        'Suministro e instalacion de canceleria de aluminio.',
      ],
      <String>[
        'Vidrio/Aluminio',
        'Canceleria de aluminio',
        'm2',
        '1850',
        'acabado',
        'Natural',
        'Remodelacion',
        'Suministro e instalacion de canceleria de aluminio.',
      ],
      <String>[
        'Paneles',
        'Panel de yeso',
        'm2',
        '620',
        'tipo_panel',
        'RH',
        'Remodelacion',
        'Fabricacion de muro de panel de yeso.',
      ],
    ];

    return rows.map(_csvRow).join('\n');
  }

  String _csvRow(List<String> values) {
    return values.map((value) {
      final escaped = value.replaceAll('"', '""');
      if (escaped.contains(',') || escaped.contains('"') || escaped.contains('\n')) {
        return '"$escaped"';
      }
      return escaped;
    }).join(',');
  }

  Future<void> _bulkAdjustPrices(List<ConceptTemplateCatalogItem> templates) async {
    if (templates.isEmpty) {
      showRemaMessage(context, 'No hay conceptos para ajuste masivo con el filtro actual.');
      return;
    }
    final percent = double.tryParse(_bulkPercentController.text.trim().replaceAll(',', '.'));
    if (percent == null) {
      showRemaMessage(context, 'Ingresa un porcentaje válido (ej. 10 o -5).');
      return;
    }

    await _runMutation(
      action: () => ref
          .read(catalogAdminProvider.notifier)
          .bulkAdjustTemplatePrices(templateIds: [for (final t in templates) t.id], percent: percent),
      successMessage: 'Ajuste masivo aplicado a ${templates.length} conceptos.',
    );
  }

  Future<void> _runMutation({required Future<void> Function() action, required String successMessage}) async {
    try {
      await action();
      if (mounted) {
        showRemaMessage(context, successMessage);
      }
    } catch (error) {
      if (mounted) {
        showRemaMessage(context, '$error');
      }
    }
  }

  Future<String?> _showNameDialog({required String title, required String label, String initialValue = ''}) async {
    return showDialog<String>(
      context: context,
      builder: (_) => _TextValueDialog(title: title, label: label, initialValue: initialValue),
    );
  }

  Future<bool?> _confirmDelete(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Eliminar')),
        ],
      ),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.snapshot});

  final ConceptCatalogSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tiles = [
          RemaMetricTile(label: 'Universos', value: '${snapshot.universes.length}'),
          RemaMetricTile(label: 'Tipos de proyecto', value: '${snapshot.projectTypes.length}'),
          RemaMetricTile(label: 'Conceptos', value: '${snapshot.templates.length}', backgroundColor: const Color(0xFFFFDEA0)),
          RemaMetricTile(label: 'Atributos', value: '${snapshot.attributes.length}', backgroundColor: RemaColors.surfaceHighest),
        ];
        if (constraints.maxWidth < 960) {
          return Column(
            children: [
              for (final tile in tiles) ...[
                tile,
                if (tile != tiles.last) const SizedBox(height: 16),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (final tile in tiles) ...[
              Expanded(child: tile),
              if (tile != tiles.last) const SizedBox(width: 16),
            ],
          ],
        );
      },
    );
  }
}

class _UniversesPanel extends StatelessWidget {
  const _UniversesPanel({
    required this.snapshot,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
  });

  final ConceptCatalogSnapshot snapshot;
  final VoidCallback onCreate;
  final ValueChanged<UniverseCatalogItem> onEdit;
  final ValueChanged<UniverseCatalogItem> onDelete;

  @override
  Widget build(BuildContext context) {
    return RemaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RemaSectionHeader(
            title: 'Universos',
            icon: Icons.public,
            trailing: FilledButton.icon(onPressed: onCreate, icon: const Icon(Icons.add), label: const Text('Nuevo')),
          ),
          const SizedBox(height: 20),
          if (snapshot.universes.isEmpty)
            const Text('Aún no hay universos registrados.')
          else
            for (final universe in snapshot.universes) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(universe.name),
                subtitle: Text('${snapshot.templatesForUniverse(universe.id).length} conceptos asociados'),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    IconButton(onPressed: () => onEdit(universe), icon: const Icon(Icons.edit_outlined)),
                    IconButton(onPressed: () => onDelete(universe), icon: const Icon(Icons.delete_outline)),
                  ],
                ),
              ),
              if (universe != snapshot.universes.last) const Divider(height: 1),
            ],
        ],
      ),
    );
  }
}

class _ProjectTypesPanel extends StatelessWidget {
  const _ProjectTypesPanel({
    required this.snapshot,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
  });

  final ConceptCatalogSnapshot snapshot;
  final VoidCallback onCreate;
  final ValueChanged<ProjectTypeCatalogItem> onEdit;
  final ValueChanged<ProjectTypeCatalogItem> onDelete;

  @override
  Widget build(BuildContext context) {
    return RemaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RemaSectionHeader(
            title: 'Tipos de proyecto',
            icon: Icons.account_tree_outlined,
            trailing: FilledButton.icon(onPressed: onCreate, icon: const Icon(Icons.add), label: const Text('Nuevo')),
          ),
          const SizedBox(height: 20),
          if (snapshot.projectTypes.isEmpty)
            const Text('Aún no hay tipos de proyecto registrados.')
          else
            for (final item in snapshot.projectTypes) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item.name),
                subtitle: Text('action_base: ${item.actionBase}'),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    IconButton(onPressed: () => onEdit(item), icon: const Icon(Icons.edit_outlined)),
                    IconButton(onPressed: () => onDelete(item), icon: const Icon(Icons.delete_outline)),
                  ],
                ),
              ),
              if (item != snapshot.projectTypes.last) const Divider(height: 1),
            ],
        ],
      ),
    );
  }
}

class _TemplatesPanel extends StatelessWidget {
  const _TemplatesPanel({
    required this.snapshot,
    required this.selectedUniverseId,
    required this.selectedProjectTypeId,
    required this.search,
    required this.bulkPercentController,
    required this.visibleTemplates,
    required this.onUniverseChanged,
    required this.onProjectTypeChanged,
    required this.onSearchChanged,
    required this.onBulkAdjust,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
  });

  final ConceptCatalogSnapshot snapshot;
  final String? selectedUniverseId;
  final String? selectedProjectTypeId;
  final String search;
  final TextEditingController bulkPercentController;
  final List<ConceptTemplateCatalogItem> visibleTemplates;
  final ValueChanged<String?> onUniverseChanged;
  final ValueChanged<String?> onProjectTypeChanged;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<List<ConceptTemplateCatalogItem>> onBulkAdjust;
  final VoidCallback onCreate;
  final ValueChanged<ConceptTemplateCatalogItem> onEdit;
  final ValueChanged<ConceptTemplateCatalogItem> onDelete;

  @override
  Widget build(BuildContext context) {
    var templates = selectedProjectTypeId == null
        ? visibleTemplates
        : visibleTemplates.where((item) => item.projectTypeId == selectedProjectTypeId).toList();
    if (search.isNotEmpty) {
      templates = templates.where((item) {
        final haystack = '${item.name} ${item.baseDescription} ${item.defaultUnit}'.toLowerCase();
        return haystack.contains(search);
      }).toList();
    }
    return RemaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RemaSectionHeader(
            title: 'Conceptos base',
            icon: Icons.inventory_2_outlined,
            trailing: FilledButton.icon(onPressed: onCreate, icon: const Icon(Icons.add), label: const Text('Nuevo')),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: selectedUniverseId,
                  decoration: const InputDecoration(labelText: 'Universo'),
                  items: [
                    for (final item in snapshot.universes)
                      DropdownMenuItem(value: item.id, child: Text(item.name)),
                  ],
                  onChanged: onUniverseChanged,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: selectedProjectTypeId,
                  decoration: const InputDecoration(labelText: 'Tipo de proyecto'),
                  items: [
                    for (final item in snapshot.projectTypes)
                      DropdownMenuItem(value: item.id, child: Text(item.name)),
                  ],
                  onChanged: onProjectTypeChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Buscar concepto',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: onSearchChanged,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 220,
                child: TextField(
                  controller: bulkPercentController,
                  decoration: const InputDecoration(labelText: 'Ajuste masivo % (ej. 10 o -5)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonalIcon(
                onPressed: () => onBulkAdjust(templates),
                icon: const Icon(Icons.auto_fix_high_outlined),
                label: const Text('Aplicar a filtrados'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (templates.isEmpty)
            const Text('No hay conceptos para el filtro actual.')
          else
            for (final template in templates) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(template.name),
                subtitle: Text(
                  '${snapshot.projectTypeById(template.projectTypeId)?.name ?? 'Sin tipo'} · ${template.defaultUnit} · ${template.basePrice.toStringAsFixed(2)}',
                ),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    IconButton(onPressed: () => onEdit(template), icon: const Icon(Icons.edit_outlined)),
                    IconButton(onPressed: () => onDelete(template), icon: const Icon(Icons.delete_outline)),
                  ],
                ),
              ),
              if (template.baseDescription.trim().isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(template.baseDescription, style: Theme.of(context).textTheme.bodySmall),
                  ),
                ),
              if (template != templates.last) const Divider(height: 1),
            ],
        ],
      ),
    );
  }
}

class _AttributesPanel extends StatelessWidget {
  const _AttributesPanel({
    required this.snapshot,
    required this.selectedTemplateId,
    required this.visibleTemplates,
    required this.visibleAttributes,
    required this.onTemplateChanged,
    required this.onCreateAttribute,
    required this.onEditAttribute,
    required this.onDeleteAttribute,
    required this.onCreateOption,
    required this.onEditOption,
    required this.onDeleteOption,
  });

  final ConceptCatalogSnapshot snapshot;
  final String? selectedTemplateId;
  final List<ConceptTemplateCatalogItem> visibleTemplates;
  final List<ConceptAttributeCatalogItem> visibleAttributes;
  final ValueChanged<String?> onTemplateChanged;
  final VoidCallback onCreateAttribute;
  final ValueChanged<ConceptAttributeCatalogItem> onEditAttribute;
  final ValueChanged<ConceptAttributeCatalogItem> onDeleteAttribute;
  final ValueChanged<ConceptAttributeCatalogItem> onCreateOption;
  final ValueChanged<AttributeOptionCatalogItem> onEditOption;
  final ValueChanged<AttributeOptionCatalogItem> onDeleteOption;

  @override
  Widget build(BuildContext context) {
    return RemaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RemaSectionHeader(
            title: 'Atributos y opciones',
            icon: Icons.tune,
            trailing: FilledButton.icon(
              onPressed: selectedTemplateId == null ? null : onCreateAttribute,
              icon: const Icon(Icons.add),
              label: const Text('Nuevo atributo'),
            ),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: selectedTemplateId,
            decoration: const InputDecoration(labelText: 'Concepto'),
            items: [
              for (final item in visibleTemplates) DropdownMenuItem(value: item.id, child: Text(item.name)),
            ],
            onChanged: onTemplateChanged,
          ),
          const SizedBox(height: 20),
          if (selectedTemplateId == null)
            const Text('Selecciona un concepto para administrar atributos.')
          else if (visibleAttributes.isEmpty)
            const Text('Este concepto aún no tiene atributos.')
          else
            for (final attribute in visibleAttributes) ...[
              _AttributeCard(
                attribute: attribute,
                options: snapshot.optionsForAttribute(attribute.id),
                onEditAttribute: () => onEditAttribute(attribute),
                onDeleteAttribute: () => onDeleteAttribute(attribute),
                onAddOption: () => onCreateOption(attribute),
                onEditOption: onEditOption,
                onDeleteOption: onDeleteOption,
              ),
              if (attribute != visibleAttributes.last) const SizedBox(height: 16),
            ],
        ],
      ),
    );
  }
}

class _ImportPanel extends StatelessWidget {
  const _ImportPanel({
    required this.projectTypes,
    required this.selectedProjectTypeId,
    required this.onProjectTypeChanged,
    required this.onImport,
    required this.onDownloadTemplate,
    required this.isImporting,
    required this.lastSummary,
    required this.lastFileName,
  });

  final List<ProjectTypeCatalogItem> projectTypes;
  final String? selectedProjectTypeId;
  final ValueChanged<String?> onProjectTypeChanged;
  final VoidCallback onImport;
  final VoidCallback onDownloadTemplate;
  final bool isImporting;
  final CatalogImportSummary? lastSummary;
  final String? lastFileName;

  @override
  Widget build(BuildContext context) {
    return RemaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RemaSectionHeader(
            title: 'Importador CSV',
            icon: Icons.upload_file_outlined,
            trailing: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: isImporting ? null : onDownloadTemplate,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Descargar plantilla'),
                ),
                FilledButton.icon(
                  onPressed: isImporting ? null : onImport,
                  icon: isImporting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.file_upload_outlined),
                  label: Text(isImporting ? 'Importando...' : 'Subir CSV'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('Columnas obligatorias: universe, concept, unit, base_price, attribute, option.'),
          const SizedBox(height: 6),
          const Text('Columnas opcionales: project_type, base_description.'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: selectedProjectTypeId,
            decoration: const InputDecoration(labelText: 'Tipo de proyecto destino'),
            items: [
              for (final item in projectTypes) DropdownMenuItem(value: item.id, child: Text(item.name)),
            ],
            onChanged: onProjectTypeChanged,
          ),
          if (lastFileName != null) ...[
            const SizedBox(height: 16),
            Text('Último archivo: $lastFileName'),
          ],
          if (lastSummary != null) ...[
            const SizedBox(height: 20),
            _ImportSummaryCard(summary: lastSummary!),
          ],
        ],
      ),
    );
  }
}

class _AttributeCard extends StatelessWidget {
  const _AttributeCard({
    required this.attribute,
    required this.options,
    required this.onEditAttribute,
    required this.onDeleteAttribute,
    required this.onAddOption,
    required this.onEditOption,
    required this.onDeleteOption,
  });

  final ConceptAttributeCatalogItem attribute;
  final List<AttributeOptionCatalogItem> options;
  final VoidCallback onEditAttribute;
  final VoidCallback onDeleteAttribute;
  final VoidCallback onAddOption;
  final ValueChanged<AttributeOptionCatalogItem> onEditOption;
  final ValueChanged<AttributeOptionCatalogItem> onDeleteOption;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RemaColors.surfaceLow,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(attribute.name, style: Theme.of(context).textTheme.titleMedium)),
              IconButton(onPressed: onEditAttribute, icon: const Icon(Icons.edit_outlined)),
              IconButton(onPressed: onDeleteAttribute, icon: const Icon(Icons.delete_outline)),
              FilledButton.tonalIcon(onPressed: onAddOption, icon: const Icon(Icons.add), label: const Text('Opción')),
            ],
          ),
          const SizedBox(height: 12),
          if (options.isEmpty)
            const Text('Sin opciones capturadas.')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in options)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: RemaColors.surfaceWhite,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(option.value),
                        const SizedBox(width: 8),
                        InkWell(onTap: () => onEditOption(option), child: const Icon(Icons.edit, size: 16)),
                        const SizedBox(width: 6),
                        InkWell(onTap: () => onDeleteOption(option), child: const Icon(Icons.close, size: 16)),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ImportSummaryCard extends StatelessWidget {
  const _ImportSummaryCard({required this.summary});

  final CatalogImportSummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: summary.hasErrors ? const Color(0xFFFFF1E0) : RemaColors.surfaceLow,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Resumen de importación', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Text('Universos: ${summary.createdUniverses} creados, ${summary.existingUniverses} existentes'),
          Text('Conceptos: ${summary.createdTemplates} creados, ${summary.existingTemplates} existentes'),
          Text('Atributos: ${summary.createdAttributes} creados, ${summary.existingAttributes} existentes'),
          Text('Opciones: ${summary.createdOptions} creadas, ${summary.existingOptions} existentes'),
          if (summary.issues.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Observaciones:'),
            const SizedBox(height: 8),
            for (final issue in summary.issues.take(8))
              Text('Línea ${issue.lineNumber}: ${issue.message}'),
            if (summary.issues.length > 8) Text('... ${summary.issues.length - 8} observaciones adicionales'),
          ],
        ],
      ),
    );
  }
}

class _TextValueDialog extends StatefulWidget {
  const _TextValueDialog({required this.title, required this.label, required this.initialValue});

  final String title;
  final String label;
  final String initialValue;

  @override
  State<_TextValueDialog> createState() => _TextValueDialogState();
}

class _TextValueDialogState extends State<_TextValueDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.label),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _ProjectTypeDialog extends StatefulWidget {
  const _ProjectTypeDialog({this.initial});

  final ProjectTypeCatalogItem? initial;

  @override
  State<_ProjectTypeDialog> createState() => _ProjectTypeDialogState();
}

class _ProjectTypeDialogState extends State<_ProjectTypeDialog> {
  late final TextEditingController _nameController = TextEditingController(text: widget.initial?.name ?? '');
  late final TextEditingController _actionBaseController = TextEditingController(text: widget.initial?.actionBase ?? '');

  @override
  void dispose() {
    _nameController.dispose();
    _actionBaseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Nuevo tipo de proyecto' : 'Editar tipo de proyecto'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Nombre')),
            const SizedBox(height: 16),
            TextField(controller: _actionBaseController, decoration: const InputDecoration(labelText: 'action_base')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _ProjectTypeFormResult(
              name: _nameController.text.trim(),
              actionBase: _actionBaseController.text.trim(),
            ),
          ),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _ConceptDialog extends StatefulWidget {
  const _ConceptDialog({
    required this.universes,
    required this.projectTypes,
    required this.initialUniverseId,
    required this.initialProjectTypeId,
    this.initial,
  });

  final List<UniverseCatalogItem> universes;
  final List<ProjectTypeCatalogItem> projectTypes;
  final String? initialUniverseId;
  final String? initialProjectTypeId;
  final ConceptTemplateCatalogItem? initial;

  @override
  State<_ConceptDialog> createState() => _ConceptDialogState();
}

class _ConceptDialogState extends State<_ConceptDialog> {
  late String? _universeId = widget.initialUniverseId ?? (widget.universes.isEmpty ? null : widget.universes.first.id);
  late String? _projectTypeId = widget.initialProjectTypeId ?? (widget.projectTypes.isEmpty ? null : widget.projectTypes.first.id);
  late final TextEditingController _nameController = TextEditingController(text: widget.initial?.name ?? '');
  late final TextEditingController _descriptionController = TextEditingController(text: widget.initial?.baseDescription ?? '');
  late final TextEditingController _unitController = TextEditingController(text: widget.initial?.defaultUnit ?? 'm2');
  late final TextEditingController _priceController = TextEditingController(text: widget.initial?.basePrice.toStringAsFixed(2) ?? '0');

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _unitController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Nuevo concepto' : 'Editar concepto'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _universeId,
                decoration: const InputDecoration(labelText: 'Universo'),
                items: [
                  for (final item in widget.universes) DropdownMenuItem(value: item.id, child: Text(item.name)),
                ],
                onChanged: (value) => setState(() => _universeId = value),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _projectTypeId,
                decoration: const InputDecoration(labelText: 'Tipo de proyecto'),
                items: [
                  for (final item in widget.projectTypes) DropdownMenuItem(value: item.id, child: Text(item.name)),
                ],
                onChanged: (value) => setState(() => _projectTypeId = value),
              ),
              const SizedBox(height: 16),
              TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Nombre')),
              const SizedBox(height: 16),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Base description (opcional)'),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: TextField(controller: _unitController, decoration: const InputDecoration(labelText: 'Unidad'))),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _priceController,
                      decoration: const InputDecoration(labelText: 'Precio base'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final price = double.tryParse(_priceController.text.trim().replaceAll(',', '')) ?? 0;
            if (_universeId == null || _projectTypeId == null) {
              return;
            }
            Navigator.of(context).pop(
              _ConceptFormResult(
                universeId: _universeId!,
                projectTypeId: _projectTypeId!,
                name: _nameController.text.trim(),
                baseDescription: _descriptionController.text.trim(),
                defaultUnit: _unitController.text.trim(),
                basePrice: price,
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _ProjectTypeFormResult {
  const _ProjectTypeFormResult({required this.name, required this.actionBase});

  final String name;
  final String actionBase;
}

class _ConceptFormResult {
  const _ConceptFormResult({
    required this.universeId,
    required this.projectTypeId,
    required this.name,
    required this.baseDescription,
    required this.defaultUnit,
    required this.basePrice,
  });

  final String universeId;
  final String projectTypeId;
  final String name;
  final String baseDescription;
  final String defaultUnit;
  final double basePrice;
}