import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cotizaciones/domain/concept_generation.dart';
import '../domain/catalog_admin_models.dart';

class CatalogUiState {
  const CatalogUiState({
    this.selectedUniverseId,
    this.selectedProjectTypeId,
    this.selectedTemplateId,
    this.selectedImportProjectTypeId,
    this.templateSearch = '',
    this.lastImportSummary,
    this.lastImportFileName,
    this.isImporting = false,
  });

  final String? selectedUniverseId;
  final String? selectedProjectTypeId;
  final String? selectedTemplateId;
  final String? selectedImportProjectTypeId;
  final String templateSearch;
  final CatalogImportSummary? lastImportSummary;
  final String? lastImportFileName;
  final bool isImporting;

  CatalogUiState copyWith({
    String? selectedUniverseId,
    String? selectedProjectTypeId,
    String? selectedTemplateId,
    String? selectedImportProjectTypeId,
    String? templateSearch,
    CatalogImportSummary? lastImportSummary,
    String? lastImportFileName,
    bool? isImporting,
    bool clearImportSummary = false,
  }) {
    return CatalogUiState(
      selectedUniverseId: selectedUniverseId ?? this.selectedUniverseId,
      selectedProjectTypeId:
          selectedProjectTypeId ?? this.selectedProjectTypeId,
      selectedTemplateId: selectedTemplateId ?? this.selectedTemplateId,
      selectedImportProjectTypeId:
          selectedImportProjectTypeId ?? this.selectedImportProjectTypeId,
      templateSearch: templateSearch ?? this.templateSearch,
      lastImportSummary: clearImportSummary
          ? null
          : (lastImportSummary ?? this.lastImportSummary),
      lastImportFileName: clearImportSummary
          ? null
          : (lastImportFileName ?? this.lastImportFileName),
      isImporting: isImporting ?? this.isImporting,
    );
  }
}

class CatalogViewData {
  const CatalogViewData({
    required this.selectedUniverseId,
    required this.selectedProjectTypeId,
    required this.selectedTemplateId,
    required this.selectedImportProjectTypeId,
    required this.visibleTemplates,
    required this.filteredTemplates,
    required this.visibleAttributes,
  });

  final String? selectedUniverseId;
  final String? selectedProjectTypeId;
  final String? selectedTemplateId;
  final String? selectedImportProjectTypeId;
  final List<ConceptTemplateCatalogItem> visibleTemplates;
  final List<ConceptTemplateCatalogItem> filteredTemplates;
  final List<ConceptAttributeCatalogItem> visibleAttributes;
}

final catalogUiControllerProvider =
    NotifierProvider<CatalogUiController, CatalogUiState>(
      CatalogUiController.new,
    );

class CatalogUiController extends Notifier<CatalogUiState> {
  @override
  CatalogUiState build() => const CatalogUiState();

  void syncWithSnapshot(ConceptCatalogSnapshot snapshot) {
    var changed = false;
    var nextUniverseId = state.selectedUniverseId;
    var nextProjectTypeId = state.selectedProjectTypeId;
    var nextTemplateId = state.selectedTemplateId;
    var nextImportProjectTypeId = state.selectedImportProjectTypeId;

    if (nextUniverseId == null ||
        !snapshot.universes.any((item) => item.id == nextUniverseId)) {
      nextUniverseId = snapshot.universes.isEmpty
          ? null
          : snapshot.universes.first.id;
      changed = true;
    }

    if (nextProjectTypeId == null ||
        !snapshot.projectTypes.any((item) => item.id == nextProjectTypeId)) {
      nextProjectTypeId = snapshot.projectTypes.isEmpty
          ? null
          : snapshot.projectTypes.first.id;
      changed = true;
    }

    final templatesForUniverse = nextUniverseId == null
        ? snapshot.templates
        : snapshot.templatesForUniverse(nextUniverseId);
    if (nextTemplateId == null ||
        !templatesForUniverse.any((item) => item.id == nextTemplateId)) {
      nextTemplateId = templatesForUniverse.isEmpty
          ? null
          : templatesForUniverse.first.id;
      changed = true;
    }

    if (nextImportProjectTypeId == null ||
        !snapshot.projectTypes.any(
          (item) => item.id == nextImportProjectTypeId,
        )) {
      nextImportProjectTypeId = snapshot.projectTypes.isEmpty
          ? null
          : snapshot.projectTypes.first.id;
      changed = true;
    }

    if (!changed) {
      return;
    }

    state = state.copyWith(
      selectedUniverseId: nextUniverseId,
      selectedProjectTypeId: nextProjectTypeId,
      selectedTemplateId: nextTemplateId,
      selectedImportProjectTypeId: nextImportProjectTypeId,
    );
  }

  CatalogViewData viewDataFor(ConceptCatalogSnapshot snapshot) {
    final selectedUniverseId =
        snapshot.universes.any((item) => item.id == state.selectedUniverseId)
        ? state.selectedUniverseId
        : (snapshot.universes.isEmpty ? null : snapshot.universes.first.id);
    final selectedProjectTypeId =
        snapshot.projectTypes.any(
          (item) => item.id == state.selectedProjectTypeId,
        )
        ? state.selectedProjectTypeId
        : (snapshot.projectTypes.isEmpty
              ? null
              : snapshot.projectTypes.first.id);
    final selectedImportProjectTypeId =
        snapshot.projectTypes.any(
          (item) => item.id == state.selectedImportProjectTypeId,
        )
        ? state.selectedImportProjectTypeId
        : (snapshot.projectTypes.isEmpty
              ? null
              : snapshot.projectTypes.first.id);

    final visibleTemplates = selectedUniverseId == null
        ? snapshot.templates
        : snapshot.templatesForUniverse(selectedUniverseId);

    final selectedTemplateId =
        visibleTemplates.any((item) => item.id == state.selectedTemplateId)
        ? state.selectedTemplateId
        : (visibleTemplates.isEmpty ? null : visibleTemplates.first.id);

    var filteredTemplates = selectedProjectTypeId == null
        ? visibleTemplates
        : visibleTemplates
              .where((item) => item.projectTypeId == selectedProjectTypeId)
              .toList();

    final search = state.templateSearch.trim().toLowerCase();
    if (search.isNotEmpty) {
      filteredTemplates = filteredTemplates.where((item) {
        final haystack =
            '${item.name} ${item.baseDescription} ${item.defaultUnit}'
                .toLowerCase();
        return haystack.contains(search);
      }).toList();
    }

    final visibleAttributes = selectedTemplateId == null
        ? const <ConceptAttributeCatalogItem>[]
        : snapshot.attributesForTemplate(selectedTemplateId);

    return CatalogViewData(
      selectedUniverseId: selectedUniverseId,
      selectedProjectTypeId: selectedProjectTypeId,
      selectedTemplateId: selectedTemplateId,
      selectedImportProjectTypeId: selectedImportProjectTypeId,
      visibleTemplates: visibleTemplates,
      filteredTemplates: filteredTemplates,
      visibleAttributes: visibleAttributes,
    );
  }

  void selectUniverse(String? value) {
    state = state.copyWith(selectedUniverseId: value, selectedTemplateId: null);
  }

  void selectProjectType(String? value) {
    state = state.copyWith(selectedProjectTypeId: value);
  }

  void selectTemplate(String? value) {
    state = state.copyWith(selectedTemplateId: value);
  }

  void selectImportProjectType(String? value) {
    state = state.copyWith(selectedImportProjectTypeId: value);
  }

  void changeTemplateSearch(String value) {
    state = state.copyWith(templateSearch: value.trim().toLowerCase());
  }

  void setImporting(bool value) {
    state = state.copyWith(isImporting: value);
  }

  void setImportSummary({
    required CatalogImportSummary summary,
    required String fileName,
  }) {
    state = state.copyWith(
      lastImportSummary: summary,
      lastImportFileName: fileName,
    );
  }
}
