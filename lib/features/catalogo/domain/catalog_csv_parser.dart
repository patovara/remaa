import 'catalog_admin_models.dart';

const _requiredColumns = <String>[
  'universe',
  'concept',
  'unit',
  'base_price',
  'attribute',
  'option',
];

const _optionalColumns = <String>[
  'project_type',
  'base_description',
];

CatalogImportParseResult parseCatalogCsv(String content) {
  final rows = _parseCsv(content);
  if (rows.isEmpty) {
    return const CatalogImportParseResult(
      rows: [],
      issues: [CatalogImportIssue(lineNumber: 1, message: 'El archivo CSV esta vacio.')],
    );
  }

  final header = rows.first.map((cell) => cell.trim().toLowerCase()).toList();
  final issues = <CatalogImportIssue>[];
  final indexes = <String, int>{};

  for (final column in _requiredColumns) {
    final index = header.indexOf(column);
    if (index < 0) {
      issues.add(
        CatalogImportIssue(
          lineNumber: 1,
          message: 'Falta la columna obligatoria "$column".',
        ),
      );
    } else {
      indexes[column] = index;
    }
  }

  if (issues.isNotEmpty) {
    return CatalogImportParseResult(rows: const [], issues: issues);
  }

  for (final column in _optionalColumns) {
    final index = header.indexOf(column);
    if (index >= 0) {
      indexes[column] = index;
    }
  }

  final parsedRows = <CatalogImportRow>[];
  for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
    final raw = rows[rowIndex];
    if (_isRowEmpty(raw)) {
      continue;
    }

    String cell(String column) {
      final index = indexes[column]!;
      if (index >= raw.length) {
        return '';
      }
      return raw[index].trim();
    }

    final universe = cell('universe');
    final concept = cell('concept');
    final unit = cell('unit');
    final basePriceText = cell('base_price');
    final attribute = cell('attribute');
    final option = cell('option');
    final projectType = indexes.containsKey('project_type') ? cell('project_type') : '';
    final baseDescription = indexes.containsKey('base_description') ? cell('base_description') : '';
    final lineNumber = rowIndex + 1;

    if (universe.isEmpty || concept.isEmpty || unit.isEmpty || basePriceText.isEmpty || attribute.isEmpty || option.isEmpty) {
      issues.add(
        CatalogImportIssue(
          lineNumber: lineNumber,
          message: 'Todos los campos obligatorios deben tener valor.',
        ),
      );
      continue;
    }

    final basePrice = double.tryParse(basePriceText.replaceAll(',', ''));
    if (basePrice == null) {
      issues.add(
        CatalogImportIssue(
          lineNumber: lineNumber,
          message: 'base_price no es numerico: $basePriceText',
        ),
      );
      continue;
    }

    parsedRows.add(
      CatalogImportRow(
        lineNumber: lineNumber,
        universe: universe,
        concept: concept,
        unit: unit,
        basePrice: basePrice,
        attribute: attribute,
        option: option,
        projectType: projectType.isEmpty ? null : projectType,
        baseDescription: baseDescription.isEmpty ? null : baseDescription,
      ),
    );
  }

  return CatalogImportParseResult(rows: parsedRows, issues: issues);
}

bool _isRowEmpty(List<String> row) {
  for (final value in row) {
    if (value.trim().isNotEmpty) {
      return false;
    }
  }
  return true;
}

List<List<String>> _parseCsv(String content) {
  final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final rows = <List<String>>[];
  final currentRow = <String>[];
  final currentCell = StringBuffer();
  var inQuotes = false;

  void commitCell() {
    currentRow.add(currentCell.toString());
    currentCell.clear();
  }

  void commitRow() {
    commitCell();
    rows.add(List<String>.from(currentRow));
    currentRow.clear();
  }

  for (var index = 0; index < normalized.length; index++) {
    final char = normalized[index];
    if (char == '"') {
      final nextIsQuote = index + 1 < normalized.length && normalized[index + 1] == '"';
      if (inQuotes && nextIsQuote) {
        currentCell.write('"');
        index++;
      } else {
        inQuotes = !inQuotes;
      }
      continue;
    }

    if (char == ',' && !inQuotes) {
      commitCell();
      continue;
    }

    if (char == '\n' && !inQuotes) {
      commitRow();
      continue;
    }

    currentCell.write(char);
  }

  if (currentCell.isNotEmpty || currentRow.isNotEmpty) {
    commitRow();
  }

  return rows;
}