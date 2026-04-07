import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'surveys_staff_repository.dart';

final surveysStaffRepositoryProvider = Provider<SurveysStaffRepository>((ref) {
  return SurveysStaffRepository();
});

/// Provider to fetch all surveys for the current authenticated staff user
final surveysByStaffProvider = FutureProvider<List<SurveyWithQuoteContext>>((ref) async {
  final repository = ref.watch(surveysStaffRepositoryProvider);
  return repository.fetchSurveysForCurrentUser();
});

/// Provider to refetch surveys (used by refresh actions)
final surveysByStaffRefreshProvider = FutureProvider<void>((ref) async {
  ref.invalidate(surveysByStaffProvider);
});
