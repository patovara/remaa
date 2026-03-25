import '../../../core/config/supabase_bootstrap.dart';
import '../../../core/logging/app_logger.dart';
import '../../cotizaciones/data/concepts_catalog_repository.dart';
import '../../cotizaciones/domain/concept_generation.dart';
import '../domain/catalog_admin_models.dart';
import '../domain/catalog_csv_parser.dart';

class CatalogAdminRepository {
  final ConceptsCatalogRepository _reader = ConceptsCatalogRepository();

  static ConceptCatalogSnapshot? _localSnapshot;

  Future<ConceptCatalogSnapshot> fetchCatalog() async {
    final client = SupabaseBootstrap.client;
    if (client != null) {
      return _reader.fetchCatalog();
    }

    _localSnapshot ??= _cloneSnapshot(await _reader.fetchCatalog());
    return _cloneSnapshot(_localSnapshot!);
  }

  Future<void> createUniverse(String name) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw StateError('El nombre del universo es obligatorio.');
    }

    final client = SupabaseBootstrap.client;
    if (client == null) {
      final snapshot = await fetchCatalog();
      if (_containsUniverse(snapshot, cleanName)) {
        throw StateError('El universo ya existe.');
      }
      _localSnapshot = ConceptCatalogSnapshot(
        universes: [
          ...snapshot.universes,
          UniverseCatalogItem(id: _localId('universe'), name: cleanName),
        ],
        projectTypes: [...snapshot.projectTypes],
        closures: [...snapshot.closures],
        templates: [...snapshot.templates],
        attributes: [...snapshot.attributes],
        options: [...snapshot.options],
      );
      return;
    }

    if (_containsUniverse(await fetchCatalog(), cleanName)) {
      throw StateError('El universo ya existe.');
    }

    await client.from('universes').insert({'name': cleanName});
  }

  Future<void> updateUniverse({required String id, required String name}) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw StateError('El nombre del universo es obligatorio.');
    }

    final snapshot = await fetchCatalog();
    final duplicated = snapshot.universes.any(
      (item) => item.id != id && _normalize(item.name) == _normalize(cleanName),
    );
    if (duplicated) {
      throw StateError('Ya existe otro universo con ese nombre.');
    }

    final client = SupabaseBootstrap.client;
    if (client == null) {
      _localSnapshot = ConceptCatalogSnapshot(
        universes: [
          for (final item in snapshot.universes)
            if (item.id == id) UniverseCatalogItem(id: item.id, name: cleanName) else item,
        ],
        projectTypes: [...snapshot.projectTypes],
        closures: [...snapshot.closures],
        templates: [...snapshot.templates],
        attributes: [...snapshot.attributes],
        options: [...snapshot.options],
      );
      return;
    }

    await client.from('universes').update({'name': cleanName}).eq('id', id);
  }

  Future<void> deleteUniverse(String id) async {
    final snapshot = await fetchCatalog();
    final hasTemplate = snapshot.templates.any((item) => item.universeId == id);
    if (hasTemplate) {
      throw StateError('No puedes eliminar un universo con conceptos asociados.');
    }

    final client = SupabaseBootstrap.client;
    if (client == null) {
      _localSnapshot = ConceptCatalogSnapshot(
        universes: [for (final item in snapshot.universes) if (item.id != id) item],
        projectTypes: [...snapshot.projectTypes],
        closures: [...snapshot.closures],
        templates: [...snapshot.templates],
        attributes: [...snapshot.attributes],
        options: [...snapshot.options],
      );
      return;
    }

    final quotes = await client.from('quotes').select('id').eq('universe_id', id).limit(1);
    if ((quotes as List).isNotEmpty) {
      throw StateError('No puedes eliminar un universo que ya fue usado en cotizaciones.');
    }
    await client.from('universes').delete().eq('id', id);
  }

  Future<void> createProjectType({required String name, required String actionBase}) async {
    final cleanName = name.trim();
    final cleanAction = actionBase.trim();
    if (cleanName.isEmpty || cleanAction.isEmpty) {
      throw StateError('Nombre y action_base son obligatorios.');
    }

    final snapshot = await fetchCatalog();
    if (snapshot.projectTypes.any((item) => _normalize(item.name) == _normalize(cleanName))) {
      throw StateError('El tipo de proyecto ya existe.');
    }

    final client = SupabaseBootstrap.client;
    if (client == null) {
      _localSnapshot = ConceptCatalogSnapshot(
        universes: [...snapshot.universes],
        projectTypes: [
          ...snapshot.projectTypes,
          ProjectTypeCatalogItem(id: _localId('project-type'), name: cleanName, actionBase: cleanAction),
        ],
        closures: [...snapshot.closures],
        templates: [...snapshot.templates],
        attributes: [...snapshot.attributes],
        options: [...snapshot.options],
      );
      return;
    }

    await client.from('project_types').insert({'name': cleanName, 'action_base': cleanAction});
  }

  Future<void> updateProjectType({required String id, required String name, required String actionBase}) async {
    final cleanName = name.trim();
    final cleanAction = actionBase.trim();
    if (cleanName.isEmpty || cleanAction.isEmpty) {
      throw StateError('Nombre y action_base son obligatorios.');
    }

    final snapshot = await fetchCatalog();
    final duplicated = snapshot.projectTypes.any(
      (item) => item.id != id && _normalize(item.name) == _normalize(cleanName),
    );
    if (duplicated) {
      throw StateError('Ya existe otro tipo de proyecto con ese nombre.');
    }

    final client = SupabaseBootstrap.client;
    if (client == null) {
      _localSnapshot = ConceptCatalogSnapshot(
        universes: [...snapshot.universes],
        projectTypes: [
          for (final item in snapshot.projectTypes)
            if (item.id == id)
              ProjectTypeCatalogItem(id: item.id, name: cleanName, actionBase: cleanAction)
            else
              item,
        ],
        closures: [...snapshot.closures],
        templates: [...snapshot.templates],
        attributes: [...snapshot.attributes],
        options: [...snapshot.options],
      );
      return;
    }

    await client.from('project_types').update({'name': cleanName, 'action_base': cleanAction}).eq('id', id);
  }

  Future<void> deleteProjectType(String id) async {
    final snapshot = await fetchCatalog();
    final hasTemplate = snapshot.templates.any((item) => item.projectTypeId == id);
    if (hasTemplate) {
      throw StateError('No puedes eliminar un tipo de proyecto con conceptos asociados.');
    }

    final client = SupabaseBootstrap.client;
    if (client == null) {
      _localSnapshot = ConceptCatalogSnapshot(
        universes: [...snapshot.universes],
        projectTypes: [for (final item in snapshot.projectTypes) if (item.id != id) item],
        closures: [...snapshot.closures],
        templates: [...snapshot.templates],
        attributes: [...snapshot.attributes],
        options: [...snapshot.options],
      );
      return;
    }

    final quotes = await client.from('quotes').select('id').eq('project_type_id', id).limit(1);
    if ((quotes as List).isNotEmpty) {
      throw StateError('No puedes eliminar un tipo de proyecto usado en cotizaciones.');
    }
    await client.from('project_types').delete().eq('id', id);
  }

  Future<void> createTemplate({
    required String universeId,
    required String projectTypeId,
    required String name,
    required String baseDescription,
    required String defaultUnit,
    required double basePrice,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty || defaultUnit.trim().isEmpty) {
      throw StateError('Nombre, tipo de proyecto y unidad son obligatorios.');
    }

    final snapshot = await fetchCatalog();
    final exists = snapshot.templates.any(
      (item) => item.universeId == universeId && _normalize(item.name) == _normalize(cleanName),
    );
    if (exists) {
      throw StateError('Ya existe un concepto con ese nombre en el universo seleccionado.');
    }

    final closureId = await _ensureDefaultClosure();
    final refreshedSnapshot = await fetchCatalog();
    final client = SupabaseBootstrap.client;
    if (client == null) {
      _localSnapshot = ConceptCatalogSnapshot(
        universes: [...refreshedSnapshot.universes],
        projectTypes: [...refreshedSnapshot.projectTypes],
        closures: [...refreshedSnapshot.closures],
        templates: [
          ...refreshedSnapshot.templates,
          ConceptTemplateCatalogItem(
            id: _localId('template'),
            universeId: universeId,
            projectTypeId: projectTypeId,
            closureId: closureId,
            name: cleanName,
            baseDescription: baseDescription.trim(),
            defaultUnit: defaultUnit.trim(),
            basePrice: basePrice,
          ),
        ],
        attributes: [...refreshedSnapshot.attributes],
        options: [...refreshedSnapshot.options],
      );
      return;
    }

    await client.from('concept_templates').insert({
      'universe_id': universeId,
      'project_type_id': projectTypeId,
      'closure_id': closureId,
      'name': cleanName,
      'base_description': baseDescription.trim(),
      'default_unit': defaultUnit.trim(),
      'base_price': basePrice,
    });
  }

  Future<void> updateTemplate({
    required String id,
    required String universeId,
    required String projectTypeId,
    required String name,
    required String baseDescription,
    required String defaultUnit,
    required double basePrice,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty || defaultUnit.trim().isEmpty) {
      throw StateError('Nombre y unidad son obligatorios.');
    }

    final snapshot = await fetchCatalog();
    final duplicated = snapshot.templates.any(
      (item) => item.id != id && item.universeId == universeId && _normalize(item.name) == _normalize(cleanName),
    );
    if (duplicated) {
      throw StateError('Ya existe otro concepto con ese nombre en el universo seleccionado.');
    }

    final client = SupabaseBootstrap.client;
    if (client == null) {
      _localSnapshot = ConceptCatalogSnapshot(
        universes: [...snapshot.universes],
        projectTypes: [...snapshot.projectTypes],
        closures: [...snapshot.closures],
        templates: [
          for (final item in snapshot.templates)
            if (item.id == id)
              ConceptTemplateCatalogItem(
                id: item.id,
                universeId: universeId,
                projectTypeId: projectTypeId,
                closureId: item.closureId,
                name: cleanName,
                baseDescription: baseDescription.trim(),
                defaultUnit: defaultUnit.trim(),
                basePrice: basePrice,
              )
            else
              item,
        ],
        attributes: [...snapshot.attributes],
        options: [...snapshot.options],
      );
      return;
    }

    await client.from('concept_templates').update({
      'universe_id': universeId,
      'project_type_id': projectTypeId,
      'name': cleanName,
      'base_description': baseDescription.trim(),
      'default_unit': defaultUnit.trim(),
      'base_price': basePrice,
    }).eq('id', id);
  }

  Future<void> deleteTemplate(String id) async {
    final snapshot = await fetchCatalog();
    final hasAttributes = snapshot.attributes.any((item) => item.templateId == id);
    if (hasAttributes) {
      throw StateError('Elimina primero los atributos del concepto.');
    }

    final client = SupabaseBootstrap.client;
    if (client == null) {
      _localSnapshot = ConceptCatalogSnapshot(
        universes: [...snapshot.universes],
        projectTypes: [...snapshot.projectTypes],
        closures: [...snapshot.closures],
        templates: [for (final item in snapshot.templates) if (item.id != id) item],
        attributes: [...snapshot.attributes],
        options: [...snapshot.options],
      );
      return;
    }

    await client.from('concept_templates').delete().eq('id', id);
  }

  Future<void> createAttribute({required String templateId, required String name}) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw StateError('El nombre del atributo es obligatorio.');
    }

    final snapshot = await fetchCatalog();
    final exists = snapshot.attributes.any(
      (item) => item.templateId == templateId && _normalize(item.name) == _normalize(cleanName),
    );
    if (exists) {
      throw StateError('El atributo ya existe para este concepto.');
    }

    final client = SupabaseBootstrap.client;
    if (client == null) {
      _localSnapshot = ConceptCatalogSnapshot(
        universes: [...snapshot.universes],
        projectTypes: [...snapshot.projectTypes],
        closures: [...snapshot.closures],
        templates: [...snapshot.templates],
        attributes: [
          ...snapshot.attributes,
          ConceptAttributeCatalogItem(id: _localId('attribute'), templateId: templateId, name: cleanName),
        ],
        options: [...snapshot.options],
      );
      return;
    }

    await client.from('concept_attributes').insert({
      'concept_template_id': templateId,
      'name': cleanName,
    });
  }

  Future<void> updateAttribute({required String id, required String templateId, required String name}) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw StateError('El nombre del atributo es obligatorio.');
    }

    final snapshot = await fetchCatalog();
    final duplicated = snapshot.attributes.any(
      (item) => item.id != id && item.templateId == templateId && _normalize(item.name) == _normalize(cleanName),
    );
    if (duplicated) {
      throw StateError('Ya existe otro atributo con ese nombre.');
    }

    final client = SupabaseBootstrap.client;
    if (client == null) {
      _localSnapshot = ConceptCatalogSnapshot(
        universes: [...snapshot.universes],
        projectTypes: [...snapshot.projectTypes],
        closures: [...snapshot.closures],
        templates: [...snapshot.templates],
        attributes: [
          for (final item in snapshot.attributes)
            if (item.id == id) ConceptAttributeCatalogItem(id: item.id, templateId: templateId, name: cleanName) else item,
        ],
        options: [...snapshot.options],
      );
      return;
    }

    await client.from('concept_attributes').update({'name': cleanName}).eq('id', id);
  }

  Future<void> deleteAttribute(String id) async {
    final snapshot = await fetchCatalog();
    final hasOptions = snapshot.options.any((item) => item.attributeId == id);
    if (hasOptions) {
      throw StateError('Elimina primero las opciones del atributo.');
    }

    final client = SupabaseBootstrap.client;
    if (client == null) {
      _localSnapshot = ConceptCatalogSnapshot(
        universes: [...snapshot.universes],
        projectTypes: [...snapshot.projectTypes],
        closures: [...snapshot.closures],
        templates: [...snapshot.templates],
        attributes: [for (final item in snapshot.attributes) if (item.id != id) item],
        options: [...snapshot.options],
      );
      return;
    }

    await client.from('concept_attributes').delete().eq('id', id);
  }

  Future<void> createOption({required String attributeId, required String value}) async {
    final cleanValue = value.trim();
    if (cleanValue.isEmpty) {
      throw StateError('La opcion es obligatoria.');
    }

    final snapshot = await fetchCatalog();
    final exists = snapshot.options.any(
      (item) => item.attributeId == attributeId && _normalize(item.value) == _normalize(cleanValue),
    );
    if (exists) {
      throw StateError('La opcion ya existe para este atributo.');
    }

    final client = SupabaseBootstrap.client;
    if (client == null) {
      _localSnapshot = ConceptCatalogSnapshot(
        universes: [...snapshot.universes],
        projectTypes: [...snapshot.projectTypes],
        closures: [...snapshot.closures],
        templates: [...snapshot.templates],
        attributes: [...snapshot.attributes],
        options: [
          ...snapshot.options,
          AttributeOptionCatalogItem(id: _localId('option'), attributeId: attributeId, value: cleanValue),
        ],
      );
      return;
    }

    await client.from('attribute_options').insert({'attribute_id': attributeId, 'value': cleanValue});
  }

  Future<void> updateOption({required String id, required String attributeId, required String value}) async {
    final cleanValue = value.trim();
    if (cleanValue.isEmpty) {
      throw StateError('La opcion es obligatoria.');
    }

    final snapshot = await fetchCatalog();
    final duplicated = snapshot.options.any(
      (item) => item.id != id && item.attributeId == attributeId && _normalize(item.value) == _normalize(cleanValue),
    );
    if (duplicated) {
      throw StateError('Ya existe otra opcion con ese valor.');
    }

    final client = SupabaseBootstrap.client;
    if (client == null) {
      _localSnapshot = ConceptCatalogSnapshot(
        universes: [...snapshot.universes],
        projectTypes: [...snapshot.projectTypes],
        closures: [...snapshot.closures],
        templates: [...snapshot.templates],
        attributes: [...snapshot.attributes],
        options: [
          for (final item in snapshot.options)
            if (item.id == id) AttributeOptionCatalogItem(id: item.id, attributeId: attributeId, value: cleanValue) else item,
        ],
      );
      return;
    }

    await client.from('attribute_options').update({'value': cleanValue}).eq('id', id);
  }

  Future<void> deleteOption(String id) async {
    final snapshot = await fetchCatalog();
    final client = SupabaseBootstrap.client;
    if (client == null) {
      _localSnapshot = ConceptCatalogSnapshot(
        universes: [...snapshot.universes],
        projectTypes: [...snapshot.projectTypes],
        closures: [...snapshot.closures],
        templates: [...snapshot.templates],
        attributes: [...snapshot.attributes],
        options: [for (final item in snapshot.options) if (item.id != id) item],
      );
      return;
    }

    await client.from('attribute_options').delete().eq('id', id);
  }

  Future<CatalogImportSummary> importCsv({
    required String csvContent,
    required String defaultProjectTypeId,
  }) async {
    final parsed = parseCatalogCsv(csvContent);
    final issues = <CatalogImportIssue>[...parsed.issues];
    if (parsed.rows.isEmpty) {
      return CatalogImportSummary(
        createdUniverses: 0,
        existingUniverses: 0,
        createdTemplates: 0,
        existingTemplates: 0,
        createdAttributes: 0,
        existingAttributes: 0,
        createdOptions: 0,
        existingOptions: 0,
        issues: issues,
      );
    }

    var snapshot = await fetchCatalog();
    var createdUniverses = 0;
    var existingUniverses = 0;
    var createdTemplates = 0;
    var existingTemplates = 0;
    var createdAttributes = 0;
    var existingAttributes = 0;
    var createdOptions = 0;
    var existingOptions = 0;

    for (final row in parsed.rows) {
      try {
        var universe = _findUniverse(snapshot, row.universe);
        if (universe == null) {
          await createUniverse(row.universe);
          createdUniverses++;
          snapshot = await fetchCatalog();
          universe = _findUniverse(snapshot, row.universe);
        } else {
          existingUniverses++;
        }

        if (universe == null) {
          issues.add(CatalogImportIssue(lineNumber: row.lineNumber, message: 'No se pudo resolver el universo.'));
          continue;
        }

        var projectTypeId = defaultProjectTypeId;
        if (row.projectType != null && row.projectType!.trim().isNotEmpty) {
          final matchedProjectType = _findProjectType(snapshot, row.projectType!);
          if (matchedProjectType == null) {
            issues.add(
              CatalogImportIssue(
                lineNumber: row.lineNumber,
                message: 'project_type no existe: ${row.projectType}',
              ),
            );
            continue;
          }
          projectTypeId = matchedProjectType.id;
        }

        var template = _findTemplateByScope(snapshot, universe.id, row.concept, projectTypeId: projectTypeId);
        if (template == null) {
          await createTemplate(
            universeId: universe.id,
            projectTypeId: projectTypeId,
            name: row.concept,
            baseDescription: row.baseDescription ?? '',
            defaultUnit: row.unit,
            basePrice: row.basePrice,
          );
          createdTemplates++;
          snapshot = await fetchCatalog();
          template = _findTemplateByScope(snapshot, universe.id, row.concept, projectTypeId: projectTypeId);
        } else {
          existingTemplates++;
        }

        if (template == null) {
          issues.add(CatalogImportIssue(lineNumber: row.lineNumber, message: 'No se pudo resolver el concepto.'));
          continue;
        }

        var attribute = _findAttribute(snapshot, template.id, row.attribute);
        if (attribute == null) {
          await createAttribute(templateId: template.id, name: row.attribute);
          createdAttributes++;
          snapshot = await fetchCatalog();
          attribute = _findAttribute(snapshot, template.id, row.attribute);
        } else {
          existingAttributes++;
        }

        if (attribute == null) {
          issues.add(CatalogImportIssue(lineNumber: row.lineNumber, message: 'No se pudo resolver el atributo.'));
          continue;
        }

        final option = _findOption(snapshot, attribute.id, row.option);
        if (option == null) {
          await createOption(attributeId: attribute.id, value: row.option);
          createdOptions++;
          snapshot = await fetchCatalog();
        } else {
          existingOptions++;
        }
      } catch (error) {
        AppLogger.error('catalog_csv_import_row_failed', data: {
          'line': row.lineNumber,
          'error': error.toString(),
        });
        issues.add(CatalogImportIssue(lineNumber: row.lineNumber, message: error.toString()));
      }
    }

    return CatalogImportSummary(
      createdUniverses: createdUniverses,
      existingUniverses: existingUniverses,
      createdTemplates: createdTemplates,
      existingTemplates: existingTemplates,
      createdAttributes: createdAttributes,
      existingAttributes: existingAttributes,
      createdOptions: createdOptions,
      existingOptions: existingOptions,
      issues: issues,
    );
  }

  UniverseCatalogItem? _findUniverse(ConceptCatalogSnapshot snapshot, String name) {
    for (final item in snapshot.universes) {
      if (_normalize(item.name) == _normalize(name)) {
        return item;
      }
    }
    return null;
  }

  ConceptTemplateCatalogItem? _findTemplateByScope(
    ConceptCatalogSnapshot snapshot,
    String universeId,
    String name, {
    required String? projectTypeId,
  }) {
    for (final item in snapshot.templates) {
      final typeMatches = projectTypeId == null || item.projectTypeId == projectTypeId;
      if (item.universeId == universeId && typeMatches && _normalize(item.name) == _normalize(name)) {
        return item;
      }
    }
    return null;
  }

  ProjectTypeCatalogItem? _findProjectType(ConceptCatalogSnapshot snapshot, String name) {
    for (final item in snapshot.projectTypes) {
      if (_normalize(item.name) == _normalize(name)) {
        return item;
      }
    }
    return null;
  }

  Future<void> bulkAdjustTemplatePrices({required List<String> templateIds, required double percent}) async {
    if (templateIds.isEmpty) {
      return;
    }

    final snapshot = await fetchCatalog();
    final factor = 1 + (percent / 100);
    final client = SupabaseBootstrap.client;

    if (client == null) {
      _localSnapshot = ConceptCatalogSnapshot(
        universes: [...snapshot.universes],
        projectTypes: [...snapshot.projectTypes],
        closures: [...snapshot.closures],
        templates: [
          for (final item in snapshot.templates)
            if (templateIds.contains(item.id))
              ConceptTemplateCatalogItem(
                id: item.id,
                universeId: item.universeId,
                projectTypeId: item.projectTypeId,
                closureId: item.closureId,
                name: item.name,
                baseDescription: item.baseDescription,
                defaultUnit: item.defaultUnit,
                basePrice: double.parse((item.basePrice * factor).toStringAsFixed(2)),
              )
            else
              item,
        ],
        attributes: [...snapshot.attributes],
        options: [...snapshot.options],
      );
      return;
    }

    for (final template in snapshot.templates) {
      if (!templateIds.contains(template.id)) {
        continue;
      }
      final updatedPrice = double.parse((template.basePrice * factor).toStringAsFixed(2));
      await client.from('concept_templates').update({'base_price': updatedPrice}).eq('id', template.id);
    }
  }

  ConceptAttributeCatalogItem? _findAttribute(ConceptCatalogSnapshot snapshot, String templateId, String name) {
    for (final item in snapshot.attributes) {
      if (item.templateId == templateId && _normalize(item.name) == _normalize(name)) {
        return item;
      }
    }
    return null;
  }

  AttributeOptionCatalogItem? _findOption(ConceptCatalogSnapshot snapshot, String attributeId, String value) {
    for (final item in snapshot.options) {
      if (item.attributeId == attributeId && _normalize(item.value) == _normalize(value)) {
        return item;
      }
    }
    return null;
  }

  bool _containsUniverse(ConceptCatalogSnapshot snapshot, String name) {
    return _findUniverse(snapshot, name) != null;
  }

  Future<String> _ensureDefaultClosure() async {
    const defaultText =
        'INCLUYE MATERIAL DE PRIMERA CALIDAD, CORTES, DESPERDICIOS, ACARREOS, MANIOBRAS, MANO DE OBRA ESPECIALIZADA Y TODO LO NECESARIO PARA SU CORRECTA EJECUCION.';

    final snapshot = await fetchCatalog();
    for (final closure in snapshot.closures) {
      if (_normalize(closure.text) == _normalize(defaultText)) {
        return closure.id;
      }
    }

    final client = SupabaseBootstrap.client;
    if (client == null) {
      final closure = ConceptClosureCatalogItem(id: _localId('closure'), text: defaultText);
      _localSnapshot = ConceptCatalogSnapshot(
        universes: [...snapshot.universes],
        projectTypes: [...snapshot.projectTypes],
        closures: [...snapshot.closures, closure],
        templates: [...snapshot.templates],
        attributes: [...snapshot.attributes],
        options: [...snapshot.options],
      );
      return closure.id;
    }

    final inserted = await client.from('concept_closures').insert({'text': defaultText}).select('id').single();
    return inserted['id'] as String;
  }
  ConceptCatalogSnapshot _cloneSnapshot(ConceptCatalogSnapshot snapshot) {
    return ConceptCatalogSnapshot(
      universes: [...snapshot.universes],
      projectTypes: [...snapshot.projectTypes],
      closures: [...snapshot.closures],
      templates: [...snapshot.templates],
      attributes: [...snapshot.attributes],
      options: [...snapshot.options],
    );
  }

  String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _localId(String prefix) => '$prefix-${DateTime.now().microsecondsSinceEpoch}';
}