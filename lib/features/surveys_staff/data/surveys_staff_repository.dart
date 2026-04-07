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
      // Query project_survey_entries with joins to get quote and project context
      // RLS policies will automatically filter to current user's surveys
      final response = await _client
          .from('project_survey_entries')
          .select('''
            id,
            project_id,
            quote_id,
            description,
            evidence_paths,
            evidence_meta,
            created_at,
            quotes(
              quote_number,
              status,
              total,
              created_at,
              projects(
                id,
                code,
                name,
                description,
                site_address,
                client_id,
                clients(business_name)
              )
            )
          ''')
          .eq('captured_by_user_id', userId)
          .order('created_at', ascending: false);

      return (response as List<dynamic>)
          .map((row) {
            final quoteData = row['quotes'] as Map<String, dynamic>?;
            final projectData = quoteData?['projects'] as Map<String, dynamic>?;
            final clientData = projectData?['clients'] as Map<String, dynamic>?;

            return SurveyWithQuoteContext(
              surveyId: row['id'] as String,
              projectId: row['project_id'] as String,
              quoteId: row['quote_id'] as String? ?? '',
              description: row['description'] as String? ?? '',
              evidencePaths: List<String>.from(row['evidence_paths'] as List<dynamic>? ?? []),
              evidenceMetadata: List<Map<String, dynamic>>.from(
                (row['evidence_meta'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
              ),
              createdAt: DateTime.parse(row['created_at'] as String),
              quoteNumber: quoteData?['quote_number'] as String? ?? 'N/A',
              quoteStatus: quoteData?['status'] as String? ?? 'unknown',
              quoteTotal: (quoteData?['total'] as num?)?.toDouble() ?? 0.0,
              quoteCreatedAt: quoteData != null
                  ? DateTime.parse(quoteData['created_at'] as String)
                  : DateTime.now(),
              projectName: projectData?['name'] as String? ?? 'Unknown Project',
              projectCode: projectData?['code'] as String? ?? '',
              projectDescription: projectData?['description'] as String?,
              projectSiteAddress: projectData?['site_address'] as String?,
              clientName: clientData?['business_name'] as String? ?? 'Unknown Client',
            );
          })
          .toList();
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
