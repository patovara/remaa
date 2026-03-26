import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:typed_data';

import '../../cotizaciones/domain/quote_models.dart';

class DraftLevantamientoPhoto {
  const DraftLevantamientoPhoto({
    required this.name,
    required this.size,
    required this.bytes,
  });

  final String name;
  final int size;
  final Uint8List bytes;
}

class DraftLevantamientoSnapshot {
  const DraftLevantamientoSnapshot({
    this.projectKey,
    this.projectName,
    this.clientId,
    this.clientName,
    this.address,
    this.notes,
    this.universeId,
    this.projectTypeId,
    this.photos = const <DraftLevantamientoPhoto>[],
  });

  final String? projectKey;
  final String? projectName;
  final String? clientId;
  final String? clientName;
  final String? address;
  final String? notes;
  final String? universeId;
  final String? projectTypeId;
  final List<DraftLevantamientoPhoto> photos;

  bool get hasContent {
    return [
      projectKey,
      projectName,
      clientId,
      clientName,
      address,
      notes,
      universeId,
      projectTypeId,
      if (photos.isNotEmpty) 'photos',
    ].any((value) => value != null && value.trim().isNotEmpty);
  }

  DraftLevantamientoSnapshot copyWith({
    String? projectKey,
    String? projectName,
    String? clientId,
    String? clientName,
    String? address,
    String? notes,
    String? universeId,
    String? projectTypeId,
    List<DraftLevantamientoPhoto>? photos,
  }) {
    return DraftLevantamientoSnapshot(
      projectKey: projectKey ?? this.projectKey,
      projectName: projectName ?? this.projectName,
      clientId: clientId ?? this.clientId,
      clientName: clientName ?? this.clientName,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      universeId: universeId ?? this.universeId,
      projectTypeId: projectTypeId ?? this.projectTypeId,
      photos: photos ?? this.photos,
    );
  }
}

class ActiveLevantamientoSession {
  const ActiveLevantamientoSession({
    required this.projectId,
    required this.universeId,
    required this.projectTypeId,
    this.quoteId,
    this.projectKey,
    this.projectName,
    this.clientId,
    this.clientName,
    this.address,
    this.evidenceCount = 0,
    this.evidencePreviewList = const <Uint8List>[],
    this.entries = const <SurveyEntryRecord>[],
    this.isCompleted = false,
  });

  final String projectId;
  final String universeId;
  final String projectTypeId;
  final String? quoteId;
  // Snapshot de los campos del formulario para restaurar al volver a la pantalla
  final String? projectKey;
  final String? projectName;
  final String? clientId;
  final String? clientName;
  final String? address;
  final int evidenceCount;
  final List<Uint8List> evidencePreviewList;
  final List<SurveyEntryRecord> entries;
  final bool isCompleted;

  bool get isActive => !isCompleted;

  ActiveLevantamientoSession copyWith({
    String? projectId,
    String? universeId,
    String? projectTypeId,
    String? quoteId,
    String? projectKey,
    String? projectName,
    String? clientId,
    String? clientName,
    String? address,
    int? evidenceCount,
    List<Uint8List>? evidencePreviewList,
    List<SurveyEntryRecord>? entries,
    bool? isCompleted,
  }) {
    return ActiveLevantamientoSession(
      projectId: projectId ?? this.projectId,
      universeId: universeId ?? this.universeId,
      projectTypeId: projectTypeId ?? this.projectTypeId,
      quoteId: quoteId ?? this.quoteId,
      projectKey: projectKey ?? this.projectKey,
      projectName: projectName ?? this.projectName,
      clientId: clientId ?? this.clientId,
      clientName: clientName ?? this.clientName,
      address: address ?? this.address,
      evidenceCount: evidenceCount ?? this.evidenceCount,
      evidencePreviewList: evidencePreviewList ?? this.evidencePreviewList,
      entries: entries ?? this.entries,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}

final activeLevantamientoProvider =
    NotifierProvider<ActiveLevantamientoController, ActiveLevantamientoSession?>(
  ActiveLevantamientoController.new,
);

final levantamientoDraftProvider =
    NotifierProvider<LevantamientoDraftController, DraftLevantamientoSnapshot?>(
  LevantamientoDraftController.new,
);

class ActiveLevantamientoController
    extends Notifier<ActiveLevantamientoSession?> {
  @override
  ActiveLevantamientoSession? build() {
    return null;
  }

  void activate({
    required String projectId,
    required String universeId,
    required String projectTypeId,
    String? quoteId,
    String? projectKey,
    String? projectName,
    String? clientId,
    String? clientName,
    String? address,
    int evidenceCount = 0,
    List<Uint8List> evidencePreviewList = const <Uint8List>[],
    List<SurveyEntryRecord> entries = const <SurveyEntryRecord>[],
  }) {
    state = ActiveLevantamientoSession(
      projectId: projectId,
      universeId: universeId,
      projectTypeId: projectTypeId,
      quoteId: quoteId,
      projectKey: projectKey,
      projectName: projectName,
      clientId: clientId,
      clientName: clientName,
      address: address,
      evidenceCount: evidenceCount,
      evidencePreviewList: evidencePreviewList,
      entries: entries,
      isCompleted: false,
    );
  }

  void addEntry({
    required String description,
    List<Uint8List> evidencePreviewList = const <Uint8List>[],
    List<SurveyEvidenceMeta> evidenceMetadata = const <SurveyEvidenceMeta>[],
  }) {
    final current = state;
    if (current == null) return;

    final trimmed = description.trim();
    final hasText = trimmed.isNotEmpty;
    final hasEvidence = evidencePreviewList.isNotEmpty;
    if (!hasText && !hasEvidence) {
      return;
    }

    final latest = current.entries.isNotEmpty ? current.entries.last : null;
    final isDuplicate = latest != null &&
        latest.description.trim() == trimmed &&
        latest.evidencePreviewList.length == evidencePreviewList.length;
    if (isDuplicate) {
      return;
    }

    final nextEntries = <SurveyEntryRecord>[
      ...current.entries,
      SurveyEntryRecord(
        description: trimmed,
        evidencePreviewList: evidencePreviewList,
        evidenceMetadata: evidenceMetadata,
      ),
    ];

    state = current.copyWith(
      entries: nextEntries,
      evidenceCount: evidencePreviewList.length,
      evidencePreviewList: evidencePreviewList,
    );
  }

  /// Actualiza solo el snapshot de campos del formulario sin cambiar el resto.
  void updateSnapshot({
    String? projectKey,
    String? projectName,
    String? clientId,
    String? clientName,
    String? address,
  }) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(
      projectKey: projectKey ?? current.projectKey,
      projectName: projectName ?? current.projectName,
      clientId: clientId ?? current.clientId,
      clientName: clientName ?? current.clientName,
      address: address ?? current.address,
    );
  }

  void attachQuote(String quoteId) {
    final current = state;
    if (current == null) {
      return;
    }
    state = current.copyWith(quoteId: quoteId, isCompleted: false);
  }

  bool canUseUniverse(String universeId) {
    final current = state;
    if (current == null || current.isCompleted) {
      return true;
    }
    return current.universeId == universeId;
  }

  void finish() {
    final current = state;
    if (current == null) {
      return;
    }
    state = current.copyWith(isCompleted: true);
  }

  void clear() {
    state = null;
  }
}

class LevantamientoDraftController
    extends Notifier<DraftLevantamientoSnapshot?> {
  @override
  DraftLevantamientoSnapshot? build() {
    return null;
  }

  void update({
    String? projectKey,
    String? projectName,
    String? clientId,
    String? clientName,
    String? address,
    String? notes,
    String? universeId,
    String? projectTypeId,
    List<DraftLevantamientoPhoto> photos = const <DraftLevantamientoPhoto>[],
  }) {
    final normalized = DraftLevantamientoSnapshot(
      projectKey: _normalize(projectKey),
      projectName: _normalize(projectName),
      clientId: _normalize(clientId),
      clientName: _normalize(clientName),
      address: _normalize(address),
      notes: _normalize(notes),
      universeId: _normalize(universeId),
      projectTypeId: _normalize(projectTypeId),
      photos: photos,
    );

    state = normalized.hasContent ? normalized : null;
  }

  void clear() {
    state = null;
  }

  String? _normalize(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
