import '../../../core/config/supabase_bootstrap.dart';
import '../../../core/logging/app_logger.dart';
import '../domain/quote_models.dart';

class QuotesRepository {
  static const List<ProjectLookup> _localProjects = [
    ProjectLookup(
      id: 'seed-project-001',
      code: 'PRJ001',
      name: 'Proyecto Demo Residencial',
    ),
  ];

  static final List<QuoteRecord> _localQuotes = [
    const QuoteRecord(
      id: 'seed-quote-001',
      projectId: 'seed-project-001',
      quoteNumber: 'RM-CL001-MNTO-PRJ001',
      status: 'draft',
      universeId: 'seed-u-recubrimientos',
      projectTypeId: 'seed-pt-mantenimiento',
      subtotal: 0,
      tax: 0,
      total: 0,
    ),
  ];

  static final Map<String, List<QuoteItemRecord>> _localItems = {
    'seed-quote-001': [],
  };

  Future<List<ProjectLookup>> fetchProjects() async {
    final client = SupabaseBootstrap.client;
    if (client == null) {
      return _localProjects;
    }

    try {
      final rows = await client
          .from('projects')
          .select('id, code, name, client_id')
          .order('created_at', ascending: false);

      final projects = [
        for (final row in rows)
          ProjectLookup(
            id: row['id'] as String,
            code: _normalizeProjectCode(row['code'] as String?, row['id'] as String),
            name: row['name'] as String? ?? 'Sin nombre',
            clientId: row['client_id'] as String?,
          ),
      ];

      if (projects.isEmpty) {
        return _localProjects;
      }

      return projects;
    } catch (error) {
      AppLogger.error('projects_fetch_failed', data: {'error': error.toString()});
      return _localProjects;
    }
  }

  Future<List<QuoteRecord>> fetchQuotes() async {
    final client = SupabaseBootstrap.client;
    if (client == null) {
      return _sortedLocalQuotes;
    }

    try {
      final rows = await client
          .from('quotes')
          .select(
            'id, project_id, quote_number, status, universe_id, project_type_id, subtotal, tax, total, valid_until, created_at',
          )
          .order('created_at', ascending: false);

      final quotes = [
        for (final row in rows)
          QuoteRecord(
            id: row['id'] as String,
            projectId: row['project_id'] as String? ?? '',
            quoteNumber: row['quote_number'] as String? ?? '',
            status: row['status'] as String? ?? 'draft',
            universeId: row['universe_id'] as String? ?? '',
            projectTypeId: row['project_type_id'] as String? ?? '',
            subtotal: _toDouble(row['subtotal']),
            tax: _toDouble(row['tax']),
            total: _toDouble(row['total']),
            validUntil: _toDate(row['valid_until']),
          ),
      ];
      if (quotes.isEmpty) {
        return _sortedLocalQuotes;
      }
      return quotes;
    } catch (error) {
      AppLogger.error('quotes_fetch_failed', data: {'error': error.toString()});
      return _sortedLocalQuotes;
    }
  }

  Future<QuoteRecord> createDraftQuote({
    required String projectId,
    required String universeId,
    required String projectTypeId,
  }) async {
    final client = SupabaseBootstrap.client;
    final quoteNumber = await _nextQuoteNumber(
      projectId: projectId,
      projectTypeId: projectTypeId,
      client: client,
    );

    if (
        client == null ||
        !_isUuid(projectId) ||
        !_isUuid(universeId) ||
        !_isUuid(projectTypeId)) {
      final local = QuoteRecord(
        id: 'seed-quote-${DateTime.now().millisecondsSinceEpoch}',
        projectId: projectId,
        quoteNumber: quoteNumber,
        status: 'draft',
        universeId: universeId,
        projectTypeId: projectTypeId,
        subtotal: 0,
        tax: 0,
        total: 0,
      );
      _localQuotes.add(local);
      _localItems[local.id] = [];
      return local;
    }

    try {
      final inserted = await client
          .from('quotes')
          .insert({
            'project_id': projectId,
            'quote_number': quoteNumber,
            'status': 'draft',
            'universe_id': universeId,
            'project_type_id': projectTypeId,
          })
          .select(
            'id, project_id, quote_number, status, universe_id, project_type_id, subtotal, tax, total, valid_until',
          )
          .single();

      return QuoteRecord(
        id: inserted['id'] as String,
        projectId: inserted['project_id'] as String? ?? '',
        quoteNumber: inserted['quote_number'] as String? ?? quoteNumber,
        status: inserted['status'] as String? ?? 'draft',
        universeId: inserted['universe_id'] as String? ?? universeId,
        projectTypeId: inserted['project_type_id'] as String? ?? projectTypeId,
        subtotal: _toDouble(inserted['subtotal']),
        tax: _toDouble(inserted['tax']),
        total: _toDouble(inserted['total']),
        validUntil: _toDate(inserted['valid_until']),
      );
    } catch (error) {
      AppLogger.error('quotes_create_failed', data: {'error': error.toString()});
      final local = QuoteRecord(
        id: 'seed-quote-${DateTime.now().millisecondsSinceEpoch}',
        projectId: projectId,
        quoteNumber: quoteNumber,
        status: 'draft',
        universeId: universeId,
        projectTypeId: projectTypeId,
        subtotal: 0,
        tax: 0,
        total: 0,
      );
      _localQuotes.add(local);
      _localItems[local.id] = [];
      return local;
    }
  }

  Future<QuoteRecord> updateTotals({
    required QuoteRecord quote,
    required double subtotal,
    required double tax,
    required double total,
  }) async {
    final updated = quote.copyWith(subtotal: subtotal, tax: tax, total: total);
    final client = SupabaseBootstrap.client;

    if (client == null || !_isUuid(quote.id)) {
      _replaceLocalQuote(updated);
      return updated;
    }

    try {
      await client.from('quotes').update({
        'subtotal': subtotal,
        'tax': tax,
        'total': total,
      }).eq('id', quote.id);
      return updated;
    } catch (error) {
      AppLogger.error('quotes_update_totals_failed', data: {'error': error.toString()});
      _replaceLocalQuote(updated);
      return updated;
    }
  }

  Future<List<QuoteItemRecord>> fetchItemsByQuoteId(String quoteId) async {
    final client = SupabaseBootstrap.client;
    if (client == null || !_isUuid(quoteId)) {
      return List<QuoteItemRecord>.from(_localItems[quoteId] ?? const []);
    }

    try {
      final rows = await client
          .from('quote_items')
          .select('id, quote_id, template_id, concept, generated_data, unit, quantity, unit_price, line_total')
          .eq('quote_id', quoteId);

      return [
        for (final row in rows)
          QuoteItemRecord(
            id: row['id'] as String,
            quoteId: row['quote_id'] as String? ?? quoteId,
            templateId: row['template_id'] as String?,
            concept: row['concept'] as String? ?? '',
            generatedData: _toMap(row['generated_data']),
            unit: row['unit'] as String? ?? '',
            quantity: _toDouble(row['quantity']),
            unitPrice: _toDouble(row['unit_price']),
            lineTotal: _toDouble(row['line_total']),
          ),
      ];
    } catch (error) {
      AppLogger.error('quote_items_fetch_failed', data: {'error': error.toString()});
      return List<QuoteItemRecord>.from(_localItems[quoteId] ?? const []);
    }
  }

  Future<List<QuoteItemRecord>> saveItem(QuoteItemRecord item) async {
    final client = SupabaseBootstrap.client;
    if (client == null || !_isUuid(item.quoteId)) {
      final items = List<QuoteItemRecord>.from(_localItems[item.quoteId] ?? const []);
      final next = [
        for (final current in items)
          if (current.id != item.id) current,
        item,
      ];
      _localItems[item.quoteId] = next;
      return next;
    }

    try {
      final payload = {
        'quote_id': item.quoteId,
        'template_id': item.templateId,
        'concept': item.concept,
        'generated_data': item.generatedData,
        'unit': item.unit,
        'quantity': item.quantity,
        'unit_price': item.unitPrice,
        'line_total': item.lineTotal,
      };

      if (_isUuid(item.id)) {
        await client.from('quote_items').update(payload).eq('id', item.id);
      } else {
        await client.from('quote_items').insert(payload);
      }

      return fetchItemsByQuoteId(item.quoteId);
    } catch (error) {
      AppLogger.error('quote_items_save_failed', data: {'error': error.toString()});
      final items = List<QuoteItemRecord>.from(_localItems[item.quoteId] ?? const []);
      final next = [
        for (final current in items)
          if (current.id != item.id) current,
        item,
      ];
      _localItems[item.quoteId] = next;
      return next;
    }
  }

  Future<List<QuoteItemRecord>> deleteItem({
    required String quoteId,
    required String itemId,
  }) async {
    final client = SupabaseBootstrap.client;
    if (client == null || !_isUuid(itemId)) {
      final items = List<QuoteItemRecord>.from(_localItems[quoteId] ?? const []);
      final next = [for (final item in items) if (item.id != itemId) item];
      _localItems[quoteId] = next;
      return next;
    }

    try {
      await client.from('quote_items').delete().eq('id', itemId);
      return fetchItemsByQuoteId(quoteId);
    } catch (error) {
      AppLogger.error('quote_items_delete_failed', data: {'error': error.toString()});
      final items = List<QuoteItemRecord>.from(_localItems[quoteId] ?? const []);
      final next = [for (final item in items) if (item.id != itemId) item];
      _localItems[quoteId] = next;
      return next;
    }
  }

  List<QuoteRecord> get _sortedLocalQuotes {
    final quotes = List<QuoteRecord>.from(_localQuotes);
    quotes.sort((a, b) => b.quoteNumber.compareTo(a.quoteNumber));
    return quotes;
  }

  void _replaceLocalQuote(QuoteRecord quote) {
    final index = _localQuotes.indexWhere((item) => item.id == quote.id);
    if (index >= 0) {
      _localQuotes[index] = quote;
      return;
    }
    _localQuotes.add(quote);
  }

  Future<String> _nextQuoteNumber({
    required String projectId,
    required String projectTypeId,
    required dynamic client,
  }) async {
    final projectCode = await _resolveProjectCode(projectId: projectId, client: client);
    final clientCode = await _resolveClientCode(projectId: projectId, client: client);
    final projectTypeKey = await _resolveProjectTypeKey(
      projectTypeId: projectTypeId,
      client: client,
    );

    return 'RM-$clientCode-$projectTypeKey-$projectCode';
  }

  Future<String> _resolveProjectCode({
    required String projectId,
    required dynamic client,
  }) async {
    if (client == null || !_isUuid(projectId)) {
      final localProject = _localProjects.firstWhere(
        (item) => item.id == projectId,
        orElse: () => const ProjectLookup(id: 'local-project', code: 'PRJ001', name: 'Proyecto', clientId: null),
      );
      return _normalizeProjectCode(localProject.code, projectId);
    }

    try {
      final row = await client.from('projects').select('id, code').eq('id', projectId).single();
      return _normalizeProjectCode(row['code'] as String?, row['id'] as String? ?? projectId);
    } catch (_) {
      return _fallbackProjectCode(projectId);
    }
  }

  Future<String> _resolveClientCode({
    required String projectId,
    required dynamic client,
  }) async {
    if (client == null || !_isUuid(projectId)) {
      return 'CL001';
    }

    try {
      final projectRow = await client.from('projects').select('client_id').eq('id', projectId).single();
      final clientId = projectRow['client_id'] as String?;
      if (clientId == null || clientId.isEmpty) {
        return 'CL001';
      }

      final clientRows = await client.from('clients').select('id').order('created_at');
      final ids = [for (final row in clientRows) row['id'] as String];
      final index = ids.indexOf(clientId);
      if (index < 0) {
        return 'CL001';
      }
      return 'CL${(index + 1).toString().padLeft(3, '0')}';
    } catch (_) {
      return 'CL001';
    }
  }

  Future<String> _resolveProjectTypeKey({
    required String projectTypeId,
    required dynamic client,
  }) async {
    if (client == null || !_isUuid(projectTypeId)) {
      return _projectTypeKeyFromRaw(projectTypeId);
    }

    try {
      final row = await client.from('project_types').select('name').eq('id', projectTypeId).single();
      return _projectTypeKeyFromRaw(row['name'] as String? ?? projectTypeId);
    } catch (_) {
      return _projectTypeKeyFromRaw(projectTypeId);
    }
  }

  String _projectTypeKeyFromRaw(String raw) {
    final value = raw.toLowerCase();
    if (value.contains('mantenimiento') || value.contains('manto')) {
      return 'MNTO';
    }
    if (value.contains('remodel')) {
      return 'RMD';
    }
    if (value.contains('constru')) {
      return 'CNST';
    }
    if (value.contains('seed-pt-mantenimiento')) {
      return 'MNTO';
    }
    if (value.contains('seed-pt-remodelacion')) {
      return 'RMD';
    }
    if (value.contains('seed-pt-construccion')) {
      return 'CNST';
    }
    return 'GEN';
  }

  String _normalizeProjectCode(String? code, String projectId) {
    final source = (code ?? '').toUpperCase().trim();
    final digits = RegExp(r'\d+').allMatches(source).map((m) => m.group(0)!).join();
    if (digits.isNotEmpty) {
      return 'PRJ${digits.padLeft(3, '0').substring(digits.length > 3 ? digits.length - 3 : 0)}';
    }
    return _fallbackProjectCode(projectId);
  }

  String _fallbackProjectCode(String projectId) {
    final clean = projectId.replaceAll('-', '');
    final tail = clean.length >= 3 ? clean.substring(clean.length - 3) : clean.padLeft(3, '0');
    return 'PRJ${tail.toUpperCase()}';
  }

  double _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse('$value') ?? 0;
  }

  DateTime? _toDate(Object? value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  Map<String, Object?>? _toMap(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, val) => MapEntry('$key', val));
    }
    return null;
  }

  bool _isUuid(String value) {
    final uuidPattern = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    );
    return uuidPattern.hasMatch(value);
  }
}
