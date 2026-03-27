import '../../../core/config/supabase_bootstrap.dart';
import '../../../core/logging/app_logger.dart';
import '../domain/concept_generation.dart';

class ConceptsCatalogRepository {
  Future<ConceptCatalogSnapshot> fetchCatalog() async {
    final client = SupabaseBootstrap.client;
    if (client == null) {
      return _seedCatalog;
    }

    try {
      final universesRows = await client
          .from('universes')
          .select('id, name')
          .order('name');
      final projectTypesRows = await client
          .from('project_types')
          .select('id, name, action_base')
          .order('name');
      final closuresRows = await client
          .from('concept_closures')
          .select('id, text')
          .order('text');
      final templatesRows = await client
          .from('concept_templates')
          .select(
            'id, universe_id, project_type_id, closure_id, name, base_description, default_unit, base_price',
          )
          .order('name');
      final attributesRows = await client
          .from('concept_attributes')
          .select('id, concept_template_id, name')
          .order('name');
      final optionsRows = await client
          .from('attribute_options')
          .select('id, attribute_id, value')
          .order('value');

      return ConceptCatalogSnapshot(
        universes: [
          for (final row in universesRows)
            UniverseCatalogItem(
              id: row['id'] as String,
              name: row['name'] as String? ?? '',
            ),
        ],
        projectTypes: [
          for (final row in projectTypesRows)
            ProjectTypeCatalogItem(
              id: row['id'] as String,
              name: row['name'] as String? ?? '',
              actionBase: row['action_base'] as String? ?? '',
            ),
        ],
        closures: [
          for (final row in closuresRows)
            ConceptClosureCatalogItem(
              id: row['id'] as String,
              text: row['text'] as String? ?? '',
            ),
        ],
        templates: [
          for (final row in templatesRows)
            ConceptTemplateCatalogItem(
              id: row['id'] as String,
              universeId: row['universe_id'] as String,
              projectTypeId: row['project_type_id'] as String,
              closureId: row['closure_id'] as String,
              name: row['name'] as String? ?? '',
              baseDescription: row['base_description'] as String? ?? '',
              defaultUnit: row['default_unit'] as String? ?? '',
              basePrice: _toDouble(row['base_price']),
            ),
        ],
        attributes: [
          for (final row in attributesRows)
            ConceptAttributeCatalogItem(
              id: row['id'] as String,
              templateId: row['concept_template_id'] as String,
              name: row['name'] as String? ?? '',
            ),
        ],
        options: [
          for (final row in optionsRows)
            AttributeOptionCatalogItem(
              id: row['id'] as String,
              attributeId: row['attribute_id'] as String,
              value: row['value'] as String? ?? '',
            ),
        ],
      );
    } catch (error) {
      AppLogger.error('concept_catalog_fetch_failed', data: {'error': error.toString()});
      return _seedCatalog;
    }
  }

  double _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse('$value') ?? 0;
  }
}

const _seedCatalog = ConceptCatalogSnapshot(
  universes: [
    UniverseCatalogItem(id: 'seed-u-vidrio-aluminio', name: 'Vidrio/Aluminio'),
    UniverseCatalogItem(id: 'seed-u-recubrimientos', name: 'Recubrimientos'),
    UniverseCatalogItem(id: 'seed-u-acero', name: 'Acero'),
    UniverseCatalogItem(id: 'seed-u-paneles', name: 'Paneles'),
  ],
  projectTypes: [
    ProjectTypeCatalogItem(
      id: 'seed-pt-mantenimiento',
      name: 'Mantenimiento',
      actionBase: 'SUMINISTRAR Y APLICAR',
    ),
    ProjectTypeCatalogItem(
      id: 'seed-pt-remodelacion',
      name: 'Remodelacion',
      actionBase: 'SUMINISTRAR E INSTALAR',
    ),
    ProjectTypeCatalogItem(
      id: 'seed-pt-construccion',
      name: 'Construccion',
      actionBase: 'DEMOLER Y RETIRAR',
    ),
  ],
  closures: [
    ConceptClosureCatalogItem(
      id: 'seed-cierre-1',
      text:
          'INCLUYE MATERIAL DE PRIMERA CALIDAD, CORTES, DESPERDICIOS, ACARREOS, MANIOBRAS, MANO DE OBRA ESPECIALIZADA Y TODO LO NECESARIO PARA SU CORRECTA EJECUCION.',
    ),
  ],
  templates: [
    ConceptTemplateCatalogItem(
      id: 'seed-t-pintura',
      universeId: 'seed-u-recubrimientos',
      projectTypeId: 'seed-pt-mantenimiento',
      closureId: 'seed-cierre-1',
      name: 'Pintura vinilica',
      baseDescription:
          'pintura vinilica marca {marca}, acabado {acabado}, a {manos} manos sobre superficie preparada',
      defaultUnit: 'm2',
      basePrice: 120,
    ),
    ConceptTemplateCatalogItem(
      id: 'seed-t-canceleria',
      universeId: 'seed-u-vidrio-aluminio',
      projectTypeId: 'seed-pt-remodelacion',
      closureId: 'seed-cierre-1',
      name: 'Canceleria de aluminio',
      baseDescription:
          'canceleria de aluminio serie {serie}, color {color}, con vidrio {vidrio} y herrajes completos',
      defaultUnit: 'm2',
      basePrice: 1650,
    ),
    ConceptTemplateCatalogItem(
      id: 'seed-t-paneles',
      universeId: 'seed-u-paneles',
      projectTypeId: 'seed-pt-remodelacion',
      closureId: 'seed-cierre-1',
      name: 'Panel de yeso',
      baseDescription:
          'sistema de panel de yeso tipo {tipo_panel}, espesor {espesor}, con estructura {estructura} y acabado {acabado}',
      defaultUnit: 'm2',
      basePrice: 290,
    ),
  ],
  attributes: [
    ConceptAttributeCatalogItem(
      id: 'seed-a-pintura-marca',
      templateId: 'seed-t-pintura',
      name: 'marca',
    ),
    ConceptAttributeCatalogItem(
      id: 'seed-a-pintura-acabado',
      templateId: 'seed-t-pintura',
      name: 'acabado',
    ),
    ConceptAttributeCatalogItem(
      id: 'seed-a-pintura-manos',
      templateId: 'seed-t-pintura',
      name: 'manos',
    ),
    ConceptAttributeCatalogItem(
      id: 'seed-a-canceleria-serie',
      templateId: 'seed-t-canceleria',
      name: 'serie',
    ),
    ConceptAttributeCatalogItem(
      id: 'seed-a-canceleria-color',
      templateId: 'seed-t-canceleria',
      name: 'color',
    ),
    ConceptAttributeCatalogItem(
      id: 'seed-a-canceleria-vidrio',
      templateId: 'seed-t-canceleria',
      name: 'vidrio',
    ),
    ConceptAttributeCatalogItem(
      id: 'seed-a-panel-tipo',
      templateId: 'seed-t-paneles',
      name: 'tipo_panel',
    ),
    ConceptAttributeCatalogItem(
      id: 'seed-a-panel-espesor',
      templateId: 'seed-t-paneles',
      name: 'espesor',
    ),
    ConceptAttributeCatalogItem(
      id: 'seed-a-panel-estructura',
      templateId: 'seed-t-paneles',
      name: 'estructura',
    ),
    ConceptAttributeCatalogItem(
      id: 'seed-a-panel-acabado',
      templateId: 'seed-t-paneles',
      name: 'acabado',
    ),
  ],
  options: [
    AttributeOptionCatalogItem(
      id: 'seed-o-pintura-marca-comex',
      attributeId: 'seed-a-pintura-marca',
      value: 'Comex',
    ),
    AttributeOptionCatalogItem(
      id: 'seed-o-pintura-marca-berel',
      attributeId: 'seed-a-pintura-marca',
      value: 'Berel',
    ),
    AttributeOptionCatalogItem(
      id: 'seed-o-pintura-acabado-mate',
      attributeId: 'seed-a-pintura-acabado',
      value: 'Mate',
    ),
    AttributeOptionCatalogItem(
      id: 'seed-o-pintura-acabado-satinado',
      attributeId: 'seed-a-pintura-acabado',
      value: 'Satinado',
    ),
    AttributeOptionCatalogItem(
      id: 'seed-o-pintura-manos-2',
      attributeId: 'seed-a-pintura-manos',
      value: '2',
    ),
    AttributeOptionCatalogItem(
      id: 'seed-o-canceleria-serie-70',
      attributeId: 'seed-a-canceleria-serie',
      value: '70',
    ),
    AttributeOptionCatalogItem(
      id: 'seed-o-canceleria-color-negro',
      attributeId: 'seed-a-canceleria-color',
      value: 'Negro',
    ),
    AttributeOptionCatalogItem(
      id: 'seed-o-canceleria-vidrio-templado',
      attributeId: 'seed-a-canceleria-vidrio',
      value: 'Templado 9mm',
    ),
    AttributeOptionCatalogItem(
      id: 'seed-o-panel-tipo-std',
      attributeId: 'seed-a-panel-tipo',
      value: 'STD',
    ),
    AttributeOptionCatalogItem(
      id: 'seed-o-panel-tipo-rh',
      attributeId: 'seed-a-panel-tipo',
      value: 'RH',
    ),
    AttributeOptionCatalogItem(
      id: 'seed-o-panel-tipo-rf',
      attributeId: 'seed-a-panel-tipo',
      value: 'RF',
    ),
    AttributeOptionCatalogItem(
      id: 'seed-o-panel-espesor-12',
      attributeId: 'seed-a-panel-espesor',
      value: '1/2"',
    ),
    AttributeOptionCatalogItem(
      id: 'seed-o-panel-espesor-58',
      attributeId: 'seed-a-panel-espesor',
      value: '5/8"',
    ),
    AttributeOptionCatalogItem(
      id: 'seed-o-panel-estructura-362',
      attributeId: 'seed-a-panel-estructura',
      value: 'Canal y poste 3 5/8"',
    ),
    AttributeOptionCatalogItem(
      id: 'seed-o-panel-estructura-6',
      attributeId: 'seed-a-panel-estructura',
      value: 'Canal y poste 6"',
    ),
    AttributeOptionCatalogItem(
      id: 'seed-o-panel-acabado-cinta',
      attributeId: 'seed-a-panel-acabado',
      value: 'Juntas con cinta y compuesto',
    ),
    AttributeOptionCatalogItem(
      id: 'seed-o-panel-acabado-pintura',
      attributeId: 'seed-a-panel-acabado',
      value: 'Listo para pintura',
    ),
  ],
);
