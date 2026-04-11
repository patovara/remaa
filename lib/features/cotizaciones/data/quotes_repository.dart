import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../../../core/config/supabase_bootstrap.dart';
import '../../../core/logging/app_logger.dart';
import '../../clientes/presentation/clientes_mock_data.dart';
import '../domain/quote_models.dart';

class QuotesRepository {
  static int _localProjectKeySeq = 1;
  static const String _actaBucket = 'acta-files';

  static final List<ProjectLookup> _localProjects = [];

  static final List<QuoteRecord> _localQuotes = [];

  static final Map<String, List<QuoteItemRecord>> _localItems = {};

  static final Map<String, List<SurveyEntryRecord>> _localSurveyEntries = {};
  static final Map<String, ActaDocumentRecord> _localActaDocuments = {};

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

      final merged = <ProjectLookup>[...projects];
      final knownIds = projects.map((project) => project.id).toSet();
      for (final local in _localProjects) {
        if (knownIds.add(local.id)) {
          merged.add(local);
        }
      }

      return merged;
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
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw StateError('El proyecto debe tener nombre.');
    }

    final normalized = ProjectLookup(
      id: projectId,
      code: _projectCodeById(projectId),
      name: normalizedName,
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
    if (quote.isPaid && status != QuoteStatus.paid) {
      throw StateError('No puedes modificar una cotizacion ya pagada.');
    }

    if (quote.isActaFinalizada &&
        status != QuoteStatus.actaFinalizada &&
        status != QuoteStatus.paid) {
      throw StateError('No puedes modificar una cotizacion con acta finalizada.');
    }

    if (status == QuoteStatus.concluded) {
      await _ensureQuoteCanBeConcluded(quote);
    }
    if (status == QuoteStatus.approved) {
      if (!quote.isConcluded) {
        throw StateError('La cotizacion debe estar concluida antes de aprobarse.');
      }
      if (!quote.hasApprovalPdf) {
        throw StateError('Debes adjuntar el PDF del pedido antes de aprobar la cotizacion.');
      }
    }
    if (status == QuoteStatus.paid && !quote.isActaFinalizada) {
      throw StateError('La cotizacion debe estar por cobrar antes de marcarse como pagada.');
    }

    final shouldClearApprovalPdf =
        status == QuoteStatus.draft && (quote.isConcluded || quote.isDeclined);

    final updated = quote.copyWith(
      status: status,
      approvalPdfPath: shouldClearApprovalPdf ? '' : quote.approvalPdfPath,
      approvalPdfUploadedAt: shouldClearApprovalPdf ? null : quote.approvalPdfUploadedAt,
    );
    final client = SupabaseBootstrap.client;

    if (client == null || !_isUuid(quote.id)) {
      _replaceLocalQuote(updated);
      return updated;
    }

    try {
      final payload = <String, Object?>{'status': status};
      if (shouldClearApprovalPdf) {
        payload['approval_pdf_path'] = null;
        payload['approval_pdf_uploaded_at'] = null;
      }
      await client.from('quotes').update(payload).eq('id', quote.id);
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

    if (!quote.isConcluded) {
      throw StateError('Debes concluir la cotizacion antes de adjuntar el PDF de aprobacion.');
    }

    await _ensureApprovalPdfCanBeAttached(quote);

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
      final message = error.toString().toLowerCase();
      if (message.contains('row-level security') || message.contains('unauthorized')) {
        throw StateError(
          'No se pudo adjuntar el PDF del pedido. Revisa permisos del bucket quote-approvals en storage.',
        );
      }
      throw StateError('No se pudo adjuntar el PDF del pedido.');
    }
  }

  Future<bool> saveActaDocument({
    required String quoteId,
    required Uint8List bytes,
    required String fileName,
    List<ActaPhotoAssetInput> photos = const <ActaPhotoAssetInput>[],
  }) async {
    if (bytes.isEmpty) {
      throw StateError('No se pudo generar el PDF del acta.');
    }

    final now = DateTime.now();
    final localRecord = ActaDocumentRecord(
      quoteId: quoteId,
      fileName: fileName,
      bytes: bytes,
      createdAt: now,
    );
    _localActaDocuments[quoteId] = localRecord;

    final client = SupabaseBootstrap.client;
    if (client == null || !_isUuid(quoteId)) {
      return false;
    }

    try {
      final timestamp = now.millisecondsSinceEpoch;
      final pdfObjectPath = '$quoteId/pdf/${timestamp}_${_sanitizeStorageName(fileName)}';
      await client.storage.from(_actaBucket).uploadBinary(
            pdfObjectPath,
            bytes,
            fileOptions: const FileOptions(contentType: 'application/pdf', upsert: true),
          );

      final photoMetaMaps = <Map<String, Object?>>[];
      for (var index = 0; index < photos.length; index++) {
        final photo = photos[index];
        if (photo.bytes.isEmpty) {
          continue;
        }
        final ext = _guessImageExtension(photo.fileName);
        final photoObjectPath = '$quoteId/photos/${timestamp}_${index}_${photo.slot}.$ext';
        await client.storage.from(_actaBucket).uploadBinary(
              photoObjectPath,
              photo.bytes,
              fileOptions: FileOptions(
                contentType: photo.mimeType ?? 'image/jpeg',
                upsert: true,
              ),
            );
        photoMetaMaps.add({
          'slot': photo.slot,
          'object_path': photoObjectPath,
          'file_name': photo.fileName,
          'file_size_bytes': photo.fileSizeBytes,
          'mime_type': photo.mimeType,
        });
      }

      await client.from('quote_acta_assets').upsert({
        'quote_id': quoteId,
        'pdf_object_path': pdfObjectPath,
        'pdf_file_name': fileName,
        'pdf_file_size_bytes': bytes.length,
        'photo_meta': photoMetaMaps,
        'created_at': now.toUtc().toIso8601String(),
        'updated_at': now.toUtc().toIso8601String(),
      });

      _localActaDocuments[quoteId] = ActaDocumentRecord(
        quoteId: quoteId,
        fileName: fileName,
        bytes: bytes,
        createdAt: now,
        objectPath: pdfObjectPath,
        photoAssets: [for (final item in photoMetaMaps) _actaPhotoMetaFromMap(item)],
      );
      return true;
    } catch (error) {
      AppLogger.error('acta_document_save_failed', data: {'quoteId': quoteId, 'error': error.toString()});
      return false;
    }
  }

  Future<ActaDocumentRecord?> fetchActaDocument(String quoteId) async {
    final local = _localActaDocuments[quoteId];
    if (local != null) {
      return local;
    }

    final client = SupabaseBootstrap.client;
    if (client == null || !_isUuid(quoteId)) {
      return null;
    }

    try {
      final row = await client
          .from('quote_acta_assets')
          .select('quote_id, pdf_object_path, pdf_file_name, created_at, photo_meta')
          .eq('quote_id', quoteId)
          .maybeSingle();
      if (row == null) {
        return null;
      }

      final objectPath = (row['pdf_object_path'] as String? ?? '').trim();
      if (objectPath.isEmpty) {
        return null;
      }

      final bytes = await client.storage.from(_actaBucket).download(objectPath);
      if (bytes.isEmpty) {
        return null;
      }

      final record = ActaDocumentRecord(
        quoteId: row['quote_id'] as String? ?? quoteId,
        fileName: row['pdf_file_name'] as String? ?? 'acta_entrega_$quoteId.pdf',
        bytes: bytes,
        createdAt: _toDateTime(row['created_at']) ?? DateTime.now(),
        objectPath: objectPath,
        photoAssets: _parseActaPhotoMeta(row['photo_meta']),
      );
      _localActaDocuments[quoteId] = record;
      return record;
    } catch (error) {
      AppLogger.error('acta_document_fetch_failed', data: {'quoteId': quoteId, 'error': error.toString()});
      return null;
    }
  }

  Future<void> _ensureApprovalPdfCanBeAttached(QuoteRecord quote) async {
    final issues = <String>[];

    if (quote.isDeclined) {
      issues.add('la cotizacion esta declinada');
    }
    if (quote.isActaFinalizada) {
      issues.add('el acta ya fue finalizada');
    }
    if (!quote.isConcluded) {
      issues.add('la cotizacion aun no esta concluida');
    }

    final project = await _findProjectById(quote.projectId);
    final clientId = project?.clientId?.trim() ?? '';
    if (clientId.isEmpty) {
      issues.add('el proyecto no tiene un cliente registrado');
    }

    final items = await fetchItemsByQuoteId(quote.id);
    final hasValidItems = items.any(
      (item) => item.lineTotal > 0 && item.quantity > 0 && item.concept.trim().isNotEmpty,
    );
    if (!hasValidItems || quote.total <= 0) {
      issues.add('la cotizacion no esta concluida con conceptos e importe');
    }

    if (issues.isNotEmpty) {
      throw StateError(
        'No puedes adjuntar el PDF de aprobacion porque ${issues.join(', ')}.',
      );
    }
  }

  Future<void> _ensureQuoteCanBeConcluded(QuoteRecord quote) async {
    final issues = <String>[];

    final project = await _findProjectById(quote.projectId);
    final clientId = project?.clientId?.trim() ?? '';
    if (clientId.isEmpty) {
      issues.add('el proyecto no tiene un cliente registrado');
    }

    final items = await fetchItemsByQuoteId(quote.id);
    final hasValidItems = items.any(
      (item) => item.lineTotal > 0 && item.quantity > 0 && item.concept.trim().isNotEmpty,
    );
    if (!hasValidItems || quote.total <= 0) {
      issues.add('la cotizacion no tiene conceptos concluidos con importe');
    }

    if (issues.isNotEmpty) {
      throw StateError(
        'No puedes concluir la cotizacion porque ${issues.join(', ')}.',
      );
    }
  }

  Future<ProjectLookup?> _findProjectById(String projectId) async {
    final local = _localProjects.where((project) => project.id == projectId).cast<ProjectLookup?>().firstWhere(
          (project) => project != null,
          orElse: () => null,
        );
    if (local != null) {
      return local;
    }

    final client = SupabaseBootstrap.client;
    if (client == null || !_isUuid(projectId)) {
      return null;
    }

    try {
      final row = await client
          .from('projects')
          .select('id, code, name, client_id, site_address, description, manager_name')
          .eq('id', projectId)
          .maybeSingle();
      if (row == null) {
        return null;
      }
      return ProjectLookup(
        id: row['id'] as String? ?? projectId,
        code: _normalizeProjectCode(row['code'] as String?, row['id'] as String? ?? projectId),
        name: (row['name'] as String? ?? '').trim(),
        clientId: row['client_id'] as String?,
        siteAddress: row['site_address'] as String?,
        description: row['description'] as String?,
        managerName: row['manager_name'] as String?,
      );
    } catch (error) {
      AppLogger.error('project_lookup_for_approval_failed', data: {'projectId': projectId, 'error': error.toString()});
      return null;
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

  Future<List<QuoteItemRecord>> fetchRecentItemsByTemplate({
    required String templateId,
    int limit = 5,
  }) async {
    final cleanTemplateId = templateId.trim();
    if (cleanTemplateId.isEmpty) {
      return const [];
    }

    final client = SupabaseBootstrap.client;
    if (client == null) {
      final local = <QuoteItemRecord>[];
      for (final items in _localItems.values) {
        for (final item in items) {
          if ((item.templateId ?? '').trim() == cleanTemplateId) {
            local.add(item);
          }
        }
      }
      return local.reversed.take(limit).toList();
    }

    try {
      final rows = await client
          .from('quote_items')
          .select(
            'id, quote_id, template_id, concept, generated_data, unit, quantity, unit_price, line_total',
          )
          .eq('template_id', cleanTemplateId)
          .order('created_at', ascending: false)
          .limit(limit);

      return [
        for (final row in rows)
          QuoteItemRecord(
            id: row['id'] as String,
            quoteId: row['quote_id'] as String? ?? '',
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
      AppLogger.error('quote_items_recent_by_template_failed', data: {
        'template_id': cleanTemplateId,
        'error': error.toString(),
      });
      return const [];
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
      final localClientId = project.clientId?.trim() ?? '';
      final localClient = localClientId.isEmpty ? null : findClientById(localClientId);
      if (localClient != null) {
        final location = _composeLocation(
          city: localClient.city,
          state: localClient.state,
        );
        return QuoteContextInfo(
          projectName: project.name,
          clientName: _resolveClientDisplayName(
            contactName: localClient.contactName,
            businessName: localClient.name,
          ),
          address: _normalizeAddressForQuote(
            address: _firstNonEmpty([
              project.siteAddress,
              localClient.address,
            ]),
            location: location,
          ),
          location: location,
          description: project.description ?? '',
        );
      }

      if (client != null && localClientId.isNotEmpty && _isUuid(localClientId)) {
        try {
          final clientRow = await client
              .from('clients')
              .select('business_name, contact_name, address_line, city, state')
              .eq('id', localClientId)
              .single();
          final clientName = _resolveClientDisplayName(
            contactName: clientRow['contact_name'] as String?,
            businessName: clientRow['business_name'] as String?,
          );
          final addressLine = clientRow['address_line'] as String? ?? '';
          final normalizedLocation = _normalizeLocationParts(
            city: clientRow['city'] as String?,
            state: clientRow['state'] as String?,
          );
          final location = _composeLocation(
            city: normalizedLocation.city,
            state: normalizedLocation.state,
          );
          return QuoteContextInfo(
            projectName: project.name,
            clientName: clientName.isEmpty ? 'Cliente no disponible' : clientName,
            address: _normalizeAddressForQuote(
              address: _firstNonEmpty([
                project.siteAddress,
                addressLine,
              ]),
              location: location,
            ),
            location: location,
            description: project.description ?? '',
          );
        } catch (_) {}
      }

      return QuoteContextInfo(
        projectName: project.name,
        clientName: localClientId.isEmpty ? 'Cliente no asignado' : 'Cliente no disponible',
        address: (project.siteAddress ?? '').trim(),
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
          .select('business_name, contact_name, address_line, city, state')
          .eq('id', clientId)
          .single();

      final clientName = _resolveClientDisplayName(
        contactName: clientRow['contact_name'] as String?,
        businessName: clientRow['business_name'] as String?,
      );
      final addressLine = clientRow['address_line'] as String? ?? '';
      final normalizedLocation = _normalizeLocationParts(
        city: clientRow['city'] as String?,
        state: clientRow['state'] as String?,
      );
      final location = _composeLocation(
        city: normalizedLocation.city,
        state: normalizedLocation.state,
      );

      return QuoteContextInfo(
        projectName: projectName,
        clientName: clientName,
        address: _normalizeAddressForQuote(
          address: _firstNonEmpty([address, addressLine]),
          location: location,
        ),
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

  String _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final normalized = (value ?? '').trim();
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return '';
  }

  String _resolveClientDisplayName({
    String? contactName,
    String? businessName,
  }) {
    final preferredContact = (contactName ?? '').trim();
    if (preferredContact.isNotEmpty) {
      return preferredContact;
    }
    return (businessName ?? '').trim();
  }

  ({String city, String state}) _normalizeLocationParts({
    String? city,
    String? state,
  }) {
    final rawCity = (city ?? '').trim();
    final rawState = (state ?? '').trim();
    if (rawState.isNotEmpty) {
      return (city: rawCity, state: rawState);
    }

    if (!rawCity.contains(',')) {
      return (city: rawCity, state: rawState);
    }

    final parts = rawCity
        .split(',')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList();
    if (parts.length < 2) {
      return (city: rawCity, state: rawState);
    }

    return (
      city: parts.sublist(1).join(', '),
      state: parts.first,
    );
  }

  String _composeLocation({String? city, String? state}) {
    return [
      if ((state ?? '').trim().isNotEmpty) state!.trim(),
      if ((city ?? '').trim().isNotEmpty) city!.trim(),
    ].join(', ');
  }

  String _normalizeAddressForQuote({
    required String address,
    required String location,
  }) {
    var normalized = address.trim();
    final locationNormalized = location.trim();
    if (normalized.isEmpty || locationNormalized.isEmpty) {
      return normalized;
    }

    final suffix = ', $locationNormalized';
    while (normalized.toLowerCase().endsWith(suffix.toLowerCase())) {
      normalized = normalized.substring(0, normalized.length - suffix.length).trimRight();
      normalized = normalized.replaceAll(RegExp(r'[\s,]+$'), '');
    }
    return normalized;
  }

  Future<SurveyEntryRecord?> appendSurveyEntry({
    required String projectId,
    String? quoteId,
    required String description,
    required List<SurveyEvidenceInput> evidenceInputs,
  }) async {
    final trimmed = description.trim();
    final hasText = trimmed.isNotEmpty;
    final sanitizedInputs = [
      for (final input in evidenceInputs)
        if (input.bytes.isNotEmpty) input,
    ];
    final limitedInputs =
        sanitizedInputs.length <= 2 ? sanitizedInputs : sanitizedInputs.sublist(0, 2);
    final hasEvidence = limitedInputs.isNotEmpty;
    if (!hasText && !hasEvidence) {
      return null;
    }

    final client = SupabaseBootstrap.client;
    final canRemote = client != null && _isUuid(projectId);
    if (!canRemote) {
      final local = SurveyEntryRecord(
        id: 'local-entry-${DateTime.now().millisecondsSinceEpoch}',
        projectId: projectId,
        quoteId: quoteId,
        description: trimmed,
        evidencePaths: [
          for (var index = 0; index < limitedInputs.length; index++)
            'local://$projectId/${DateTime.now().millisecondsSinceEpoch}_$index',
        ],
        evidencePreviewList: [for (final input in limitedInputs) input.bytes],
        evidenceMetadata: [
          for (var index = 0; index < limitedInputs.length; index++)
            SurveyEvidenceMeta(
              objectPath: 'local://$projectId/${DateTime.now().millisecondsSinceEpoch}_$index',
              originalName: limitedInputs[index].originalName,
              fileSizeBytes: limitedInputs[index].fileSizeBytes,
              sortOrder: index,
              mimeType: limitedInputs[index].mimeType,
            ),
        ],
        createdAt: DateTime.now(),
      );
      final items = List<SurveyEntryRecord>.from(_localSurveyEntries[projectId] ?? const []);
      items.add(local);
      _localSurveyEntries[projectId] = items;
      return local;
    }

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final quoteFolder = _isUuid(quoteId ?? '') ? quoteId! : 'no-quote';
      final evidencePaths = <String>[];

      final evidenceMetaMaps = <Map<String, Object?>>[];
      for (var index = 0; index < limitedInputs.length; index++) {
        final input = limitedInputs[index];
        final ext = _guessImageExtension(input.originalName);
        final objectPath = '$projectId/$quoteFolder/${timestamp}_$index.$ext';
        await client.storage.from('survey-photos').uploadBinary(
              objectPath,
              input.bytes,
              fileOptions: const FileOptions(upsert: true),
            );
        evidencePaths.add(objectPath);
        evidenceMetaMaps.add({
          'object_path': objectPath,
          'original_name': input.originalName,
          'mime_type': input.mimeType,
          'file_size_bytes': input.fileSizeBytes,
          'sort_order': index,
          'width_px': null,
          'height_px': null,
          'taken_at': null,
        });
      }

      // Get current user for ownership tracking
      final currentUser = client.auth.currentUser;
      final currentUserId = currentUser?.id;
      
      final payload = <String, Object?>{
        'project_id': projectId,
        'description': _asNullable(trimmed),
        'evidence_paths': evidencePaths,
        'evidence_meta': evidenceMetaMaps,
        if (currentUserId != null) 'captured_by_user_id': currentUserId,
      };
      if (_isUuid(quoteId ?? '')) {
        payload['quote_id'] = quoteId;
      }

      final inserted = await client
          .from('project_survey_entries')
          .insert(payload)
          .select('id, description, created_at')
          .single();

      return SurveyEntryRecord(
        id: inserted['id'] as String?,
        projectId: projectId,
        quoteId: _isUuid(quoteId ?? '') ? quoteId : null,
        description: inserted['description'] as String? ?? trimmed,
        evidencePaths: evidencePaths,
        evidencePreviewList: [for (final input in limitedInputs) input.bytes],
        evidenceMetadata: [
          for (var index = 0; index < limitedInputs.length; index++)
            SurveyEvidenceMeta(
              objectPath: evidencePaths[index],
              originalName: limitedInputs[index].originalName,
              fileSizeBytes: limitedInputs[index].fileSizeBytes,
              sortOrder: index,
              mimeType: limitedInputs[index].mimeType,
            ),
        ],
        createdAt: _toDateTime(inserted['created_at']),
      );
    } catch (error) {
      AppLogger.error('survey_entry_append_failed', data: {'error': error.toString()});
      final local = SurveyEntryRecord(
        id: 'local-entry-${DateTime.now().millisecondsSinceEpoch}',
        projectId: projectId,
        quoteId: quoteId,
        description: trimmed,
        evidencePaths: [
          for (var index = 0; index < limitedInputs.length; index++)
            'local://$projectId/${DateTime.now().millisecondsSinceEpoch}_$index',
        ],
        evidencePreviewList: [for (final input in limitedInputs) input.bytes],
        evidenceMetadata: [
          for (var index = 0; index < limitedInputs.length; index++)
            SurveyEvidenceMeta(
              objectPath: 'local://$projectId/${DateTime.now().millisecondsSinceEpoch}_$index',
              originalName: limitedInputs[index].originalName,
              fileSizeBytes: limitedInputs[index].fileSizeBytes,
              sortOrder: index,
              mimeType: limitedInputs[index].mimeType,
            ),
        ],
        createdAt: DateTime.now(),
      );
      final items = List<SurveyEntryRecord>.from(_localSurveyEntries[projectId] ?? const []);
      items.add(local);
      _localSurveyEntries[projectId] = items;
      return local;
    }
  }

  Future<List<SurveyEntryRecord>> fetchSurveyEntries({required String projectId}) async {
    final client = SupabaseBootstrap.client;
    final localItems = List<SurveyEntryRecord>.from(_localSurveyEntries[projectId] ?? const []);

    if (client == null || !_isUuid(projectId)) {
      return localItems;
    }

    try {
      final rows = await client
          .from('project_survey_entries')
          .select('id, quote_id, description, evidence_paths, evidence_meta, created_at')
          .eq('project_id', projectId)
          .order('created_at', ascending: true);

      final entries = <SurveyEntryRecord>[];
      for (final row in rows) {
        final evidencePathsDynamic = row['evidence_paths'];
        final evidencePaths = <String>[
          if (evidencePathsDynamic is List)
            for (final item in evidencePathsDynamic)
              if (item is String && item.trim().isNotEmpty) item.trim(),
        ];

        final evidenceMetaDynamic = row['evidence_meta'];
        final evidenceMeta = <SurveyEvidenceMeta>[];
        if (evidenceMetaDynamic is List) {
          for (final item in evidenceMetaDynamic) {
            if (item is Map<String, dynamic>) {
              final objectPath = (item['object_path'] as String? ?? '').trim();
              if (objectPath.isEmpty) continue;
              evidenceMeta.add(
                SurveyEvidenceMeta(
                  objectPath: objectPath,
                  originalName: item['original_name'] as String? ?? objectPath,
                  fileSizeBytes: (item['file_size_bytes'] as num?)?.toInt() ?? 0,
                  sortOrder: (item['sort_order'] as num?)?.toInt() ?? evidenceMeta.length,
                  mimeType: item['mime_type'] as String?,
                  widthPx: (item['width_px'] as num?)?.toInt(),
                  heightPx: (item['height_px'] as num?)?.toInt(),
                  takenAt: _toDateTime(item['taken_at']),
                ),
              );
            }
          }
        }

        final sources = evidenceMeta.isNotEmpty
            ? evidenceMeta.map((meta) => meta.objectPath).toList()
            : evidencePaths;

        final evidence = <Uint8List>[];
        if (sources.isNotEmpty) {
          final downloads = await Future.wait(
            sources.map((path) async {
              try {
                final bytes = await client.storage.from('survey-photos').download(path);
                return bytes.isNotEmpty ? bytes : null;
              } catch (_) {
                return null;
              }
            }),
          );
          for (final bytes in downloads) {
            if (bytes != null) {
              evidence.add(bytes);
            }
          }
        }

        entries.add(
          SurveyEntryRecord(
            id: row['id'] as String?,
            projectId: projectId,
            quoteId: row['quote_id'] as String?,
            description: row['description'] as String? ?? '',
            evidencePaths: evidencePaths,
            evidencePreviewList: evidence,
            evidenceMetadata: evidenceMeta,
            createdAt: _toDateTime(row['created_at']),
          ),
        );
      }

      if (entries.isEmpty) {
        return localItems;
      }
      return [...entries, ...localItems];
    } catch (error) {
      AppLogger.error('survey_entries_fetch_failed', data: {'error': error.toString()});
      return localItems;
    }
  }

  Future<SurveyEntryRecord?> updateSurveyEntry({
    required String projectId,
    required String entryId,
    String? quoteId,
    required String description,
    List<SurveyEvidenceInput>? replacementEvidenceInputs,
    bool clearEvidence = false,
    List<String> existingEvidencePaths = const <String>[],
  }) async {
    final trimmed = description.trim();
    final incoming = replacementEvidenceInputs == null
        ? null
        : [
            for (final input in replacementEvidenceInputs)
              if (input.bytes.isNotEmpty) input,
          ];
    final shouldReplaceEvidence = incoming != null || clearEvidence;
    final limitedInputs = incoming == null
        ? const <SurveyEvidenceInput>[]
        : (incoming.length <= 2 ? incoming : incoming.sublist(0, 2));

    final client = SupabaseBootstrap.client;
    final canRemote = client != null && _isUuid(projectId) && _isUuid(entryId);
    if (!canRemote) {
      final items = List<SurveyEntryRecord>.from(_localSurveyEntries[projectId] ?? const []);
      final index = items.indexWhere((item) => item.id == entryId);
      if (index < 0) {
        return null;
      }
      final current = items[index];
      final nextEvidencePaths = shouldReplaceEvidence
          ? [
              for (var i = 0; i < limitedInputs.length; i++)
                'local://$projectId/${DateTime.now().millisecondsSinceEpoch}_$i',
            ]
          : current.evidencePaths;
      final nextEvidenceMeta = shouldReplaceEvidence
          ? [
              for (var i = 0; i < limitedInputs.length; i++)
                SurveyEvidenceMeta(
                  objectPath: nextEvidencePaths[i],
                  originalName: limitedInputs[i].originalName,
                  fileSizeBytes: limitedInputs[i].fileSizeBytes,
                  sortOrder: i,
                  mimeType: limitedInputs[i].mimeType,
                ),
            ]
          : current.evidenceMetadata;
      final updated = SurveyEntryRecord(
        id: current.id,
        projectId: current.projectId,
        quoteId: current.quoteId,
        description: trimmed,
        evidencePaths: nextEvidencePaths,
        evidencePreviewList:
            shouldReplaceEvidence ? [for (final input in limitedInputs) input.bytes] : current.evidencePreviewList,
        evidenceMetadata: nextEvidenceMeta,
        createdAt: current.createdAt,
      );
      items[index] = updated;
      _localSurveyEntries[projectId] = items;
      return updated;
    }

    try {
      final payload = <String, Object?>{
        'description': _asNullable(trimmed),
      };

      final uploadedPaths = <String>[];
      final uploadedMeta = <Map<String, Object?>>[];
      if (shouldReplaceEvidence) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final quoteFolder = _isUuid(quoteId ?? '') ? quoteId! : 'no-quote';
        for (var index = 0; index < limitedInputs.length; index++) {
          final input = limitedInputs[index];
          final ext = _guessImageExtension(input.originalName);
          final objectPath = '$projectId/$quoteFolder/${timestamp}_edit_$index.$ext';
          await client.storage.from('survey-photos').uploadBinary(
                objectPath,
                input.bytes,
                fileOptions: const FileOptions(upsert: true),
              );
          uploadedPaths.add(objectPath);
          uploadedMeta.add({
            'object_path': objectPath,
            'original_name': input.originalName,
            'mime_type': input.mimeType,
            'file_size_bytes': input.fileSizeBytes,
            'sort_order': index,
            'width_px': null,
            'height_px': null,
            'taken_at': null,
          });
        }

        payload['evidence_paths'] = uploadedPaths;
        payload['evidence_meta'] = uploadedMeta;
      }

      final updated = await client
          .from('project_survey_entries')
          .update(payload)
          .eq('id', entryId)
          .select('id, project_id, quote_id, description, evidence_paths, evidence_meta, created_at')
          .single();

      if (shouldReplaceEvidence && existingEvidencePaths.isNotEmpty) {
        try {
          await client.storage.from('survey-photos').remove(existingEvidencePaths);
        } catch (_) {
          // Best effort cleanup for replaced files.
        }
      }

      final updatedPathsDynamic = updated['evidence_paths'];
      final updatedPaths = <String>[
        if (updatedPathsDynamic is List)
          for (final item in updatedPathsDynamic)
            if (item is String && item.trim().isNotEmpty) item.trim(),
      ];

      final updatedMetaDynamic = updated['evidence_meta'];
      final updatedMeta = <SurveyEvidenceMeta>[];
      if (updatedMetaDynamic is List) {
        for (final item in updatedMetaDynamic) {
          if (item is Map<String, dynamic>) {
            final objectPath = (item['object_path'] as String? ?? '').trim();
            if (objectPath.isEmpty) {
              continue;
            }
            updatedMeta.add(
              SurveyEvidenceMeta(
                objectPath: objectPath,
                originalName: item['original_name'] as String? ?? objectPath,
                fileSizeBytes: (item['file_size_bytes'] as num?)?.toInt() ?? 0,
                sortOrder: (item['sort_order'] as num?)?.toInt() ?? updatedMeta.length,
                mimeType: item['mime_type'] as String?,
                widthPx: (item['width_px'] as num?)?.toInt(),
                heightPx: (item['height_px'] as num?)?.toInt(),
                takenAt: _toDateTime(item['taken_at']),
              ),
            );
          }
        }
      }

      return SurveyEntryRecord(
        id: updated['id'] as String?,
        projectId: updated['project_id'] as String?,
        quoteId: updated['quote_id'] as String?,
        description: updated['description'] as String? ?? trimmed,
        evidencePaths: updatedPaths,
        evidencePreviewList: shouldReplaceEvidence
            ? [for (final input in limitedInputs) input.bytes]
            : const <Uint8List>[],
        evidenceMetadata: updatedMeta,
        createdAt: _toDateTime(updated['created_at']),
      );
    } catch (error) {
      AppLogger.error('survey_entry_update_failed', data: {'error': error.toString(), 'entry_id': entryId});
      return null;
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
    if (_isStructuredProjectKey(projectCode)) {
      return projectCode;
    }

    final clientCode = await _resolveClientCode(projectId: projectId, client: client);
    final projectTypeKey = await _resolveProjectTypeKey(
      projectTypeId: projectTypeId,
      client: client,
    );

    final base = 'RM-$clientCode-$projectTypeKey-$projectCode';
    return base;
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

    return reserveProjectKey(
      client: client,
      projectTypeId: null,
      clientId: null,
    );
  }

  Future<String> reserveProjectKey({
    required dynamic client,
    String? clientId,
    String? projectTypeId,
  }) async {
    if (client == null) {
      return _nextLocalProjectKey();
    }

    final normalizedClientId = (clientId ?? '').trim();
    final normalizedProjectTypeId = (projectTypeId ?? '').trim();
    final hasStructuredParams = _isUuid(normalizedClientId) && _isUuid(normalizedProjectTypeId);

    try {
      if (hasStructuredParams) {
        final structuredResponse = await client.rpc(
          'next_structured_project_key',
          params: {
            'p_client_id': normalizedClientId,
            'p_project_type_id': normalizedProjectTypeId,
          },
        );
        if (structuredResponse is String && structuredResponse.trim().isNotEmpty) {
          return structuredResponse.trim().toUpperCase();
        }
      }

      final response = await client.rpc('next_project_key');
      if (response is String && response.trim().isNotEmpty) {
        return response.trim().toUpperCase();
      }
    } catch (_) {
      // fallback below
    }

    return _nextLocalProjectKey();
  }

  bool _isStructuredProjectKey(String value) {
    final normalized = value.trim().toUpperCase();
    return RegExp(r'^RM-[A-Z]{3}-[0-9]{3,}-[A-Z]{4}-PRJ[0-9]{3,}$').hasMatch(normalized);
  }

  String _nextLocalProjectKey() {
    final value = _localProjectKeySeq++;
    final millis = DateTime.now().millisecondsSinceEpoch;
    return 'PRJ$millis${value.toString().padLeft(2, '0')}';
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
      return 'RMDL';
    }
    if (value.contains('constru')) {
      return 'CONS';
    }
    if (value.contains('seed-pt-mantenimiento')) {
      return 'MNTO';
    }
    if (value.contains('seed-pt-remodelacion')) {
      return 'RMDL';
    }
    if (value.contains('seed-pt-construccion')) {
      return 'CONS';
    }
    return 'GEN';
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

  List<ActaPhotoAssetMeta> _parseActaPhotoMeta(Object? raw) {
    if (raw is! List) {
      return const <ActaPhotoAssetMeta>[];
    }
    final items = <ActaPhotoAssetMeta>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        items.add(_actaPhotoMetaFromMap(item));
      } else if (item is Map) {
        items.add(
          _actaPhotoMetaFromMap(item.map((key, value) => MapEntry('$key', value))),
        );
      }
    }
    return items;
  }

  ActaPhotoAssetMeta _actaPhotoMetaFromMap(Map<String, Object?> item) {
    return ActaPhotoAssetMeta(
      slot: item['slot'] as String? ?? 'durante',
      objectPath: item['object_path'] as String? ?? '',
      fileName: item['file_name'] as String? ?? 'imagen.jpg',
      fileSizeBytes: item['file_size_bytes'] as int? ?? 0,
      mimeType: item['mime_type'] as String?,
    );
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
