import 'dart:typed_data';

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
    this.approvalPdfPath,
    this.approvalPdfUploadedAt,
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
  final String? approvalPdfPath;
  final DateTime? approvalPdfUploadedAt;

  bool get hasApprovalPdf => approvalPdfPath != null && approvalPdfPath!.trim().isNotEmpty;

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
    String? approvalPdfPath,
    DateTime? approvalPdfUploadedAt,
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
      approvalPdfPath: approvalPdfPath ?? this.approvalPdfPath,
      approvalPdfUploadedAt: approvalPdfUploadedAt ?? this.approvalPdfUploadedAt,
    );
  }
}

class ProjectLookup {
  const ProjectLookup({
    required this.id,
    required this.code,
    required this.name,
    this.clientId,
    this.siteAddress,
    this.description,
    this.managerName,
  });

  final String id;
  final String code;
  final String name;
  final String? clientId;
  final String? siteAddress;
  final String? description;
  final String? managerName;

  String get label => '$code - $name';
}

class NewProjectInput {
  const NewProjectInput({
    required this.code,
    required this.name,
    this.clientId,
    this.siteAddress,
    this.description,
    this.managerName,
  });

  final String code;
  final String name;
  final String? clientId;
  final String? siteAddress;
  final String? description;
  final String? managerName;
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

class QuoteContextInfo {
  const QuoteContextInfo({
    required this.projectName,
    required this.clientName,
    required this.address,
    required this.location,
    required this.description,
  });

  final String projectName;
  final String clientName;
  final String address;
  final String location;
  final String description;

  bool get isEmpty =>
      projectName.trim().isEmpty &&
      clientName.trim().isEmpty &&
      address.trim().isEmpty &&
      location.trim().isEmpty &&
      description.trim().isEmpty;
}

class SurveyEntryRecord {
  const SurveyEntryRecord({
    this.id,
    required this.description,
    this.evidencePreviewList = const <Uint8List>[],
    this.evidenceMetadata = const <SurveyEvidenceMeta>[],
    this.createdAt,
  });

  final String? id;
  final String description;
  final List<Uint8List> evidencePreviewList;
  final List<SurveyEvidenceMeta> evidenceMetadata;
  final DateTime? createdAt;
}

class SurveyEvidenceInput {
  const SurveyEvidenceInput({
    required this.bytes,
    required this.originalName,
    required this.fileSizeBytes,
    this.mimeType,
  });

  final Uint8List bytes;
  final String originalName;
  final int fileSizeBytes;
  final String? mimeType;
}

class SurveyEvidenceMeta {
  const SurveyEvidenceMeta({
    required this.objectPath,
    required this.originalName,
    required this.fileSizeBytes,
    required this.sortOrder,
    this.mimeType,
    this.widthPx,
    this.heightPx,
    this.takenAt,
  });

  final String objectPath;
  final String originalName;
  final int fileSizeBytes;
  final int sortOrder;
  final String? mimeType;
  final int? widthPx;
  final int? heightPx;
  final DateTime? takenAt;
}
