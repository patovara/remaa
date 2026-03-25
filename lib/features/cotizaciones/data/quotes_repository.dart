import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../../../core/config/supabase_bootstrap.dart';
import '../../../core/logging/app_logger.dart';
import '../domain/quote_models.dart';

class QuotesRepository {
  static int _localProjectKeySeq = 1;

  static final List<ProjectLookup> _localProjects = [
    const ProjectLookup(
      id: 'seed-project-001',
      code: 'PRJ001',
      name: 'Proyecto Demo Residencial',
      siteAddress: 'Direccion demo',
      description: 'Proyecto de ejemplo local',
      managerName: 'Arq. Daniel M.',
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
      approvalPdfPath: null,
      approvalPdfUploadedAt: null,
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
          .select('id, code, name, client_id, site_address, description, manager_name')
          .order('created_at', ascending: false);

      final projects = [
        for (final row in rows)
          ProjectLookup(
            id: row['id'] as String,
            code: _normalizeProjectCode(row['code'] as String?, row['id'] as String),
            name: row['name'] as String? ?? 'Sin nombre',
            clientId: row['client_id'] as String?,
            siteAddress: row['site_address'] as String?,
            description: row['description'] as String?,
            managerName: row['manager_name'] as String?,
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

  Future<ProjectLookup> createProject({required NewProjectInput input}) async {
    final code = input.code.trim().toUpperCase();
    final name = input.name.trim();
    if (code.isEmpty || name.isEmpty) {
      throw StateError('La clave y nombre del proyecto son obligatorios.');
    }

    final client = SupabaseBootstrap.client;
    final canRemote =
        client != null &&
        input.clientId != null &&
        input.clientId!.isNotEmpty &&
        _isUuid(input.clientId!);

    if (!canRemote) {
      final local = ProjectLookup(
        id: 'seed-project-${DateTime.now().millisecondsSinceEpoch}',
        code: code,
        name: name,
        clientId: input.clientId,
        siteAddress: input.siteAddress,
        description: input.description,
        managerName: input.managerName,
      );
      _upsertLocalProject(local);
      return local;
    }

    try {
      final inserted = await client
          .from('projects')
          .insert({
            'client_id': input.clientId,
            'code': code,
            'name': name,
            'site_address': _asNullable(input.siteAddress),
            'description': _asNullable(input.description),
            'manager_name': _asNullable(input.managerName),
          })
          .select('id, code, name, client_id, site_address, description, manager_name')
          .single();

      return ProjectLookup(
        id: inserted['id'] as String,
        code: _normalizeProjectCode(inserted['code'] as String?, inserted['id'] as String),
        name: inserted['name'] as String? ?? name,
        clientId: inserted['client_id'] as String?,
        siteAddress: inserted['site_address'] as String?,
        description: inserted['description'] as String?,
        managerName: inserted['manager_name'] as String?,
      );
    } catch (error) {
      AppLogger.error('projects_create_failed', data: {'error': error.toString()});
      final local = ProjectLookup(
        id: 'seed-project-${DateTime.now().millisecondsSinceEpoch}',
        code: code,
        name: name,
        clientId: input.clientId,
        siteAddress: input.siteAddress,
        description: input.description,
        managerName: input.managerName,
      );
      _upsertLocalProject(local);
      return local;
    }
  }

  Future<void> updateProjectContext({
    required String projectId,
    required String name,
    required String managerName,
    required String address,
    required String description,
    String? clientId,
  }) async {
    final normalized = ProjectLookup(
      id: projectId,
      code: _projectCodeById(projectId),
      name: name.trim().isEmpty ? 'Proyecto sin nombre' : name.trim(),
      clientId: clientId,
      siteAddress: address.trim(),
      description: description.trim(),
      managerName: managerName.trim(),
    );

    final client = SupabaseBootstrap.client;
    final canRemote = client != null && _isUuid(projectId);
    if (!canRemote) {
      _upsertLocalProject(normalized);
      return;
    }

    try {
      final payload = <String, Object?>{
        'name': normalized.name,
        'manager_name': _asNullable(normalized.managerName),
        'site_address': _asNullable(normalized.siteAddress),
        'description': _asNullable(normalized.description),
      };
      if (clientId != null && clientId.isNotEmpty && _isUuid(clientId)) {
        payload['client_id'] = clientId;
      }
      await client.from('projects').update(payload).eq('id', projectId);
    } catch (error) {
      AppLogger.error('projects_update_context_failed', data: {'error': error.toString()});
      _upsertLocalProject(normalized);
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
            'id, project_id, quote_number, status, universe_id, project_type_id, subtotal, tax, total, valid_until, approval_pdf_path, approval_pdf_uploaded_at, created_at',
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
            approvalPdfPath: row['approval_pdf_path'] as String?,
            approvalPdfUploadedAt: _toDateTime(row['approval_pdf_uploaded_at']),
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
    String? projectKey,
  }) async {
    final client = SupabaseBootstrap.client;
    final quoteNumber = await _nextQuoteNumber(
      projectId: projectId,
      projectTypeId: projectTypeId,
      client: client,
      projectKey: projectKey,
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
        approvalPdfPath: null,
        approvalPdfUploadedAt: null,
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
            'id, project_id, quote_number, status, universe_id, project_type_id, subtotal, tax, total, valid_until, approval_pdf_path, approval_pdf_uploaded_at',
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
        approvalPdfPath: inserted['approval_pdf_path'] as String?,
        approvalPdfUploadedAt: _toDateTime(inserted['approval_pdf_uploaded_at']),
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
        approvalPdfPath: null,
        approvalPdfUploadedAt: null,
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

  Future<QuoteRecord> updateStatus({
    required QuoteRecord quote,
    required String status,
  }) async {
    if (status == 'approved' && !quote.hasApprovalPdf) {
      throw StateError('Debes adjuntar el PDF del pedido antes de aprobar la cotizacion.');
    }

    final updated = quote.copyWith(status: status);
    final client = SupabaseBootstrap.client;

    if (client == null || !_isUuid(quote.id)) {
      _replaceLocalQuote(updated);
      return updated;
    }

    try {
      await client.from('quotes').update({'status': status}).eq('id', quote.id);
      return updated;
    } catch (error) {
      AppLogger.error('quotes_update_status_failed', data: {'error': error.toString()});
      _replaceLocalQuote(updated);
      return updated;
    }
  }

  Future<QuoteRecord> attachApprovalPdf({
    required QuoteRecord quote,
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (bytes.isEmpty) {
      throw StateError('No se pudo leer el archivo PDF.');
    }

    final now = DateTime.now();
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final objectPath = '${quote.id}/${now.millisecondsSinceEpoch}_$safeName';
    final updated = quote.copyWith(
      approvalPdfPath: objectPath,
      approvalPdfUploadedAt: now,
    );

    final client = SupabaseBootstrap.client;
    if (client == null || !_isUuid(quote.id)) {
      _replaceLocalQuote(updated);
      return updated;
    }

    try {
      await client.storage.from('quote-approvals').uploadBinary(
            objectPath,
            bytes,
            fileOptions: const FileOptions(contentType: 'application/pdf', upsert: true),
          );

      await client.from('quotes').update({
        'approval_pdf_path': objectPath,
        'approval_pdf_uploaded_at': now.toUtc().toIso8601String(),
      }).eq('id', quote.id);

      return updated;
    } catch (error) {
      AppLogger.error('quotes_attach_approval_pdf_failed', data: {'error': error.toString()});
      throw StateError('No se pudo adjuntar el PDF del pedido.');
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

  Future<QuoteContextInfo> fetchQuoteContext({required String projectId}) async {
    final client = SupabaseBootstrap.client;
    if (client == null || !_isUuid(projectId)) {
      final project = _localProjects.firstWhere(
        (item) => item.id == projectId,
        orElse: () => const ProjectLookup(id: '', code: '', name: ''),
      );
      return QuoteContextInfo(
        projectName: project.name,
        clientName: 'Cliente no disponible',
        address: '',
        location: '',
        description: project.description ?? '',
      );
    }

    try {
      final project = await client
          .from('projects')
          .select('name, site_address, description, client_id')
          .eq('id', projectId)
          .single();

      final projectName = project['name'] as String? ?? '';
      final address = project['site_address'] as String? ?? '';
      final description = project['description'] as String? ?? '';
      final clientId = project['client_id'] as String?;

      if (clientId == null || clientId.isEmpty) {
        return QuoteContextInfo(
          projectName: projectName,
          clientName: 'Cliente no asignado',
          address: address,
          location: '',
          description: description,
        );
      }

      final clientRow = await client
          .from('clients')
          .select('business_name, city, state')
          .eq('id', clientId)
          .single();

      final clientName = clientRow['business_name'] as String? ?? '';
      final city = clientRow['city'] as String? ?? '';
      final state = clientRow['state'] as String? ?? '';
      final location = [city, state].where((value) => value.trim().isNotEmpty).join(', ');

      return QuoteContextInfo(
        projectName: projectName,
        clientName: clientName,
        address: address,
        location: location,
        description: description,
      );
    } catch (error) {
      AppLogger.error('quote_context_fetch_failed', data: {'error': error.toString()});
      return const QuoteContextInfo(
        projectName: '',
        clientName: '',
        address: '',
        location: '',
        description: '',
      );
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

  void _upsertLocalProject(ProjectLookup project) {
    final index = _localProjects.indexWhere((item) => item.id == project.id);
    if (index >= 0) {
      _localProjects[index] = project;
      return;
    }
    _localProjects.insert(0, project);
  }

  String _projectCodeById(String projectId) {
    for (final project in _localProjects) {
      if (project.id == projectId) {
        return project.code;
      }
    }
    return _fallbackProjectCode(projectId);
  }

  Future<String> _nextQuoteNumber({
    required String projectId,
    required String projectTypeId,
    required dynamic client,
    String? projectKey,
  }) async {
    final projectCode = await _resolveProjectCode(
      projectId: projectId,
      client: client,
      projectKey: projectKey,
    );
    final clientCode = await _resolveClientCode(projectId: projectId, client: client);
    final projectTypeKey = await _resolveProjectTypeKey(
      projectTypeId: projectTypeId,
      client: client,
    );

    final base = 'RM-$clientCode-$projectTypeKey-$projectCode';
    final seq = await _nextSeq(base: base, client: client);
    return '$base-${seq.toString().padLeft(3, '0')}';
  }

  Future<String> _resolveProjectCode({
    required String projectId,
    required dynamic client,
    String? projectKey,
  }) async {
    final manual = (projectKey ?? '').trim().toUpperCase();
    if (manual.isNotEmpty) {
      return manual;
    }

    return reserveProjectKey(client: client);
  }

  Future<String> reserveProjectKey({required dynamic client}) async {
    if (client == null) {
      return _nextLocalProjectKey();
    }

    try {
      final response = await client.rpc('next_project_key');
      if (response is String && response.trim().isNotEmpty) {
        return response.trim().toUpperCase();
      }
    } catch (_) {
      // fallback below
    }

    return _nextLocalProjectKey();
  }

  String _nextLocalProjectKey() {
    final value = _localProjectKeySeq++;
    return 'PRJ${value.toString().padLeft(3, '0')}';
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

      // Derive a stable 4-hex code from the UUID — no ordering, no race condition
      final clean = clientId.replaceAll('-', '').toUpperCase();
      final suffix = clean.length >= 4 ? clean.substring(0, 4) : clean.padLeft(4, '0');
      return 'CL$suffix';
    } catch (_) {
      return 'CL001';
    }
  }

  /// Returns the next available sequence number for a given folio base string.
  /// Counts existing quotes with that prefix and adds 1. Practically atomic for
  /// single-user apps; a unique constraint on quote_number in the DB provides
  /// the final safety net.
  Future<int> _nextSeq({required String base, required dynamic client}) async {
    // Local fallback
    final localCount = _localQuotes.where((q) => q.quoteNumber.startsWith(base)).length;
    if (client == null) {
      return localCount + 1;
    }
    try {
      final rows = await client
          .from('quotes')
          .select('id')
          .like('quote_number', '$base%');
      final remoteCount = (rows as List).length;
      return remoteCount + localCount + 1;
    } catch (_) {
      return localCount + 1;
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

  String? _asNullable(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
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

  DateTime? _toDateTime(Object? value) {
    if (value == null) {
      return null;
    }
    final raw = value.toString();
    if (raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
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
