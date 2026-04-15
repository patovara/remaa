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
import '../domain/catalog_concept_form.dart';
import 'catalog_admin_controller.dart';
import 'catalog_ui_controller.dart';

class CatalogoPage extends ConsumerStatefulWidget {
  const CatalogoPage({super.key});

  @override
  ConsumerState<CatalogoPage> createState() => _CatalogoPageState();
}

class _CatalogoPageState extends ConsumerState<CatalogoPage> {
  final TextEditingController _bulkPercentController = TextEditingController(
    text: '0',
  );

  @override
  void dispose() {
    _bulkPercentController.dispose();
    super.dispose();
  }

  String _formatCatalogError(dynamic error) {
    final errorStr = error.toString();
    
    if (errorStr.contains('42501') || errorStr.contains('insufficient_privilege')) {
      return 'Permiso insuficiente: RLS bloqueó la operación. '
          'Verifica tu rol de admin en Supabase y que las políticas de catálogo estén habilitadas.';
    }
    
    if (errorStr.contains('duplicate')) {
      return 'Registro duplicado: esta entidad ya existe en el catálogo.';
    }
    
    if (errorStr.contains('not_found') || errorStr.contains('no rows')) {
      return 'Registro no encontrado: verifica que exista en el catálogo.';
    }
    
    return errorStr;
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);
    final catalogAsync = ref.watch(catalogAdminProvider);
    final uiState = ref.watch(catalogUiControllerProvider);

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
              Text(
                'Solo usuarios admin pueden consultar o modificar el catálogo de conceptos.',
              ),
            ],
          ),
        ),
      );
    }

    return PageFrame(
      title: 'Catálogo',
      subtitle:
          'Administración de universos, tipos, conceptos, atributos y carga masiva CSV.',
      trailing: FilledButton.icon(
        onPressed: () => ref.read(catalogAdminProvider.notifier).reload(),
        icon: const Icon(Icons.refresh),
        label: const Text('Recargar'),
      ),
      child: catalogAsync.when(
        data: (snapshot) {
          try {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) {
                return;
              }
              ref
                  .read(catalogUiControllerProvider.notifier)
                  .syncWithSnapshot(snapshot);
            });

            final viewData = ref
                .read(catalogUiControllerProvider.notifier)
                .viewDataFor(snapshot);

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
                    selectedUniverseId: viewData.selectedUniverseId,
                    selectedProjectTypeId: viewData.selectedProjectTypeId,
                    bulkPercentController: _bulkPercentController,
                    templates: viewData.filteredTemplates,
                    onUniverseChanged: ref
                        .read(catalogUiControllerProvider.notifier)
                        .selectUniverse,
                    onProjectTypeChanged: ref
                        .read(catalogUiControllerProvider.notifier)
                        .selectProjectType,
                    onSearchChanged: ref
                        .read(catalogUiControllerProvider.notifier)
                        .changeTemplateSearch,
                    onBulkAdjust: _bulkAdjustPrices,
                    onCreate: _createTemplate,
                    onEdit: _editTemplate,
                    onDelete: _deleteTemplate,
                  ),
                  const SizedBox(height: 24),
                  _AttributesPanel(
                    snapshot: snapshot,
                    selectedTemplateId: viewData.selectedTemplateId,
                    visibleTemplates: viewData.visibleTemplates,
                    visibleAttributes: viewData.visibleAttributes,
                    onTemplateChanged: ref
                        .read(catalogUiControllerProvider.notifier)
                        .selectTemplate,
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
                    selectedProjectTypeId: viewData.selectedImportProjectTypeId,
                    onProjectTypeChanged: ref
                        .read(catalogUiControllerProvider.notifier)
                        .selectImportProjectType,
                    onImport: _importCsv,
                    onDownloadTemplate: _downloadCsvTemplate,
                    isImporting: uiState.isImporting,
                    lastSummary: uiState.lastImportSummary,
                    lastFileName: uiState.lastImportFileName,
                  ),
                ],
              ),
            );
          } catch (error) {
            return RemaPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Se detectó un error al renderizar el catálogo. '
                    'La pantalla no se bloqueó para que puedas continuar.',
                  ),
                  const SizedBox(height: 8),
                  SelectableText(error.toString()),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => ref
                        .read(catalogAdminProvider.notifier)
                        .reload(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Recargar catálogo'),
                  ),
                ],
              ),
            );
          }
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

  Future<void> _createUniverse() async {
    final name = await _showNameDialog(
      title: 'Nuevo universo',
      label: 'Nombre del universo',
    );
    if (name == null) {
      return;
    }
    await _runMutation(
      action: () =>
          ref.read(catalogAdminProvider.notifier).createUniverse(name),
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
      action: () => ref
          .read(catalogAdminProvider.notifier)
          .updateUniverse(id: universe.id, name: name),
      successMessage: 'Universo actualizado.',
    );
  }

  Future<void> _deleteUniverse(UniverseCatalogItem universe) async {
    final snapshot = ref.read(catalogAdminProvider).valueOrNull;
    final templateIds = {
      for (final item in snapshot?.templates ?? const <ConceptTemplateCatalogItem>[])
        if (item.universeId == universe.id) item.id,
    };
    final attributeIds = {
      for (final item in snapshot?.attributes ?? const <ConceptAttributeCatalogItem>[])
        if (templateIds.contains(item.templateId)) item.id,
    };
    final optionsCount = (snapshot?.options ?? const <AttributeOptionCatalogItem>[])
        .where((item) => attributeIds.contains(item.attributeId))
        .length;

    final hasChildren =
        templateIds.isNotEmpty || attributeIds.isNotEmpty || optionsCount > 0;
    final confirmed = await _confirmDelete(
      title: 'Eliminar universo',
      message: hasChildren
          ? 'Este universo tiene subelementos asociados. Para confirmar la eliminación en cascada escribe ELIMINAR.'
          : 'Se eliminara ${universe.name} si no tiene dependencias.',
      requireKeyword: hasChildren,
      details: hasChildren
          ? [
              'Conceptos: ${templateIds.length}',
              'Atributos: ${attributeIds.length}',
              'Opciones: $optionsCount',
            ]
          : const <String>[],
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _runMutation(
      action: () => hasChildren
          ? ref
                .read(catalogAdminProvider.notifier)
                .deleteUniverseCascade(universe.id)
          : ref.read(catalogAdminProvider.notifier).deleteUniverse(universe.id),
      successMessage: hasChildren
          ? 'Universo y subelementos eliminados.'
          : 'Universo eliminado.',
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
      action: () => ref
          .read(catalogAdminProvider.notifier)
          .createProjectType(name: result.name, actionBase: result.actionBase),
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
      action: () => ref
          .read(catalogAdminProvider.notifier)
          .updateProjectType(
            id: projectType.id,
            name: result.name,
            actionBase: result.actionBase,
          ),
      successMessage: 'Tipo de proyecto actualizado.',
    );
  }

  Future<void> _deleteProjectType(ProjectTypeCatalogItem projectType) async {
    final snapshot = ref.read(catalogAdminProvider).valueOrNull;
    final templateIds = {
      for (final item in snapshot?.templates ?? const <ConceptTemplateCatalogItem>[])
        if (item.projectTypeId == projectType.id) item.id,
    };
    final attributeIds = {
      for (final item in snapshot?.attributes ?? const <ConceptAttributeCatalogItem>[])
        if (templateIds.contains(item.templateId)) item.id,
    };
    final optionsCount = (snapshot?.options ?? const <AttributeOptionCatalogItem>[])
        .where((item) => attributeIds.contains(item.attributeId))
        .length;

    final hasChildren =
        templateIds.isNotEmpty || attributeIds.isNotEmpty || optionsCount > 0;
    final confirmed = await _confirmDelete(
      title: 'Eliminar tipo de proyecto',
      message: hasChildren
          ? 'Este tipo de proyecto tiene subelementos asociados. Para confirmar la eliminación en cascada escribe ELIMINAR.'
          : 'Se eliminara ${projectType.name} si no tiene dependencias.',
      requireKeyword: hasChildren,
      details: hasChildren
          ? [
              'Conceptos: ${templateIds.length}',
              'Atributos: ${attributeIds.length}',
              'Opciones: $optionsCount',
            ]
          : const <String>[],
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _runMutation(
      action: () => hasChildren
          ? ref
                .read(catalogAdminProvider.notifier)
                .deleteProjectTypeCascade(projectType.id)
          : ref
                .read(catalogAdminProvider.notifier)
                .deleteProjectType(projectType.id),
      successMessage: hasChildren
          ? 'Tipo de proyecto y subelementos eliminados.'
          : 'Tipo de proyecto eliminado.',
    );
  }

  Future<void> _createTemplate() async {
    final snapshot = ref.read(catalogAdminProvider).valueOrNull;
    if (snapshot == null ||
        snapshot.universes.isEmpty ||
        snapshot.projectTypes.isEmpty) {
      showRemaMessage(
        context,
        'Primero captura al menos un universo y un tipo de proyecto.',
      );
      return;
    }
    final uiState = ref.read(catalogUiControllerProvider);
    final result = await showDialog<CatalogConceptDraft>(
      context: context,
      builder: (_) => _ConceptDialog(
        universes: snapshot.universes,
        projectTypes: snapshot.projectTypes,
        initialUniverseId: uiState.selectedUniverseId,
        initialProjectTypeId: uiState.selectedProjectTypeId,
        attributeLibrary: CatalogAttributeLibrary.fromSnapshot(snapshot),
      ),
    );
    if (result == null) {
      return;
    }
    await _runMutation(
      action: () => ref
          .read(catalogAdminProvider.notifier)
          .createTemplateWithAttributes(result),
      successMessage: 'Concepto creado.',
    );
  }

  Future<void> _editTemplate(ConceptTemplateCatalogItem template) async {
    final snapshot = ref.read(catalogAdminProvider).valueOrNull;
    if (snapshot == null) {
      return;
    }
    final result = await showDialog<CatalogConceptDraft>(
      context: context,
      builder: (_) => _ConceptDialog(
        universes: snapshot.universes,
        projectTypes: snapshot.projectTypes,
        initial: template,
        initialUniverseId: template.universeId,
        initialProjectTypeId: template.projectTypeId,
        attributeLibrary: CatalogAttributeLibrary.fromSnapshot(snapshot),
      ),
    );
    if (result == null) {
      return;
    }
    await _runMutation(
      action: () => ref
          .read(catalogAdminProvider.notifier)
          .updateTemplate(
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
    final snapshot = ref.read(catalogAdminProvider).valueOrNull;
    final attributeIds = {
      for (final item in snapshot?.attributes ?? const <ConceptAttributeCatalogItem>[])
        if (item.templateId == template.id) item.id,
    };
    final optionsCount = (snapshot?.options ?? const <AttributeOptionCatalogItem>[])
        .where((item) => attributeIds.contains(item.attributeId))
        .length;
    final hasChildren = attributeIds.isNotEmpty || optionsCount > 0;

    final confirmed = await _confirmDelete(
      title: 'Eliminar concepto',
      message: hasChildren
          ? 'Este concepto tiene subelementos asociados. Para confirmar la eliminación en cascada escribe ELIMINAR.'
          : 'Se eliminara ${template.name} si no tiene atributos dependientes.',
      requireKeyword: hasChildren,
      details: hasChildren
          ? [
              'Atributos: ${attributeIds.length}',
              'Opciones: $optionsCount',
            ]
          : const <String>[],
    );
    if (confirmed != true || !mounted) {
      return;
    }
    if (ref.read(catalogUiControllerProvider).selectedTemplateId ==
        template.id) {
      ref.read(catalogUiControllerProvider.notifier).selectTemplate(null);
    }
    await _runMutation(
      action: () => hasChildren
          ? ref
                .read(catalogAdminProvider.notifier)
                .deleteTemplateCascade(template.id)
          : ref.read(catalogAdminProvider.notifier).deleteTemplate(template.id),
      successMessage: hasChildren
          ? 'Concepto y subelementos eliminados.'
          : 'Concepto eliminado.',
    );
  }

  Future<void> _createAttribute() async {
    final templateId = ref.read(catalogUiControllerProvider).selectedTemplateId;
    if (templateId == null) {
      showRemaMessage(context, 'Selecciona primero un concepto.');
      return;
    }
    final name = await _showNameDialog(
      title: 'Nuevo atributo',
      label: 'Nombre del atributo',
    );
    if (name == null) {
      return;
    }
    await _runMutation(
      action: () => ref
          .read(catalogAdminProvider.notifier)
          .createAttribute(templateId: templateId, name: name),
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
      action: () => ref
          .read(catalogAdminProvider.notifier)
          .updateAttribute(
            id: attribute.id,
            templateId: attribute.templateId,
            name: name,
          ),
      successMessage: 'Atributo actualizado.',
    );
  }

  Future<void> _deleteAttribute(ConceptAttributeCatalogItem attribute) async {
    final snapshot = ref.read(catalogAdminProvider).valueOrNull;
    final optionsCount = (snapshot?.options ?? const <AttributeOptionCatalogItem>[])
        .where((item) => item.attributeId == attribute.id)
        .length;
    final hasChildren = optionsCount > 0;

    final confirmed = await _confirmDelete(
      title: 'Eliminar atributo',
      message: hasChildren
          ? 'Este atributo tiene subelementos asociados. Para confirmar la eliminación en cascada escribe ELIMINAR.'
          : 'Se eliminara ${attribute.name} si no tiene opciones dependientes.',
      requireKeyword: hasChildren,
      details: hasChildren ? ['Opciones: $optionsCount'] : const <String>[],
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _runMutation(
      action: () => hasChildren
          ? ref
                .read(catalogAdminProvider.notifier)
                .deleteAttributeCascade(attribute.id)
          : ref.read(catalogAdminProvider.notifier).deleteAttribute(attribute.id),
      successMessage: hasChildren
          ? 'Atributo y subelementos eliminados.'
          : 'Atributo eliminado.',
    );
  }

  Future<void> _createOption(ConceptAttributeCatalogItem attribute) async {
    final value = await _showNameDialog(
      title: 'Nueva opción',
      label: 'Valor',
      initialValue: '',
    );
    if (value == null) {
      return;
    }
    await _runMutation(
      action: () => ref
          .read(catalogAdminProvider.notifier)
          .createOption(attributeId: attribute.id, value: value),
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
      action: () => ref
          .read(catalogAdminProvider.notifier)
          .updateOption(
            id: option.id,
            attributeId: option.attributeId,
            value: value,
          ),
      successMessage: 'Opción actualizada.',
    );
  }

  Future<void> _deleteOption(AttributeOptionCatalogItem option) async {
    final confirmed = await _confirmDelete(
      title: 'Eliminar opción',
      message: 'Se eliminara la opción ${option.value}.',
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _runMutation(
      action: () =>
          ref.read(catalogAdminProvider.notifier).deleteOption(option.id),
      successMessage: 'Opción eliminada.',
    );
  }

  Future<void> _importCsv() async {
    final projectTypeId = ref
        .read(catalogUiControllerProvider)
        .selectedImportProjectTypeId;
    if (projectTypeId == null) {
      showRemaMessage(
        context,
        'Selecciona el tipo de proyecto destino para la importación.',
      );
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

    ref.read(catalogUiControllerProvider.notifier).setImporting(true);
    try {
      final content = utf8.decode(bytes);
      final summary = await ref
          .read(catalogAdminProvider.notifier)
          .importCsv(csvContent: content, defaultProjectTypeId: projectTypeId);
      if (!mounted) {
        return;
      }
      ref
          .read(catalogUiControllerProvider.notifier)
          .setImportSummary(summary: summary, fileName: file.name);
      showRemaMessage(
        context,
        summary.hasErrors
            ? 'Importación completada con observaciones. Revisa el resumen.'
            : 'Importación CSV completada correctamente.',
      );
    } catch (error) {
      if (mounted) {
        showRemaMessage(context, 'No se pudo importar el CSV: ${_formatCatalogError(error)}');
      }
    } finally {
      ref.read(catalogUiControllerProvider.notifier).setImporting(false);
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
      saved
          ? 'Plantilla CSV lista para descarga.'
          : 'No se pudo descargar la plantilla CSV.',
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
    return values
        .map((value) {
          final escaped = value.replaceAll('"', '""');
          if (escaped.contains(',') ||
              escaped.contains('"') ||
              escaped.contains('\n')) {
            return '"$escaped"';
          }
          return escaped;
        })
        .join(',');
  }

  Future<void> _bulkAdjustPrices(
    List<ConceptTemplateCatalogItem> templates,
  ) async {
    if (templates.isEmpty) {
      showRemaMessage(
        context,
        'No hay conceptos para ajuste masivo con el filtro actual.',
      );
      return;
    }
    final percent = double.tryParse(
      _bulkPercentController.text.trim().replaceAll(',', '.'),
    );
    if (percent == null) {
      showRemaMessage(context, 'Ingresa un porcentaje válido (ej. 10 o -5).');
      return;
    }

    await _runMutation(
      action: () => ref
          .read(catalogAdminProvider.notifier)
          .bulkAdjustTemplatePrices(
            templateIds: [for (final t in templates) t.id],
            percent: percent,
          ),
      successMessage: 'Ajuste masivo aplicado a ${templates.length} conceptos.',
    );
  }

  Future<void> _runMutation({
    required Future<void> Function() action,
    required String successMessage,
  }) async {
    try {
      await action();
      if (mounted) {
        showRemaMessage(context, successMessage);
      }
    } catch (error) {
      if (mounted) {
        showRemaMessage(context, _formatCatalogError(error));
      }
    }
  }

  Future<String?> _showNameDialog({
    required String title,
    required String label,
    String initialValue = '',
  }) async {
    return showDialog<String>(
      context: context,
      builder: (_) => _TextValueDialog(
        title: title,
        label: label,
        initialValue: initialValue,
      ),
    );
  }

  Future<bool?> _confirmDelete({
    required String title,
    required String message,
    bool requireKeyword = false,
    List<String> details = const <String>[],
  }) {
    final confirmController = TextEditingController();
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: StatefulBuilder(
          builder: (context, setStateDialog) {
            final canConfirm = !requireKeyword || confirmController.text == 'ELIMINAR';
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final detail in details) Text(detail),
                ],
                if (requireKeyword) ...[
                  const SizedBox(height: 16),
                  const Text('Escribe ELIMINAR para confirmar.'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: confirmController,
                    onChanged: (_) => setStateDialog(() {}),
                    decoration: const InputDecoration(labelText: 'Confirmación'),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed: canConfirm
                          ? () => Navigator.of(dialogContext).pop(true)
                          : null,
                      child: const Text('Eliminar'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    ).whenComplete(confirmController.dispose);
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
          RemaMetricTile(
            label: 'Universos',
            value: '${snapshot.universes.length}',
          ),
          RemaMetricTile(
            label: 'Tipos de proyecto',
            value: '${snapshot.projectTypes.length}',
          ),
          RemaMetricTile(
            label: 'Conceptos',
            value: '${snapshot.templates.length}',
            backgroundColor: const Color(0xFFFFDEA0),
          ),
          RemaMetricTile(
            label: 'Atributos',
            value: '${snapshot.attributes.length}',
            backgroundColor: RemaColors.surfaceHighest,
          ),
        ];
        if (constraints.maxWidth < 960) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
            trailing: FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Nuevo'),
            ),
          ),
          const SizedBox(height: 20),
          if (snapshot.universes.isEmpty)
            const Text('Aún no hay universos registrados.')
          else
            for (final universe in snapshot.universes) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(universe.name),
                subtitle: Text(
                  '${snapshot.templatesForUniverse(universe.id).length} conceptos asociados',
                ),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    IconButton(
                      onPressed: () => onEdit(universe),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      onPressed: () => onDelete(universe),
                      icon: const Icon(Icons.delete_outline),
                    ),
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
            trailing: FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Nuevo'),
            ),
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
                    IconButton(
                      onPressed: () => onEdit(item),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      onPressed: () => onDelete(item),
                      icon: const Icon(Icons.delete_outline),
                    ),
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
    required this.bulkPercentController,
    required this.templates,
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
  final TextEditingController bulkPercentController;
  final List<ConceptTemplateCatalogItem> templates;
  final ValueChanged<String?> onUniverseChanged;
  final ValueChanged<String?> onProjectTypeChanged;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<List<ConceptTemplateCatalogItem>> onBulkAdjust;
  final VoidCallback onCreate;
  final ValueChanged<ConceptTemplateCatalogItem> onEdit;
  final ValueChanged<ConceptTemplateCatalogItem> onDelete;

  @override
  Widget build(BuildContext context) {
    final safeSelectedUniverseId = snapshot.universes.any(
      (item) => item.id == selectedUniverseId,
    )
        ? selectedUniverseId
        : null;
    final safeSelectedProjectTypeId = snapshot.projectTypes.any(
      (item) => item.id == selectedProjectTypeId,
    )
        ? selectedProjectTypeId
        : null;

    return RemaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RemaSectionHeader(
            title: 'Conceptos base',
            icon: Icons.inventory_2_outlined,
            trailing: FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Nuevo'),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey(
                    'templates-universe-${safeSelectedUniverseId ?? 'none'}-${snapshot.universes.length}',
                  ),
                  initialValue: safeSelectedUniverseId,
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
                  key: ValueKey(
                    'templates-project-type-${safeSelectedProjectTypeId ?? 'none'}-${snapshot.projectTypes.length}',
                  ),
                  initialValue: safeSelectedProjectTypeId,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de proyecto',
                  ),
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
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 220,
                child: TextField(
                  controller: bulkPercentController,
                  decoration: const InputDecoration(
                    labelText: 'Ajuste masivo % (ej. 10 o -5)',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                ),
              ),
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
                    IconButton(
                      onPressed: () => onEdit(template),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      onPressed: () => onDelete(template),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
              if (template.baseDescription.trim().isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      template.baseDescription,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
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
    final safeSelectedTemplateId = visibleTemplates.any(
      (item) => item.id == selectedTemplateId,
    )
        ? selectedTemplateId
        : null;

    return RemaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RemaSectionHeader(
            title: 'Atributos y opciones',
            icon: Icons.tune,
            trailing: FilledButton.icon(
              onPressed: safeSelectedTemplateId == null ? null : onCreateAttribute,
              icon: const Icon(Icons.add),
              label: const Text('Nuevo atributo'),
            ),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            key: ValueKey(
              'attributes-template-${safeSelectedTemplateId ?? 'none'}-${visibleTemplates.length}',
            ),
            initialValue: safeSelectedTemplateId,
            decoration: const InputDecoration(labelText: 'Concepto'),
            items: [
              for (final item in visibleTemplates)
                DropdownMenuItem(value: item.id, child: Text(item.name)),
            ],
            onChanged: onTemplateChanged,
          ),
          const SizedBox(height: 20),
          if (safeSelectedTemplateId == null)
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
              if (attribute != visibleAttributes.last)
                const SizedBox(height: 16),
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
    final safeSelectedProjectTypeId = projectTypes.any(
      (item) => item.id == selectedProjectTypeId,
    )
        ? selectedProjectTypeId
        : null;

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
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_upload_outlined),
                  label: Text(isImporting ? 'Importando...' : 'Subir CSV'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Columnas obligatorias: universe, concept, unit, base_price, attribute, option.',
          ),
          const SizedBox(height: 6),
          const Text('Columnas opcionales: project_type, base_description.'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey(
              'import-project-type-${safeSelectedProjectTypeId ?? 'none'}-${projectTypes.length}',
            ),
            initialValue: safeSelectedProjectTypeId,
            decoration: const InputDecoration(
              labelText: 'Tipo de proyecto destino',
            ),
            items: [
              for (final item in projectTypes)
                DropdownMenuItem(value: item.id, child: Text(item.name)),
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
              Expanded(
                child: Text(
                  attribute.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                onPressed: onEditAttribute,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                onPressed: onDeleteAttribute,
                icon: const Icon(Icons.delete_outline),
              ),
              FilledButton.tonalIcon(
                onPressed: onAddOption,
                icon: const Icon(Icons.add),
                label: const Text('Opción'),
              ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: RemaColors.surfaceWhite,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(option.value),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => onEditOption(option),
                          child: const Icon(Icons.edit, size: 16),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () => onDeleteOption(option),
                          child: const Icon(Icons.close, size: 16),
                        ),
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
        color: summary.hasErrors
            ? const Color(0xFFFFF1E0)
            : RemaColors.surfaceLow,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resumen de importación',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Text(
            'Universos: ${summary.createdUniverses} creados, ${summary.existingUniverses} existentes',
          ),
          Text(
            'Conceptos: ${summary.createdTemplates} creados, ${summary.existingTemplates} existentes',
          ),
          Text(
            'Atributos: ${summary.createdAttributes} creados, ${summary.existingAttributes} existentes',
          ),
          Text(
            'Opciones: ${summary.createdOptions} creadas, ${summary.existingOptions} existentes',
          ),
          if (summary.issues.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Observaciones:'),
            const SizedBox(height: 8),
            for (final issue in summary.issues.take(8))
              Text('Línea ${issue.lineNumber}: ${issue.message}'),
            if (summary.issues.length > 8)
              Text(
                '... ${summary.issues.length - 8} observaciones adicionales',
              ),
          ],
        ],
      ),
    );
  }
}

class _TextValueDialog extends StatefulWidget {
  const _TextValueDialog({
    required this.title,
    required this.label,
    required this.initialValue,
  });

  final String title;
  final String label;
  final String initialValue;

  @override
  State<_TextValueDialog> createState() => _TextValueDialogState();
}

class _TextValueDialogState extends State<_TextValueDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

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
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
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
  late final TextEditingController _nameController = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  late final TextEditingController _actionBaseController =
      TextEditingController(text: widget.initial?.actionBase ?? '');

  @override
  void dispose() {
    _nameController.dispose();
    _actionBaseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.initial == null
            ? 'Nuevo tipo de proyecto'
            : 'Editar tipo de proyecto',
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _actionBaseController,
              decoration: const InputDecoration(labelText: 'action_base'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
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
    required this.attributeLibrary,
    this.initial,
  });

  final List<UniverseCatalogItem> universes;
  final List<ProjectTypeCatalogItem> projectTypes;
  final String? initialUniverseId;
  final String? initialProjectTypeId;
  final CatalogAttributeLibrary attributeLibrary;
  final ConceptTemplateCatalogItem? initial;

  @override
  State<_ConceptDialog> createState() => _ConceptDialogState();
}

class _ConceptDialogState extends State<_ConceptDialog> {
  late String? _universeId =
      widget.initialUniverseId ??
      (widget.universes.isEmpty ? null : widget.universes.first.id);
  late String? _projectTypeId =
      widget.initialProjectTypeId ??
      (widget.projectTypes.isEmpty ? null : widget.projectTypes.first.id);
  late final TextEditingController _nameController = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  late final TextEditingController _descriptionController =
      TextEditingController(text: widget.initial?.baseDescription ?? '');
  late final TextEditingController _unitController = TextEditingController(
    text: widget.initial?.defaultUnit ?? 'm2',
  );
  late final TextEditingController _priceController = TextEditingController(
    text: widget.initial?.basePrice.toStringAsFixed(2) ?? '0',
  );
  final List<_AttributeSelectionRow> _attributeRows =
      <_AttributeSelectionRow>[];

  @override
  void initState() {
    super.initState();
    if (widget.initial == null &&
        widget.attributeLibrary.attributeNames.isNotEmpty) {
      _attributeRows.add(
        _AttributeSelectionRow(
          attributeName: widget.attributeLibrary.attributeNames.first,
        ),
      );
    }
  }

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
    final safeUniverseId = widget.universes.any((item) => item.id == _universeId)
        ? _universeId
        : null;
    final safeProjectTypeId = widget.projectTypes.any(
      (item) => item.id == _projectTypeId,
    )
        ? _projectTypeId
        : null;

    return AlertDialog(
      title: Text(
        widget.initial == null ? 'Nuevo concepto' : 'Editar concepto',
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey(
                  'concept-universe-${safeUniverseId ?? 'none'}-${widget.universes.length}',
                ),
                initialValue: safeUniverseId,
                decoration: const InputDecoration(labelText: 'Universo'),
                items: [
                  for (final item in widget.universes)
                    DropdownMenuItem(value: item.id, child: Text(item.name)),
                ],
                onChanged: (value) => setState(() => _universeId = value),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey(
                  'concept-project-type-${safeProjectTypeId ?? 'none'}-${widget.projectTypes.length}',
                ),
                initialValue: safeProjectTypeId,
                decoration: const InputDecoration(
                  labelText: 'Tipo de proyecto',
                ),
                items: [
                  for (final item in widget.projectTypes)
                    DropdownMenuItem(value: item.id, child: Text(item.name)),
                ],
                onChanged: (value) => setState(() => _projectTypeId = value),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Base description (opcional)',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _unitController,
                      decoration: const InputDecoration(labelText: 'Unidad'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _priceController,
                      decoration: const InputDecoration(
                        labelText: 'Precio base',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Atributos dinámicos',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 8),
              if (widget.attributeLibrary.attributeNames.isEmpty)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('No hay atributos disponibles para seleccionar.'),
                )
              else ...[
                for (var i = 0; i < _attributeRows.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue:
                                widget.attributeLibrary.attributeNames.contains(
                                  _attributeRows[i].attributeName,
                                )
                                ? _attributeRows[i].attributeName
                                : null,
                            decoration: const InputDecoration(
                              labelText: 'Atributo',
                            ),
                            items: [
                              for (final name
                                  in widget.attributeLibrary.attributeNames)
                                DropdownMenuItem<String>(
                                  value: name,
                                  child: Text(name),
                                ),
                            ],
                            onChanged: (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                _attributeRows[i] = _attributeRows[i].copyWith(
                                  attributeName: value,
                                  clearOption: true,
                                );
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _attributeRows[i].effectiveOption(
                              widget.attributeLibrary,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Opción',
                            ),
                            items: [
                              for (final option
                                  in widget
                                          .attributeLibrary
                                          .optionsByAttribute[_attributeRows[i]
                                          .attributeName] ??
                                      const <String>[])
                                DropdownMenuItem<String>(
                                  value: option,
                                  child: Text(option),
                                ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _attributeRows[i] = _attributeRows[i].copyWith(
                                  optionValue: value ?? '',
                                );
                              });
                            },
                          ),
                        ),
                        IconButton(
                          onPressed: () =>
                              setState(() => _attributeRows.removeAt(i)),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                      ],
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _attributeRows.add(
                          _AttributeSelectionRow(
                            attributeName:
                                widget.attributeLibrary.attributeNames.first,
                          ),
                        );
                      });
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar atributo'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            try {
              final selectedUniverseId = widget.universes.any(
                (item) => item.id == _universeId,
              )
                  ? _universeId
                  : null;
              final selectedProjectTypeId = widget.projectTypes.any(
                (item) => item.id == _projectTypeId,
              )
                  ? _projectTypeId
                  : null;

              final draft = CatalogConceptDraft.fromRaw(
                universeId: selectedUniverseId,
                projectTypeId: selectedProjectTypeId,
                name: _nameController.text,
                baseDescription: _descriptionController.text,
                defaultUnit: _unitController.text,
                basePrice: _priceController.text,
                attributes: [
                  for (final row in _attributeRows)
                    CatalogConceptAttributeSelection(
                      attributeName: row.attributeName,
                      optionValue: row.optionValue,
                    ),
                ],
              );
              Navigator.of(context).pop(draft);
            } catch (error) {
              showRemaMessage(context, '$error');
            }
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _AttributeSelectionRow {
  const _AttributeSelectionRow({
    required this.attributeName,
    this.optionValue = '',
  });

  final String attributeName;
  final String optionValue;

  _AttributeSelectionRow copyWith({
    String? attributeName,
    String? optionValue,
    bool clearOption = false,
  }) {
    return _AttributeSelectionRow(
      attributeName: attributeName ?? this.attributeName,
      optionValue: clearOption ? '' : (optionValue ?? this.optionValue),
    );
  }

  String? effectiveOption(CatalogAttributeLibrary library) {
    final options =
        library.optionsByAttribute[attributeName] ?? const <String>[];
    if (options.contains(optionValue)) {
      return optionValue;
    }
    return null;
  }
}

class _ProjectTypeFormResult {
  const _ProjectTypeFormResult({required this.name, required this.actionBase});

  final String name;
  final String actionBase;
}
