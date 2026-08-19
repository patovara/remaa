import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/image_optimizer.dart';
import '../../../core/config/supabase_bootstrap.dart';
import '../../cotizaciones/domain/quote_models.dart';

/// Data transfer object for survey with quote context
class SurveyWithQuoteContext {
  const SurveyWithQuoteContext({
    required this.surveyId,
    required this.projectId,
    required this.quoteId,
    required this.description,
    required this.evidencePaths,
    required this.evidenceMetadata,
    required this.createdAt,
    required this.quoteNumber,
    required this.quoteStatus,
    required this.quoteTotal,
    required this.quoteCreatedAt,
    required this.projectName,
    required this.projectCode,
    required this.projectDescription,
    required this.projectSiteAddress,
    required this.clientName,
  });

  final String surveyId;
  final String projectId;
  final String quoteId;
  final String description;
  final List<String> evidencePaths;
  final List<Map<String, dynamic>> evidenceMetadata;
  final DateTime createdAt;
  final String quoteNumber;
  final String quoteStatus;
  final double quoteTotal;
  final DateTime quoteCreatedAt;
  final String projectName;
  final String projectCode;
  final String? projectDescription;
  final String? projectSiteAddress;
  final String clientName;
}

class SurveysStaffRepository {
  final SupabaseClient _client = SupabaseBootstrap.client!;

  /// Fetch all surveys captured by the current authenticated user, grouped by quote
  Future<List<SurveyWithQuoteContext>> fetchSurveysForCurrentUser() async {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) {
      throw Exception('User not authenticated');
    }

    final userId = currentUser.id;

    try {
      final response = await _client
          .from('project_survey_entries')
          .select('id, project_id, quote_id, description, evidence_paths, evidence_meta, created_at')
          .eq('captured_by_user_id', userId)
          .order('created_at', ascending: false);

      final rows = (response as List<dynamic>).cast<Map<String, dynamic>>();
      if (rows.isEmpty) {
        return const <SurveyWithQuoteContext>[];
      }

      final projectIds = <String>{
        for (final row in rows)
          if ((row['project_id'] as String? ?? '').trim().isNotEmpty)
            (row['project_id'] as String).trim(),
      };

      final projectRows = projectIds.isEmpty
          ? const <dynamic>[]
          : await _client
              .from('projects')
              .select('id, client_id, code, name, description, site_address')
              .inFilter('id', projectIds.toList());
      final projectsById = <String, Map<String, dynamic>>{
        for (final item in projectRows.cast<Map<String, dynamic>>())
          (item['id'] as String? ?? '').trim(): item,
      };

      final quoteRows = projectIds.isEmpty
          ? const <dynamic>[]
          : await _client
              .from('quotes')
              .select('id, project_id, quote_number, status, total, created_at')
              .inFilter('project_id', projectIds.toList())
              .order('created_at', ascending: true);
      final quotesById = <String, Map<String, dynamic>>{};
      final quotesByProject = <String, List<Map<String, dynamic>>>{};
      for (final item in quoteRows.cast<Map<String, dynamic>>()) {
        final quoteId = (item['id'] as String? ?? '').trim();
        final projectId = (item['project_id'] as String? ?? '').trim();
        if (quoteId.isEmpty || projectId.isEmpty) {
          continue;
        }
        quotesById[quoteId] = item;
        quotesByProject.putIfAbsent(projectId, () => <Map<String, dynamic>>[]).add(item);
      }

      final clientIds = <String>{
        for (final item in projectsById.values)
          if ((item['client_id'] as String? ?? '').trim().isNotEmpty)
            (item['client_id'] as String).trim(),
      };
      final clientRows = clientIds.isEmpty
          ? const <dynamic>[]
          : await _client
              .from('clients')
              .select('id, business_name')
              .inFilter('id', clientIds.toList());
      final clientsById = <String, Map<String, dynamic>>{
        for (final item in clientRows.cast<Map<String, dynamic>>())
          (item['id'] as String? ?? '').trim(): item,
      };

      Map<String, dynamic>? resolveQuoteForSurvey(Map<String, dynamic> row) {
        final explicitQuoteId = (row['quote_id'] as String? ?? '').trim();
        if (explicitQuoteId.isNotEmpty) {
          return quotesById[explicitQuoteId];
        }

        final projectId = (row['project_id'] as String? ?? '').trim();
        final createdAt = DateTime.tryParse(row['created_at'] as String? ?? '');
        final projectQuotes = quotesByProject[projectId] ?? const <Map<String, dynamic>>[];
        if (projectQuotes.isEmpty) {
          return null;
        }
        if (createdAt == null) {
          return projectQuotes.last;
        }

        for (final quote in projectQuotes) {
          final quoteCreatedAt = DateTime.tryParse(quote['created_at'] as String? ?? '');
          if (quoteCreatedAt != null && !quoteCreatedAt.isBefore(createdAt)) {
            return quote;
          }
        }
        return projectQuotes.last;
      }

      return rows.map((row) {
        final projectId = (row['project_id'] as String? ?? '').trim();
        final projectData = projectsById[projectId];
        final quoteData = resolveQuoteForSurvey(row);
        final resolvedQuoteId = (quoteData?['id'] as String? ?? '').trim();
        final clientId = (projectData?['client_id'] as String? ?? '').trim();
        final clientData = clientsById[clientId];

        return SurveyWithQuoteContext(
          surveyId: row['id'] as String,
          projectId: projectId,
          quoteId: resolvedQuoteId.isNotEmpty ? resolvedQuoteId : 'project:$projectId',
          description: row['description'] as String? ?? '',
          evidencePaths: List<String>.from(row['evidence_paths'] as List<dynamic>? ?? const []),
          evidenceMetadata: [
            for (final item in (row['evidence_meta'] as List<dynamic>? ?? const []))
              if (item is Map<String, dynamic>) item,
          ],
          createdAt: DateTime.parse(row['created_at'] as String),
          quoteNumber: (quoteData?['quote_number'] as String? ?? '').trim().isNotEmpty
              ? (quoteData!['quote_number'] as String).trim()
              : 'N/A',
          quoteStatus: (quoteData?['status'] as String? ?? 'unknown').trim(),
          quoteTotal: (quoteData?['total'] as num?)?.toDouble() ?? 0.0,
          quoteCreatedAt: DateTime.tryParse(quoteData?['created_at'] as String? ?? '') ??
              DateTime.parse(row['created_at'] as String),
          projectName: (projectData?['name'] as String? ?? '').trim().isNotEmpty
              ? (projectData!['name'] as String).trim()
              : 'Unknown Project',
          projectCode: (projectData?['code'] as String? ?? '').trim(),
          projectDescription: (projectData?['description'] as String?)?.trim(),
          projectSiteAddress: (projectData?['site_address'] as String?)?.trim(),
          clientName: (clientData?['business_name'] as String? ?? '').trim().isNotEmpty
              ? (clientData!['business_name'] as String).trim()
              : 'Unknown Client',
        );
      }).toList();
    } catch (e) {
      rethrow;
    }
  }

  /// Fetch preview/thumbnail for a survey image from storage
  Future<Uint8List?> fetchSurveyImagePreview(String evidencePath) async {
    try {
      final bytes = await _client.storage.from('survey-photos').download(evidencePath);
      return bytes;
    } catch (e) {
      return null;
    }
  }

  Future<SurveyWithQuoteContext> updateSurveyEntry({
    required SurveyWithQuoteContext survey,
    required String projectName,
    required String description,
    required List<Map<String, dynamic>> retainedEvidenceMetadata,
    required List<String> retainedEvidencePaths,
    required List<SurveyEvidenceInput> newEvidenceInputs,
  }) async {
    final cleanProjectName = projectName.trim();
    final cleanDescription = description.trim();
    if (cleanProjectName.isEmpty) {
      throw StateError('El proyecto debe tener nombre.');
    }

    final currentEvidencePaths = {
      ...survey.evidencePaths.where((path) => path.trim().isNotEmpty).map((path) => path.trim()),
    };
    final nextRetainedPaths = retainedEvidencePaths
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toList();

    final removedPaths = currentEvidencePaths.difference(nextRetainedPaths.toSet()).toList();
    final uploadedPaths = <String>[];
    final uploadedMetadata = <Map<String, dynamic>>[];
    final now = DateTime.now();
    final timestamp = now.millisecondsSinceEpoch;
    final quoteFolder = _sanitizeStorageName(
      survey.quoteId.trim().isNotEmpty ? survey.quoteId.trim() : 'no-quote',
    );

    for (var index = 0; index < newEvidenceInputs.length; index++) {
      final input = newEvidenceInputs[index];
      if (input.bytes.isEmpty) {
        continue;
      }

      final optimized = await optimizeImageForDocument(
        inputBytes: input.bytes,
        fileName: input.originalName,
        profile: ImageOptimizationProfile.gridDocument,
      );
      final ext = _guessImageExtension(optimized.fileName);
      final objectPath = '${survey.projectId}/$quoteFolder/${timestamp}_edit_$index.$ext';
      await _client.storage.from('survey-photos').uploadBinary(
            objectPath,
            optimized.bytes,
            fileOptions: FileOptions(
              contentType: optimized.mimeType,
              upsert: true,
            ),
          );
      uploadedPaths.add(objectPath);
      uploadedMetadata.add({
        'object_path': objectPath,
        'original_name': optimized.fileName,
        'mime_type': optimized.mimeType,
        'file_size_bytes': optimized.bytes.length,
        'sort_order': nextRetainedPaths.length + index,
        'width_px': optimized.widthPx,
        'height_px': optimized.heightPx,
        'taken_at': null,
      });
    }

    final retainedMetadata = [
      for (final meta in retainedEvidenceMetadata)
        if (meta['object_path'] is String && nextRetainedPaths.contains((meta['object_path'] as String).trim()))
          meta,
    ];
    final nextEvidenceMetadata = <Map<String, dynamic>>[
      ...retainedMetadata,
      ...uploadedMetadata,
    ];
    final nextEvidencePaths = <String>[
      ...nextRetainedPaths,
      ...uploadedPaths,
    ];

    try {
      if (removedPaths.isNotEmpty) {
        await _client.storage.from('survey-photos').remove(removedPaths);
      }
    } catch (_) {
      // Best effort cleanup.
    }

    await _client.from('projects').update({
      'name': cleanProjectName,
      'description': cleanDescription,
    }).eq('id', survey.projectId);

    await _client.from('project_survey_entries').update({
      'description': cleanDescription,
      'evidence_paths': nextEvidencePaths,
      'evidence_meta': nextEvidenceMetadata,
    }).eq('id', survey.surveyId);

    return SurveyWithQuoteContext(
      surveyId: survey.surveyId,
      projectId: survey.projectId,
      quoteId: survey.quoteId,
      description: cleanDescription,
      evidencePaths: nextEvidencePaths,
      evidenceMetadata: nextEvidenceMetadata,
      createdAt: survey.createdAt,
      quoteNumber: survey.quoteNumber,
      quoteStatus: survey.quoteStatus,
      quoteTotal: survey.quoteTotal,
      quoteCreatedAt: survey.quoteCreatedAt,
      projectName: cleanProjectName,
      projectCode: survey.projectCode,
      projectDescription: cleanDescription,
      projectSiteAddress: survey.projectSiteAddress,
      clientName: survey.clientName,
    );
  }

  String _guessImageExtension(String originalName) {
    final parts = originalName.toLowerCase().split('.');
    if (parts.length > 1) {
      final ext = parts.last.trim();
      if (ext == 'jpg' || ext == 'jpeg' || ext == 'png' || ext == 'webp') {
        return ext;
      }
    }
    return 'jpg';
  }

  String _sanitizeStorageName(String value) {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), '_');
    return normalized.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '');
  }
}
