import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/supabase_bootstrap.dart';
import '../../levantamiento/presentation/levantamiento_state.dart';
import 'concepts_catalog_controller.dart';
import '../data/quotes_repository.dart';
import '../domain/quote_models.dart';

final quotesRepositoryProvider = Provider<QuotesRepository>(
  (ref) => QuotesRepository(),
);

final quoteProjectsProvider = FutureProvider<List<ProjectLookup>>(
  (ref) => ref.read(quotesRepositoryProvider).fetchProjects(),
);

final quotesProvider = AsyncNotifierProvider<QuotesController, List<QuoteRecord>>(
  QuotesController.new,
);

final quoteItemsProvider = AsyncNotifierProvider.family<
    QuoteItemsController,
    List<QuoteItemRecord>,
    String>(QuoteItemsController.new);

final quoteContextProvider = FutureProvider.family<QuoteContextInfo, String>((ref, projectId) {
  return ref.read(quotesRepositoryProvider).fetchQuoteContext(projectId: projectId);
});

final projectSurveyEntriesProvider = FutureProvider.family<List<SurveyEntryRecord>, String>((ref, projectId) {
  return ref.read(quotesRepositoryProvider).fetchSurveyEntries(projectId: projectId);
});

final recentTemplateItemsProvider = FutureProvider.family<List<QuoteItemRecord>, String>((
  ref,
  templateId,
) {
  return ref.read(quotesRepositoryProvider).fetchRecentItemsByTemplate(
        templateId: templateId,
        limit: 5,
      );
});

class QuotesController extends AsyncNotifier<List<QuoteRecord>> {
  late final QuotesRepository _repository = ref.read(quotesRepositoryProvider);

  @override
  FutureOr<List<QuoteRecord>> build() {
    return _repository.fetchQuotes();
  }

  Future<QuoteRecord> createDraft({
    required String projectId,
    required String universeId,
    required String projectTypeId,
    String? projectKey,
  }) async {
    final quote = await _repository.createDraftQuote(
      projectId: projectId,
      universeId: universeId,
      projectTypeId: projectTypeId,
      projectKey: projectKey,
    );
    final current = state.valueOrNull ?? const <QuoteRecord>[];
    state = AsyncData([quote, ...current]);
    return quote;
  }

  Future<String> reserveProjectKey({
    String? clientId,
    String? projectTypeId,
  }) async {
    return _repository.reserveProjectKey(
      client: SupabaseBootstrap.client,
      clientId: clientId,
      projectTypeId: projectTypeId,
    );
  }

  Future<ProjectLookup> createProject({required NewProjectInput input}) async {
    final project = await _repository.createProject(input: input);
    ref.invalidate(quoteProjectsProvider);
    return project;
  }

  Future<void> updateProjectContext({
    required String projectId,
    required String name,
    required String managerName,
    required String address,
    required String description,
    String? clientId,
  }) async {
    await _repository.updateProjectContext(
      projectId: projectId,
      name: name,
      managerName: managerName,
      address: address,
      description: description,
      clientId: clientId,
    );
    ref.invalidate(quoteProjectsProvider);
  }

  Future<QuoteContextInfo> fetchQuoteContext({required String projectId}) {
    return _repository.fetchQuoteContext(projectId: projectId);
  }

  Future<SurveyEntryRecord?> appendSurveyEntry({
    required String projectId,
    String? quoteId,
    required String description,
    required List<SurveyEvidenceInput> evidenceInputs,
  }) {
    ref.invalidate(projectSurveyEntriesProvider(projectId));
    return _repository.appendSurveyEntry(
      projectId: projectId,
      quoteId: quoteId,
      description: description,
      evidenceInputs: evidenceInputs,
    );
  }

  Future<SurveyEntryRecord?> updateSurveyEntry({
    required String projectId,
    required String entryId,
    String? quoteId,
    required String description,
    List<SurveyEvidenceInput>? replacementEvidenceInputs,
    bool clearEvidence = false,
    List<String> existingEvidencePaths = const <String>[],
  }) {
    ref.invalidate(projectSurveyEntriesProvider(projectId));
    return _repository.updateSurveyEntry(
      projectId: projectId,
      entryId: entryId,
      quoteId: quoteId,
      description: description,
      replacementEvidenceInputs: replacementEvidenceInputs,
      clearEvidence: clearEvidence,
      existingEvidencePaths: existingEvidencePaths,
    );
  }

  Future<void> setTotals({
    required String quoteId,
    required double subtotal,
    required double tax,
    required double total,
  }) async {
    final current = state.valueOrNull ?? const <QuoteRecord>[];
    QuoteRecord? quote;
    for (final item in current) {
      if (item.id == quoteId) {
        quote = item;
        break;
      }
    }
    if (quote == null) {
      return;
    }

    final updated = await _repository.updateTotals(
      quote: quote,
      subtotal: subtotal,
      tax: tax,
      total: total,
    );

    state = AsyncData([
      for (final item in current)
        if (item.id == quoteId) updated else item,
    ]);
  }

  Future<void> reload() async {
    state = await AsyncValue.guard(_repository.fetchQuotes);
  }

  Future<void> updateStatus({required String quoteId, required String status}) async {
    final current = state.valueOrNull ?? const <QuoteRecord>[];
    QuoteRecord? quote;
    for (final item in current) {
      if (item.id == quoteId) {
        quote = item;
        break;
      }
    }
    if (quote == null) return;

    final updated = await _repository.updateStatus(quote: quote, status: status);
    state = AsyncData([
      for (final item in current)
        if (item.id == quoteId) updated else item,
    ]);

    _clearLinkedLevantamientoIfNeeded(quoteId: quoteId, status: status);
  }

  void _clearLinkedLevantamientoIfNeeded({
    required String quoteId,
    required String status,
  }) {
    final shouldClear =
        status == QuoteStatus.concluded || status == QuoteStatus.actaFinalizada;
    if (!shouldClear) {
      return;
    }

    final active = ref.read(activeLevantamientoProvider);
    if (active == null || active.quoteId != quoteId) {
      return;
    }

    ref.read(activeLevantamientoProvider.notifier).clear();
    ref.read(levantamientoDraftProvider.notifier).clear();
  }

  Future<void> attachApprovalPdf({
    required String quoteId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final current = state.valueOrNull ?? const <QuoteRecord>[];
    QuoteRecord? quote;
    for (final item in current) {
      if (item.id == quoteId) {
        quote = item;
        break;
      }
    }
    if (quote == null) {
      throw StateError('No se encontro la cotizacion para adjuntar el PDF.');
    }

    final updated = await _repository.attachApprovalPdf(
      quote: quote,
      bytes: bytes,
      fileName: fileName,
    );

    state = AsyncData([
      for (final item in current)
        if (item.id == quoteId) updated else item,
    ]);
  }
}

class QuoteItemsController
    extends FamilyAsyncNotifier<List<QuoteItemRecord>, String> {
  late final QuotesRepository _repository = ref.read(quotesRepositoryProvider);
  late String _quoteId;

  @override
  FutureOr<List<QuoteItemRecord>> build(String arg) async {
    _quoteId = arg;
    return _repository.fetchItemsByQuoteId(arg);
  }

  Future<void> save(QuoteItemRecord item) async {
    await _validateTemplateScope(item);

    final next = await AsyncValue.guard(() => _repository.saveItem(item));
    if (next.hasError) {
      Error.throwWithStackTrace(next.error!, next.stackTrace!);
    }
    state = next;
    await _syncTotals(next.valueOrNull ?? const []);
  }

  Future<void> remove(String itemId) async {
    final next = await AsyncValue.guard(
      () => _repository.deleteItem(quoteId: _quoteId, itemId: itemId),
    );
    if (next.hasError) {
      Error.throwWithStackTrace(next.error!, next.stackTrace!);
    }
    state = next;
    await _syncTotals(next.valueOrNull ?? const []);
  }

  Future<void> reload() async {
    state = await AsyncValue.guard(() => _repository.fetchItemsByQuoteId(_quoteId));
    await _syncTotals(state.valueOrNull ?? const []);
  }

  Future<void> _syncTotals(List<QuoteItemRecord> items) async {
    final subtotal = items.fold<double>(0, (sum, item) => sum + item.lineTotal);
    final tax = subtotal * 0.16;
    final total = subtotal + tax;
    await ref.read(quotesProvider.notifier).setTotals(
          quoteId: _quoteId,
          subtotal: subtotal,
          tax: tax,
          total: total,
        );
  }

  Future<void> _validateTemplateScope(QuoteItemRecord item) async {
    final templateId = item.templateId;
    if (templateId == null || templateId.isEmpty) {
      return;
    }

    final currentQuotes = ref.read(quotesProvider).valueOrNull;
    List<QuoteRecord> quotes = currentQuotes ?? const <QuoteRecord>[];
    if (quotes.isEmpty) {
      quotes = await _repository.fetchQuotes();
    }

    QuoteRecord? quote;
    for (final record in quotes) {
      if (record.id == item.quoteId) {
        quote = record;
        break;
      }
    }

    if (quote == null) {
      throw StateError('No se encontro la cotizacion para validar el concepto.');
    }

    final catalog = await ref.read(conceptsCatalogProvider.future);
    for (final template in catalog.templates) {
      if (template.id != templateId) {
        continue;
      }

      if (template.universeId != quote.universeId ||
          template.projectTypeId != quote.projectTypeId) {
        throw StateError(
          'El template seleccionado no corresponde al universo/tipo de la cotizacion.',
        );
      }
      return;
    }

    throw StateError('El template seleccionado no existe en el catalogo activo.');
  }
}
