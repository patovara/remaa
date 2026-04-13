import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rema_app/features/catalogo/presentation/catalog_ui_controller.dart';
import 'package:rema_app/features/cotizaciones/domain/concept_generation.dart';

void main() {
  ConceptCatalogSnapshot snapshotWithData() {
    return const ConceptCatalogSnapshot(
      universes: [
        UniverseCatalogItem(id: 'u1', name: 'Universo 1'),
        UniverseCatalogItem(id: 'u2', name: 'Universo 2'),
      ],
      projectTypes: [
        ProjectTypeCatalogItem(
          id: 'p1',
          name: 'Remodelacion',
          actionBase: 'Suministro',
        ),
      ],
      closures: [
        ConceptClosureCatalogItem(id: 'c1', text: 'Cierre base'),
      ],
      templates: [
        ConceptTemplateCatalogItem(
          id: 't1',
          universeId: 'u1',
          projectTypeId: 'p1',
          closureId: 'c1',
          name: 'Concepto 1',
          baseDescription: 'Descripcion',
          defaultUnit: 'm2',
          basePrice: 100,
        ),
      ],
      attributes: [
        ConceptAttributeCatalogItem(
          id: 'a1',
          templateId: 't1',
          name: 'Acabado',
        ),
      ],
      options: [
        AttributeOptionCatalogItem(id: 'o1', attributeId: 'a1', value: 'Mate'),
      ],
    );
  }

  test('selectUniverse permite limpiar a null y limpia template', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(catalogUiControllerProvider.notifier);

    notifier.selectUniverse('u1');
    notifier.selectTemplate('t1');
    notifier.selectUniverse(null);

    final state = container.read(catalogUiControllerProvider);
    expect(state.selectedUniverseId, isNull);
    expect(state.selectedTemplateId, isNull);
  });

  test('selectProjectType permite limpiar a null', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(catalogUiControllerProvider.notifier);

    notifier.selectProjectType('p1');
    notifier.selectProjectType(null);

    final state = container.read(catalogUiControllerProvider);
    expect(state.selectedProjectTypeId, isNull);
  });

  test('syncWithSnapshot corrige ids obsoletos', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(catalogUiControllerProvider.notifier);

    notifier.selectUniverse('missing-u');
    notifier.selectProjectType('missing-p');
    notifier.selectTemplate('missing-t');
    notifier.selectImportProjectType('missing-p');

    final snapshot = snapshotWithData();
    notifier.syncWithSnapshot(snapshot);

    final state = container.read(catalogUiControllerProvider);
    expect(state.selectedUniverseId, 'u1');
    expect(state.selectedProjectTypeId, 'p1');
    expect(state.selectedTemplateId, 't1');
    expect(state.selectedImportProjectTypeId, 'p1');
  });

  test('viewDataFor no revienta con filtros vacios', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(catalogUiControllerProvider.notifier);

    notifier.selectUniverse('u2');
    notifier.selectProjectType('p1');
    notifier.selectTemplate('t1');

    final snapshot = snapshotWithData();
    final viewData = notifier.viewDataFor(snapshot);

    expect(viewData.visibleTemplates, isEmpty);
    expect(viewData.selectedTemplateId, isNull);
    expect(viewData.visibleAttributes, isEmpty);
  });
}
