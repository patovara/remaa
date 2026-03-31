import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/concepts_catalog_repository.dart';
import '../domain/concept_generation.dart';

final conceptsCatalogRepositoryProvider = Provider<ConceptsCatalogRepository>(
  (ref) => ConceptsCatalogRepository(),
);

final conceptsCatalogProvider =
    AsyncNotifierProvider<ConceptsCatalogController, ConceptCatalogSnapshot>(
  ConceptsCatalogController.new,
);

final conceptUsageSuggestionsProvider = AsyncNotifierProvider.family<
    ConceptUsageSuggestionsController,
    ConceptUsageResponse,
    String>(ConceptUsageSuggestionsController.new);

class ConceptsCatalogController extends AsyncNotifier<ConceptCatalogSnapshot> {
  late final ConceptsCatalogRepository _repository =
      ref.read(conceptsCatalogRepositoryProvider);

  @override
  FutureOr<ConceptCatalogSnapshot> build() {
    return _repository.fetchCatalog();
  }

  Future<void> reload() async {
    state = await AsyncValue.guard(_repository.fetchCatalog);
  }
}

class ConceptUsageSuggestionsController
    extends FamilyAsyncNotifier<ConceptUsageResponse, String> {
  late final ConceptsCatalogRepository _repository =
      ref.read(conceptsCatalogRepositoryProvider);
  late String _universeId;

  @override
  FutureOr<ConceptUsageResponse> build(String arg) {
    _universeId = arg;
    return _repository.fetchConceptUsageSuggestions(universeId: arg);
  }

  Future<void> reload() async {
    state = await AsyncValue.guard(
      () => _repository.fetchConceptUsageSuggestions(universeId: _universeId),
    );
  }
}
