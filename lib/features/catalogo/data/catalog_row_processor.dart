import '../../../core/config/supabase_bootstrap.dart';
import '../../../core/logging/app_logger.dart';
import '../../cotizaciones/domain/concept_generation.dart';
import '../domain/catalog_admin_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Result types
// ─────────────────────────────────────────────────────────────────────────────

/// Counters and optional issue for one processed row.
class CatalogRowResult {
  const CatalogRowResult({
    this.universeCreated = false,
    this.templateCreated = false,
    this.attributeCreated = false,
    this.optionCreated = false,
    this.issue,
  });

  final bool universeCreated;
  final bool templateCreated;
  final bool attributeCreated;
  final bool optionCreated;
  final CatalogImportIssue? issue;

  bool get hasIssue => issue != null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Processor
// ─────────────────────────────────────────────────────────────────────────────

/// Processes [CatalogImportRow]s one at a time with a seeded in-memory cache.
///
/// **Usage**
/// ```dart
/// final snapshot = await repository.fetchCatalog();
/// final processor = await CatalogRowProcessor.fromSnapshot(snapshot);
/// for (final row in parsedRows) {
///   final result = await processor.processRow(row, defaultProjectTypeId: id);
/// }
/// ```
///
/// The cache is seeded once from [snapshot] and extended as new entities are
/// created, so no full-catalog re-fetch happens between rows.
class CatalogRowProcessor {
  CatalogRowProcessor._({
    required Map<String, String> universeCache,
    required Map<String, String> projectTypeCache,
    required Map<String, String> templateCache,
    required Map<String, String> attributeCache,
    required Map<String, String> optionCache,
    required String defaultClosureId,
  })  : _universeCache = universeCache,
        _projectTypeCache = projectTypeCache,
        _templateCache = templateCache,
        _attributeCache = attributeCache,
        _optionCache = optionCache,
        _defaultClosureId = defaultClosureId;

  /// Cache keys
  ///   Universe   : norm(name)
  ///   ProjectType: norm(name)
  ///   Template   : "$universeId|$projectTypeId|norm(name)"
  ///   Attribute  : "$templateId|norm(name)"
  ///   Option     : "$attributeId|norm(value)"
  final Map<String, String> _universeCache;
  final Map<String, String> _projectTypeCache;
  final Map<String, String> _templateCache;
  final Map<String, String> _attributeCache;
  final Map<String, String> _optionCache;
  final String _defaultClosureId;

  // ── Factory ────────────────────────────────────────────────────────────────

  /// Builds the processor from an existing snapshot.
  /// Also ensures a default closure exists in the DB (creates it if missing).
  static Future<CatalogRowProcessor> fromSnapshot(
    ConceptCatalogSnapshot snapshot,
  ) async {
    final universeCache = {
      for (final u in snapshot.universes) _norm(u.name): u.id,
    };
    final projectTypeCache = {
      for (final pt in snapshot.projectTypes) _norm(pt.name): pt.id,
    };
    final templateCache = {
      for (final t in snapshot.templates)
        '${t.universeId}|${t.projectTypeId}|${_norm(t.name)}': t.id,
    };
    final attributeCache = {
      for (final a in snapshot.attributes) '${a.templateId}|${_norm(a.name)}': a.id,
    };
    final optionCache = {
      for (final o in snapshot.options) '${o.attributeId}|${_norm(o.value)}': o.id,
    };

    final closureId = await _ensureDefaultClosure(snapshot);

    return CatalogRowProcessor._(
      universeCache: universeCache,
      projectTypeCache: projectTypeCache,
      templateCache: templateCache,
      attributeCache: attributeCache,
      optionCache: optionCache,
      defaultClosureId: closureId,
    );
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Processes a single CSV row.
  ///
  /// Steps (in order):
  ///   1. Resolve universe  → create if missing
  ///   2. Resolve project_type → error if missing (never auto-created)
  ///   3. Resolve concept template → create if missing
  ///   4. Resolve attribute → create if missing
  ///   5. Resolve option   → create if missing
  ///
  /// All lookups and writes go through the internal cache — each DB write fires
  /// only once per unique entity per import session.
  Future<CatalogRowResult> processRow(
    CatalogImportRow row, {
    required String defaultProjectTypeId,
  }) async {
    var universeCreated = false;
    var templateCreated = false;
    var attributeCreated = false;
    var optionCreated = false;

    try {
      // ── 1. Universe ────────────────────────────────────────────────────────
      final univKey = _norm(row.universe);
      if (!_universeCache.containsKey(univKey)) {
        AppLogger.info('catalog_row_processor.create_universe', data: {'name': row.universe});
        final id = await _resolveOrInsertUniverse(row.universe.trim());
        _universeCache[univKey] = id;
        universeCreated = true;
      }
      final universeId = _universeCache[univKey]!;

      // ── 2. Project type (resolve only) ────────────────────────────────────
      String projectTypeId = defaultProjectTypeId;
      if (row.projectType != null && row.projectType!.trim().isNotEmpty) {
        final ptKey = _norm(row.projectType!);
        if (!_projectTypeCache.containsKey(ptKey)) {
          return CatalogRowResult(
            universeCreated: universeCreated,
            issue: CatalogImportIssue(
              lineNumber: row.lineNumber,
              message: 'project_type no encontrado: "${row.projectType}". '
                  'Créalo primero desde la pantalla de catálogo.',
            ),
          );
        }
        projectTypeId = _projectTypeCache[ptKey]!;
      }

      // ── 3. Concept template ────────────────────────────────────────────────
      final tplKey = '$universeId|$projectTypeId|${_norm(row.concept)}';
      if (!_templateCache.containsKey(tplKey)) {
        AppLogger.info('catalog_row_processor.create_template', data: {'concept': row.concept});
        final id = await _upsertTemplate(
          universeId: universeId,
          projectTypeId: projectTypeId,
          closureId: _defaultClosureId,
          name: row.concept.trim(),
          baseDescription: row.baseDescription ?? '',
          defaultUnit: row.unit.trim(),
          basePrice: row.basePrice,
        );
        _templateCache[tplKey] = id;
        templateCreated = true;
      }
      final templateId = _templateCache[tplKey]!;

      // ── 4. Attribute ───────────────────────────────────────────────────────
      final attrKey = '$templateId|${_norm(row.attribute)}';
      if (!_attributeCache.containsKey(attrKey)) {
        AppLogger.info('catalog_row_processor.create_attribute', data: {'attribute': row.attribute});
        final id = await _upsertAttribute(
          templateId: templateId,
          name: row.attribute.trim(),
        );
        _attributeCache[attrKey] = id;
        attributeCreated = true;
      }
      final attributeId = _attributeCache[attrKey]!;

      // ── 5. Option ──────────────────────────────────────────────────────────
      final optKey = '$attributeId|${_norm(row.option)}';
      if (!_optionCache.containsKey(optKey)) {
        AppLogger.info('catalog_row_processor.create_option', data: {'option': row.option});
        final id = await _upsertOption(
          attributeId: attributeId,
          value: row.option.trim(),
        );
        _optionCache[optKey] = id;
        optionCreated = true;
      }
    } catch (error) {
      final errorStr = error.toString();
      final isPermissionDenied = errorStr.contains('42501') || 
          errorStr.contains('insufficient_privilege');
      
      AppLogger.error('catalog_row_processor.row_failed', data: {
        'line': row.lineNumber,
        'error': errorStr,
        'is_permission_denied': isPermissionDenied,
      });
      return CatalogRowResult(
        universeCreated: universeCreated,
        templateCreated: templateCreated,
        attributeCreated: attributeCreated,
        optionCreated: optionCreated,
        issue: CatalogImportIssue(
          lineNumber: row.lineNumber,
          message: isPermissionDenied
              ? 'Permiso insuficiente (RLS 42501): Verifica tu rol de admin y políticas de catálogo.'
              : errorStr,
        ),
      );
    }

    return CatalogRowResult(
      universeCreated: universeCreated,
      templateCreated: templateCreated,
      attributeCreated: attributeCreated,
      optionCreated: optionCreated,
    );
  }

  // ── DB helpers ─────────────────────────────────────────────────────────────

  /// Universes has no unique constraint on name, so we SELECT first,
  /// then INSERT only if not found.
  Future<String> _resolveOrInsertUniverse(String name) async {
    final client = SupabaseBootstrap.client;
    if (client == null) return _localId('universe');

    final normName = _norm(name);
    final rows = await client.from('universes').select('id, name');
    for (final row in rows as List<dynamic>) {
      final r = row as Map<String, dynamic>;
      if (_norm(r['name'] as String) == normName) {
        return r['id'] as String;
      }
    }

    final inserted = await client
        .from('universes')
        .insert({'name': name})
        .select('id')
        .single();
    return inserted['id'] as String;
  }

  /// Uses the DB unique constraint `(universe_id, name)` for atomic upsert.
  /// Returns the id of the existing or newly created row.
  Future<String> _upsertTemplate({
    required String universeId,
    required String projectTypeId,
    required String closureId,
    required String name,
    required String baseDescription,
    required String defaultUnit,
    required double basePrice,
  }) async {
    final client = SupabaseBootstrap.client;
    if (client == null) return _localId('template');

    // ignoreDuplicates: true → returns null when row already existed.
    final row = await client
        .from('concept_templates')
        .upsert(
          {
            'universe_id': universeId,
            'project_type_id': projectTypeId,
            'closure_id': closureId,
            'name': name,
            'base_description': baseDescription,
            'default_unit': defaultUnit,
            'base_price': basePrice,
          },
          onConflict: 'universe_id,project_type_id,name',
          ignoreDuplicates: true,
        )
        .select('id')
        .maybeSingle();

    if (row != null) return row['id'] as String;

    // Row already existed — fetch its id.
    final existing = await client
        .from('concept_templates')
        .select('id')
        .eq('universe_id', universeId)
        .eq('project_type_id', projectTypeId)
        .ilike('name', name)
        .single();
    return existing['id'] as String;
  }

  /// Uses the DB unique constraint `(concept_template_id, name)`.
  Future<String> _upsertAttribute({
    required String templateId,
    required String name,
  }) async {
    final client = SupabaseBootstrap.client;
    if (client == null) return _localId('attribute');

    final row = await client
        .from('concept_attributes')
        .upsert(
          {'concept_template_id': templateId, 'name': name},
          onConflict: 'concept_template_id,name',
          ignoreDuplicates: true,
        )
        .select('id')
        .maybeSingle();

    if (row != null) return row['id'] as String;

    final existing = await client
        .from('concept_attributes')
        .select('id')
        .eq('concept_template_id', templateId)
        .ilike('name', name)
        .single();
    return existing['id'] as String;
  }

  /// Uses the DB unique constraint `(attribute_id, value)`.
  Future<String> _upsertOption({
    required String attributeId,
    required String value,
  }) async {
    final client = SupabaseBootstrap.client;
    if (client == null) return _localId('option');

    final row = await client
        .from('attribute_options')
        .upsert(
          {'attribute_id': attributeId, 'value': value},
          onConflict: 'attribute_id,value',
          ignoreDuplicates: true,
        )
        .select('id')
        .maybeSingle();

    if (row != null) return row['id'] as String;

    final existing = await client
        .from('attribute_options')
        .select('id')
        .eq('attribute_id', attributeId)
        .ilike('value', value)
        .single();
    return existing['id'] as String;
  }

  // ── Closure ────────────────────────────────────────────────────────────────

  static const _defaultClosureText =
      'INCLUYE MATERIAL DE PRIMERA CALIDAD, CORTES, DESPERDICIOS, ACARREOS, '
      'MANIOBRAS, MANO DE OBRA ESPECIALIZADA Y TODO LO NECESARIO PARA SU '
      'CORRECTA EJECUCION.';

  static Future<String> _ensureDefaultClosure(
    ConceptCatalogSnapshot snapshot,
  ) async {
    for (final c in snapshot.closures) {
      if (_norm(c.text) == _norm(_defaultClosureText)) return c.id;
    }

    final client = SupabaseBootstrap.client;
    if (client == null) return _localId('closure');

    final inserted = await client
        .from('concept_closures')
        .insert({'text': _defaultClosureText})
        .select('id')
        .single();
    return inserted['id'] as String;
  }

  // ── Utilities ──────────────────────────────────────────────────────────────

  static String _norm(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static String _localId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}';
}
