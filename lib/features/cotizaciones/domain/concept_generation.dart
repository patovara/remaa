class UniverseCatalogItem {
  const UniverseCatalogItem({required this.id, required this.name});

  final String id;
  final String name;
}

class ProjectTypeCatalogItem {
  const ProjectTypeCatalogItem({
    required this.id,
    required this.name,
    required this.actionBase,
  });

  final String id;
  final String name;
  final String actionBase;

  String get shortCode {
    final value = name.toLowerCase().trim();
    if (value.contains('mantenimiento')) {
      return 'MNTO';
    }
    if (value.contains('remodel')) {
      return 'RMD';
    }
    if (value.contains('constru')) {
      return 'CNST';
    }
    return 'GEN';
  }
}

class ConceptClosureCatalogItem {
  const ConceptClosureCatalogItem({required this.id, required this.text});

  final String id;
  final String text;
}

class ConceptTemplateCatalogItem {
  const ConceptTemplateCatalogItem({
    required this.id,
    required this.universeId,
    required this.projectTypeId,
    required this.closureId,
    required this.name,
    required this.baseDescription,
    required this.defaultUnit,
    required this.basePrice,
  });

  final String id;
  final String universeId;
  final String projectTypeId;
  final String closureId;
  final String name;
  final String baseDescription;
  final String defaultUnit;
  final double basePrice;
}

class ConceptAttributeCatalogItem {
  const ConceptAttributeCatalogItem({
    required this.id,
    required this.templateId,
    required this.name,
  });

  final String id;
  final String templateId;
  final String name;
}

class AttributeOptionCatalogItem {
  const AttributeOptionCatalogItem({
    required this.id,
    required this.attributeId,
    required this.value,
  });

  final String id;
  final String attributeId;
  final String value;
}

class ConceptCatalogSnapshot {
  const ConceptCatalogSnapshot({
    required this.universes,
    required this.projectTypes,
    required this.closures,
    required this.templates,
    required this.attributes,
    required this.options,
  });

  final List<UniverseCatalogItem> universes;
  final List<ProjectTypeCatalogItem> projectTypes;
  final List<ConceptClosureCatalogItem> closures;
  final List<ConceptTemplateCatalogItem> templates;
  final List<ConceptAttributeCatalogItem> attributes;
  final List<AttributeOptionCatalogItem> options;

  List<ConceptTemplateCatalogItem> templatesForUniverse(String universeId) {
    return templates.where((item) => item.universeId == universeId).toList();
  }

  List<ConceptTemplateCatalogItem> templatesForUniverseAndProjectType(
    String universeId,
    String projectTypeId,
  ) {
    return templates
        .where(
          (item) =>
              item.universeId == universeId && item.projectTypeId == projectTypeId,
        )
        .toList();
  }

  bool hasTemplatesForUniverseAndProjectType(String universeId, String projectTypeId) {
    for (final item in templates) {
      if (item.universeId == universeId && item.projectTypeId == projectTypeId) {
        return true;
      }
    }
    return false;
  }

  List<ProjectTypeCatalogItem> projectTypesForUniverse(String universeId) {
    final ids = <String>{
      for (final item in templates)
        if (item.universeId == universeId) item.projectTypeId,
    };
    final result = [
      for (final projectType in projectTypes)
        if (ids.contains(projectType.id)) projectType,
    ];
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  List<ConceptAttributeCatalogItem> attributesForTemplate(String templateId) {
    return attributes.where((item) => item.templateId == templateId).toList();
  }

  List<AttributeOptionCatalogItem> optionsForAttribute(String attributeId) {
    return options.where((item) => item.attributeId == attributeId).toList();
  }

  ConceptClosureCatalogItem? closureById(String closureId) {
    for (final closure in closures) {
      if (closure.id == closureId) {
        return closure;
      }
    }
    return null;
  }

  ProjectTypeCatalogItem? projectTypeById(String projectTypeId) {
    for (final projectType in projectTypes) {
      if (projectType.id == projectTypeId) {
        return projectType;
      }
    }
    return null;
  }

  UniverseCatalogItem? universeById(String universeId) {
    for (final universe in universes) {
      if (universe.id == universeId) {
        return universe;
      }
    }
    return null;
  }
}

class GeneratedConceptResult {
  const GeneratedConceptResult({
    required this.description,
    required this.generatedData,
  });

  final String description;
  final Map<String, Object?> generatedData;
}

class ConceptGenerator {
  const ConceptGenerator();

  GeneratedConceptResult build({
    required String projectType,
    required String action,
    required String universe,
    required String concept,
    required String baseDescription,
    required Map<String, String> attributes,
    required String unit,
    required double basePrice,
    required String closure,
  }) {
    final resolvedBaseDescription = _replacePlaceholders(
      source: baseDescription,
      attributes: attributes,
    );

    final attributeText = _attributesText(attributes);
    final body = [
      action.trim(),
      resolvedBaseDescription.trim(),
      if (attributeText.isNotEmpty) attributeText,
    ].where((part) => part.isNotEmpty).join(' ');

    final normalizedBody = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    final description =
        '$normalizedBody. Unidad: ${unit.trim()}.\n\n${closure.trim()}';

    return GeneratedConceptResult(
      description: description,
      generatedData: {
        'project_type': projectType,
        'action': action,
        'universe': universe,
        'concept': concept,
        'attributes': attributes,
        'unit': unit,
        'base_price': basePrice,
      },
    );
  }

  String _replacePlaceholders({
    required String source,
    required Map<String, String> attributes,
  }) {
    var result = source;
    attributes.forEach((key, value) {
      result = result.replaceAll('{${key.trim()}}', value.trim());
    });
    return result;
  }

  String _attributesText(Map<String, String> attributes) {
    final parts = <String>[];
    attributes.forEach((key, value) {
      final cleanKey = key.trim();
      final cleanValue = value.trim();
      if (cleanKey.isNotEmpty && cleanValue.isNotEmpty) {
        parts.add('$cleanKey: $cleanValue');
      }
    });
    if (parts.isEmpty) {
      return '';
    }
    return '(${parts.join(', ')})';
  }
}
