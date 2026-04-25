import 'package:supabase_flutter/supabase_flutter.dart';

import '../logging/app_logger.dart';

class MemoryService {
  const MemoryService({this.projectId = 'remaa_app'});

  final String projectId;

  SupabaseClient get _client => Supabase.instance.client;

  Map<String, String> _authHeaders() {
    final accessToken = _client.auth.currentSession?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      return <String, String>{};
    }
    return <String, String>{'Authorization': 'Bearer $accessToken'};
  }

  Future<Map<String, dynamic>> buildContext(String input) async {
    final trimmedInput = input.trim();
    if (trimmedInput.isEmpty) {
      throw const MemoryServiceException('input is required');
    }

    try {
      final response = await _client.functions.invoke(
        'buildMemoryContext',
        headers: _authHeaders(),
        body: <String, dynamic>{
          'project_id': projectId,
          'user_input': trimmedInput,
        },
      );

      final data = response.data;
      if (response.status >= 400) {
        final message = _extractErrorMessage(data) ?? 'buildMemoryContext failed';
        throw MemoryServiceException(message);
      }

      if (data is! Map<String, dynamic>) {
        throw const MemoryServiceException('Invalid buildMemoryContext response format');
      }

      final systemPrompt = (data['system_prompt'] as String? ?? '').trim();
      final userPrompt = (data['user_prompt'] as String? ?? '').trim();
      if (systemPrompt.isEmpty || userPrompt.isEmpty) {
        throw const MemoryServiceException('Missing system_prompt or user_prompt');
      }

      return data;
    } catch (error) {
      AppLogger.error('memory_build_context_failed', data: <String, Object?>{'error': error.toString()});
      if (error is MemoryServiceException) rethrow;
      throw MemoryServiceException('Unable to build memory context: $error');
    }
  }

  Future<void> updateMemory({
    required String event,
    Map<String, dynamic>? stateUpdate,
  }) async {
    final trimmedEvent = event.trim();
    if (trimmedEvent.isEmpty) {
      throw const MemoryServiceException('event is required');
    }

    try {
      final response = await _client.functions.invoke(
        'updateMemory',
        headers: _authHeaders(),
        body: <String, dynamic>{
          'project_id': projectId,
          'new_event': trimmedEvent,
          if (stateUpdate != null && stateUpdate.isNotEmpty) 'optional_state_update': stateUpdate,
        },
      );

      final data = response.data;
      if (response.status >= 400) {
        final message = _extractErrorMessage(data) ?? 'updateMemory failed';
        throw MemoryServiceException(message);
      }

      if (data is! Map<String, dynamic> || data['success'] != true) {
        throw const MemoryServiceException('Invalid updateMemory response');
      }
    } catch (error) {
      AppLogger.error('memory_update_failed', data: <String, Object?>{'error': error.toString()});
      if (error is MemoryServiceException) rethrow;
      throw MemoryServiceException('Unable to update memory: $error');
    }
  }

  String? _extractErrorMessage(dynamic data) {
    if (data is Map<String, dynamic>) {
      final error = data['error']?.toString().trim();
      if (error != null && error.isNotEmpty) {
        return error;
      }
    }
    return null;
  }
}

class MemoryServiceException implements Exception {
  const MemoryServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
