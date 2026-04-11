import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_bootstrap.dart';

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
}
