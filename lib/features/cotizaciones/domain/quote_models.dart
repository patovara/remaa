class QuoteRecord {
  const QuoteRecord({
    required this.id,
    required this.projectId,
    required this.quoteNumber,
    required this.status,
    required this.universeId,
    required this.projectTypeId,
    required this.subtotal,
    required this.tax,
    required this.total,
    this.validUntil,
  });

  final String id;
  final String projectId;
  final String quoteNumber;
  final String status;
  final String universeId;
  final String projectTypeId;
  final double subtotal;
  final double tax;
  final double total;
  final DateTime? validUntil;

  QuoteRecord copyWith({
    String? id,
    String? projectId,
    String? quoteNumber,
    String? status,
    String? universeId,
    String? projectTypeId,
    double? subtotal,
    double? tax,
    double? total,
    DateTime? validUntil,
  }) {
    return QuoteRecord(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      quoteNumber: quoteNumber ?? this.quoteNumber,
      status: status ?? this.status,
      universeId: universeId ?? this.universeId,
      projectTypeId: projectTypeId ?? this.projectTypeId,
      subtotal: subtotal ?? this.subtotal,
      tax: tax ?? this.tax,
      total: total ?? this.total,
      validUntil: validUntil ?? this.validUntil,
    );
  }
}

class ProjectLookup {
  const ProjectLookup({
    required this.id,
    required this.code,
    required this.name,
    this.clientId,
  });

  final String id;
  final String code;
  final String name;
  final String? clientId;

  String get label => '$code - $name';
}

class QuoteItemRecord {
  const QuoteItemRecord({
    required this.id,
    required this.quoteId,
    required this.concept,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.templateId,
    this.generatedData,
  });

  final String id;
  final String quoteId;
  final String? templateId;
  final String concept;
  final Map<String, Object?>? generatedData;
  final String unit;
  final double quantity;
  final double unitPrice;
  final double lineTotal;

  QuoteItemRecord copyWith({
    String? id,
    String? quoteId,
    String? templateId,
    String? concept,
    Map<String, Object?>? generatedData,
    String? unit,
    double? quantity,
    double? unitPrice,
    double? lineTotal,
  }) {
    return QuoteItemRecord(
      id: id ?? this.id,
      quoteId: quoteId ?? this.quoteId,
      templateId: templateId ?? this.templateId,
      concept: concept ?? this.concept,
      generatedData: generatedData ?? this.generatedData,
      unit: unit ?? this.unit,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      lineTotal: lineTotal ?? this.lineTotal,
    );
  }
}
