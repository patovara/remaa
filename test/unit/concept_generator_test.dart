import 'package:flutter_test/flutter_test.dart';

import 'package:rema_app/features/cotizaciones/domain/concept_generation.dart';

void main() {
  group('ConceptGenerator', () {
    test('build crea texto estandar y generated_data esperado', () {
      const generator = ConceptGenerator();

      final result = generator.build(
        projectType: 'Mantenimiento',
        action: 'SUMINISTRAR Y APLICAR',
        universe: 'Recubrimientos',
        concept: 'pintura vinilica',
        baseDescription:
            'pintura vinilica marca {marca}, acabado {acabado}, a {manos} manos sobre superficie preparada',
        attributes: const {
          'marca': 'Comex',
          'acabado': 'Mate',
          'manos': '2',
        },
        unit: 'm2',
        basePrice: 120,
        closure:
            'INCLUYE MATERIAL DE PRIMERA CALIDAD, CORTES, DESPERDICIOS, ACARREOS, MANIOBRAS, MANO DE OBRA ESPECIALIZADA.',
      );

      expect(result.description, contains('SUMINISTRAR Y APLICAR'));
      expect(result.description, contains('pintura vinilica marca Comex'));
      expect(result.description, contains('Unidad: m2.'));
      expect(result.description, contains('INCLUYE MATERIAL DE PRIMERA CALIDAD'));

      expect(result.generatedData['project_type'], equals('Mantenimiento'));
      expect(result.generatedData['action'], equals('SUMINISTRAR Y APLICAR'));
      expect(result.generatedData['universe'], equals('Recubrimientos'));
      expect(result.generatedData['concept'], equals('pintura vinilica'));
      expect(result.generatedData['unit'], equals('m2'));
      expect(result.generatedData['base_price'], equals(120));

      final attributes = result.generatedData['attributes'] as Map<String, String>;
      expect(attributes['marca'], equals('Comex'));
      expect(attributes['acabado'], equals('Mate'));
      expect(attributes['manos'], equals('2'));
    });
  });
}
