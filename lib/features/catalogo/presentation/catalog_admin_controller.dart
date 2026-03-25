import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cotizaciones/presentation/concepts_catalog_controller.dart';
import '../../cotizaciones/domain/concept_generation.dart';
import '../data/catalog_admin_repository.dart';
import '../domain/catalog_admin_models.dart';

final catalogAdminRepositoryProvider = Provider<CatalogAdminRepository>(
  (ref) => CatalogAdminRepository(),
);

final catalogAdminProvider = AsyncNotifierProvider<CatalogAdminController, ConceptCatalogSnapshot>(
  CatalogAdminController.new,
);

class CatalogAdminController extends AsyncNotifier<ConceptCatalogSnapshot> {
  late final CatalogAdminRepository _repository = ref.read(catalogAdminRepositoryProvider);

  @override
  FutureOr<ConceptCatalogSnapshot> build() {
    return _repository.fetchCatalog();
  }

  Future<void> reload() async {
    state = await AsyncValue.guard(_repository.fetchCatalog);
    ref.invalidate(conceptsCatalogProvider);
  }

  Future<void> createUniverse(String name) => _mutate(() => _repository.createUniverse(name));

  Future<void> updateUniverse({required String id, required String name}) =>
      _mutate(() => _repository.updateUniverse(id: id, name: name));

  Future<void> deleteUniverse(String id) => _mutate(() => _repository.deleteUniverse(id));

  Future<void> createProjectType({required String name, required String actionBase}) =>
      _mutate(() => _repository.createProjectType(name: name, actionBase: actionBase));

  Future<void> updateProjectType({required String id, required String name, required String actionBase}) =>
      _mutate(() => _repository.updateProjectType(id: id, name: name, actionBase: actionBase));

  Future<void> deleteProjectType(String id) => _mutate(() => _repository.deleteProjectType(id));

  Future<void> createTemplate({
    required String universeId,
    required String projectTypeId,
    required String name,
    required String baseDescription,
    required String defaultUnit,
    required double basePrice,
  }) =>
      _mutate(
        () => _repository.createTemplate(
          universeId: universeId,
          projectTypeId: projectTypeId,
          name: name,
          baseDescription: baseDescription,
          defaultUnit: defaultUnit,
          basePrice: basePrice,
        ),
      );

  Future<void> updateTemplate({
    required String id,
    required String universeId,
    required String projectTypeId,
    required String name,
    required String baseDescription,
    required String defaultUnit,
    required double basePrice,
  }) =>
      _mutate(
        () => _repository.updateTemplate(
          id: id,
          universeId: universeId,
          projectTypeId: projectTypeId,
          name: name,
          baseDescription: baseDescription,
          defaultUnit: defaultUnit,
          basePrice: basePrice,
        ),
      );

  Future<void> deleteTemplate(String id) => _mutate(() => _repository.deleteTemplate(id));

  Future<void> createAttribute({required String templateId, required String name}) =>
      _mutate(() => _repository.createAttribute(templateId: templateId, name: name));

  Future<void> updateAttribute({required String id, required String templateId, required String name}) =>
      _mutate(() => _repository.updateAttribute(id: id, templateId: templateId, name: name));

  Future<void> deleteAttribute(String id) => _mutate(() => _repository.deleteAttribute(id));

  Future<void> createOption({required String attributeId, required String value}) =>
      _mutate(() => _repository.createOption(attributeId: attributeId, value: value));

  Future<void> updateOption({required String id, required String attributeId, required String value}) =>
      _mutate(() => _repository.updateOption(id: id, attributeId: attributeId, value: value));

  Future<void> deleteOption(String id) => _mutate(() => _repository.deleteOption(id));

  Future<CatalogImportSummary> importCsv({required String csvContent, required String defaultProjectTypeId}) async {
    final summary = await _repository.importCsv(csvContent: csvContent, defaultProjectTypeId: defaultProjectTypeId);
    await reload();
    return summary;
  }

  Future<void> bulkAdjustTemplatePrices({required List<String> templateIds, required double percent}) async {
    await _repository.bulkAdjustTemplatePrices(templateIds: templateIds, percent: percent);
    await reload();
  }

  Future<void> _mutate(Future<void> Function() operation) async {
    await operation();
    await reload();
  }
}