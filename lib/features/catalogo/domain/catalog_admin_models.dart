class CatalogImportRow {
  const CatalogImportRow({
    required this.lineNumber,
    required this.universe,
    required this.concept,
    required this.unit,
    required this.basePrice,
    required this.attribute,
    required this.option,
    required this.projectType,
    required this.baseDescription,
  });

  final int lineNumber;
  final String universe;
  final String concept;
  final String unit;
  final double basePrice;
  final String attribute;
  final String option;
  final String? projectType;
  final String? baseDescription;
}

class CatalogImportIssue {
  const CatalogImportIssue({required this.lineNumber, required this.message});

  final int lineNumber;
  final String message;
}

class CatalogImportParseResult {
  const CatalogImportParseResult({required this.rows, required this.issues});

  final List<CatalogImportRow> rows;
  final List<CatalogImportIssue> issues;

  bool get hasErrors => issues.isNotEmpty;
}

class CatalogImportSummary {
  const CatalogImportSummary({
    required this.createdUniverses,
    required this.existingUniverses,
    required this.createdTemplates,
    required this.existingTemplates,
    required this.createdAttributes,
    required this.existingAttributes,
    required this.createdOptions,
    required this.existingOptions,
    required this.issues,
  });

  final int createdUniverses;
  final int existingUniverses;
  final int createdTemplates;
  final int existingTemplates;
  final int createdAttributes;
  final int existingAttributes;
  final int createdOptions;
  final int existingOptions;
  final List<CatalogImportIssue> issues;

  bool get hasErrors => issues.isNotEmpty;
}