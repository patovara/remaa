import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  }) async {
    final quote = await _repository.createDraftQuote(
      projectId: projectId,
      universeId: universeId,
      projectTypeId: projectTypeId,
    );
    final current = state.valueOrNull ?? const <QuoteRecord>[];
    state = AsyncData([quote, ...current]);
    return quote;
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
