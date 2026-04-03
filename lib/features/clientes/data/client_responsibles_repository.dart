import '../../../core/config/supabase_bootstrap.dart';
import '../../../core/utils/client_input_rules.dart';
import '../../../core/logging/app_logger.dart';
import '../presentation/clientes_mock_data.dart';

class ClientResponsiblesRepository {
  static final Map<String, List<ClientResponsibleRecord>> _localStore = {};

  Future<List<ClientResponsibleRecord>> fetchByClientId(String clientId) async {
    if (!_canUseRemote(clientId)) {
      return _fetchLocal(clientId);
    }

    try {
      final rows = await SupabaseBootstrap.client!
          .from('client_responsibles')
          .select('id, role, title, position, full_name, phone, email, contact_notes')
          .eq('client_id', clientId);

      return _sort(
        [
          for (final row in rows)
            _normalizeResponsible(
              ClientResponsibleRecord(
                id: row['id'] as String,
                role: responsibleRoleFromCode(row['role'] as String? ?? 'supervisor'),
                title: row['title'] as String? ?? '',
                position: row['position'] as String? ?? '',
                fullName: row['full_name'] as String? ?? '',
                phone: row['phone'] as String? ?? '',
                email: row['email'] as String? ?? '',
                contactNotes: row['contact_notes'] as String? ?? '',
              ),
            ),
        ],
      );
    } catch (error) {
      AppLogger.error(
        'client_responsibles_fetch_failed',
        data: {'client_id': clientId, 'error': error.toString()},
      );
      rethrow;
    }
  }

  Future<List<ClientResponsibleRecord>> saveResponsible({
    required String clientId,
    required ClientResponsibleRecord record,
  }) async {
    final normalizedRecord = _normalizeResponsible(record);
    if (!_canUseRemote(clientId)) {
      return _saveLocal(clientId: clientId, record: normalizedRecord);
    }

    try {
      final payload = <String, Object?>{
        'client_id': clientId,
        'role': normalizedRecord.role.code,
        'title': normalizedRecord.title,
        'position': normalizedRecord.position,
        'full_name': normalizedRecord.fullName,
        'phone': normalizedRecord.phone,
        'email': normalizedRecord.email,
        'contact_notes': normalizedRecord.contactNotes,
      };

      if (_isUuid(normalizedRecord.id)) {
        payload['id'] = normalizedRecord.id;
        await SupabaseBootstrap.client!.from('client_responsibles').upsert(payload);
      } else {
        await SupabaseBootstrap.client!.from('client_responsibles').insert(payload);
      }

      return fetchByClientId(clientId);
    } catch (error) {
      AppLogger.error(
        'client_responsibles_save_failed',
        data: {'client_id': clientId, 'responsible_id': normalizedRecord.id, 'error': error.toString()},
      );
      rethrow;
    }
  }

  Future<List<ClientResponsibleRecord>> deleteResponsible({
    required String clientId,
    required ClientResponsibleRecord record,
  }) async {
    if (!_canUseRemote(clientId) || !_isUuid(record.id)) {
      return _deleteLocal(clientId: clientId, recordId: record.id);
    }

    try {
      await SupabaseBootstrap.client!.from('client_responsibles').delete().eq('id', record.id);
      return fetchByClientId(clientId);
    } catch (error) {
      AppLogger.error(
        'client_responsibles_delete_failed',
        data: {'client_id': clientId, 'responsible_id': record.id, 'error': error.toString()},
      );
      rethrow;
    }
  }

  List<ClientResponsibleRecord> _fetchLocal(String clientId) {
    final items = _localStore[clientId] ?? const <ClientResponsibleRecord>[];
    return _sort([for (final item in items) _normalizeResponsible(item)]);
  }

  List<ClientResponsibleRecord> _saveLocal({
    required String clientId,
    required ClientResponsibleRecord record,
  }) {
    final current = _fetchLocal(clientId);
    final next = [
      for (final item in current)
        if (item.id != record.id && item.role != record.role) item,
      _normalizeResponsible(record),
    ];
    _localStore[clientId] = _sort(next);
    return _fetchLocal(clientId);
  }

  ClientResponsibleRecord _normalizeResponsible(ClientResponsibleRecord record) {
    return record.copyWith(
      position: ClientInputRules.sanitizeTextOnly(record.position),
      fullName: ClientInputRules.sanitizeTextOnly(record.fullName),
      phone: ClientInputRules.digitsOnly(record.phone),
      email: ClientInputRules.normalizeEmail(record.email),
      contactNotes: record.contactNotes.trim(),
    );
  }

  List<ClientResponsibleRecord> _deleteLocal({
    required String clientId,
    required String recordId,
  }) {
    final current = _fetchLocal(clientId);
    _localStore[clientId] = [
      for (final item in current)
        if (item.id != recordId) item,
    ];
    return _fetchLocal(clientId);
  }

  bool _canUseRemote(String clientId) => SupabaseBootstrap.client != null && _isUuid(clientId);

  bool _isUuid(String value) {
    final uuidPattern = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    );
    return uuidPattern.hasMatch(value);
  }

  List<ClientResponsibleRecord> _sort(List<ClientResponsibleRecord> items) {
    items.sort((left, right) => left.role.index.compareTo(right.role.index));
    return items;
  }
}