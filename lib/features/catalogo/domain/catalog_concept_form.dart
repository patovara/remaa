import '../../cotizaciones/domain/concept_generation.dart';

class CatalogAttributeLibrary {
  const CatalogAttributeLibrary({
    required this.attributeNames,
    required this.optionsByAttribute,
  });

  final List<String> attributeNames;
  final Map<String, List<String>> optionsByAttribute;

  static CatalogAttributeLibrary fromSnapshot(ConceptCatalogSnapshot snapshot) {
    final optionsByAttribute = <String, Set<String>>{};

    for (final attribute in snapshot.attributes) {
      final key = _normalize(attribute.name);
      if (key.isEmpty) {
        continue;
      }
      optionsByAttribute.putIfAbsent(key, () => <String>{});

      final options = snapshot.optionsForAttribute(attribute.id);
      for (final option in options) {
        final cleanOption = option.value.trim();
        if (cleanOption.isEmpty) {
          continue;
        }
        optionsByAttribute[key]!.add(cleanOption);
      }
    }

    final attributeNames = [for (final key in optionsByAttribute.keys) key]
      ..sort((a, b) => a.compareTo(b));

    return CatalogAttributeLibrary(
      attributeNames: attributeNames,
      optionsByAttribute: {
        for (final entry in optionsByAttribute.entries)
          entry.key: (entry.value.toList()..sort((a, b) => a.compareTo(b))),
      },
    );
  }
}

class CatalogConceptAttributeSelection {
  const CatalogConceptAttributeSelection({
    required this.attributeName,
    required this.optionValue,
  });

  final String attributeName;
  final String optionValue;
}

class CatalogConceptDraft {
  const CatalogConceptDraft({
    required this.universeId,
    required this.projectTypeId,
    required this.name,
    required this.baseDescription,
    required this.defaultUnit,
    required this.basePrice,
    required this.attributes,
  });

  final String universeId;
  final String projectTypeId;
  final String name;
  final String baseDescription;
  final String defaultUnit;
  final double basePrice;
  final List<CatalogConceptAttributeSelection> attributes;

  static CatalogConceptDraft fromRaw({
    required String? universeId,
    required String? projectTypeId,
    required String name,
    required String baseDescription,
    required String defaultUnit,
    required String basePrice,
    required List<CatalogConceptAttributeSelection> attributes,
  }) {
    final cleanUniverseId = (universeId ?? '').trim();
    final cleanProjectTypeId = (projectTypeId ?? '').trim();
    final cleanName = name.trim();
    final cleanDescription = baseDescription.trim();
    final cleanUnit = defaultUnit.trim();
    final cleanPriceText = basePrice.trim().replaceAll(',', '.');
    final parsedPrice = double.tryParse(cleanPriceText);

    if (cleanUniverseId.isEmpty || cleanProjectTypeId.isEmpty) {
      throw StateError('Selecciona universo y tipo de proyecto.');
    }
    if (cleanName.isEmpty) {
      throw StateError('El nombre del concepto es obligatorio.');
    }
    if (cleanUnit.isEmpty) {
      throw StateError('La unidad es obligatoria.');
    }
    if (parsedPrice == null || parsedPrice < 0) {
      throw StateError(
        'El precio base debe ser un número válido mayor o igual a 0.',
      );
    }

    final dedup = <String, CatalogConceptAttributeSelection>{};
    for (final item in attributes) {
      final cleanAttribute = item.attributeName.trim();
      if (cleanAttribute.isEmpty) {
        continue;
      }
      final key = _normalize(cleanAttribute);
      dedup[key] = CatalogConceptAttributeSelection(
        attributeName: cleanAttribute,
        optionValue: item.optionValue.trim(),
      );
    }

    return CatalogConceptDraft(
      universeId: cleanUniverseId,
      projectTypeId: cleanProjectTypeId,
      name: cleanName,
      baseDescription: cleanDescription,
      defaultUnit: cleanUnit,
      basePrice: parsedPrice,
      attributes: dedup.values.toList(),
    );
  }
}

String _normalize(String value) => value.trim().toLowerCase();
