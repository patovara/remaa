import '../logging/app_logger.dart';

typedef AICompletionAdapter = Future<String> Function({
  required String systemPrompt,
  required String userPrompt,
});

class AIService {
  const AIService({AICompletionAdapter? completionAdapter}) : _completionAdapter = completionAdapter;

  final AICompletionAdapter? _completionAdapter;

  Future<String> ask({
    required String systemPrompt,
    required String userPrompt,
  }) async {
    final cleanedSystemPrompt = systemPrompt.trim();
    final cleanedUserPrompt = userPrompt.trim();

    if (cleanedSystemPrompt.isEmpty) {
      throw const AIServiceException('systemPrompt is required');
    }
    if (cleanedUserPrompt.isEmpty) {
      throw const AIServiceException('userPrompt is required');
    }

    try {
      if (_completionAdapter != null) {
        final output = await _completionAdapter!(
          systemPrompt: cleanedSystemPrompt,
          userPrompt: cleanedUserPrompt,
        );

        if (output.trim().isEmpty) {
          throw const AIServiceException('AI adapter returned an empty response');
        }

        return output.trim();
      }

      // Default simulation path. Replace with real provider integration.
      return _simulateAnswer(
        systemPrompt: cleanedSystemPrompt,
        userPrompt: cleanedUserPrompt,
      );
    } catch (error) {
      AppLogger.error('ai_service_ask_failed', data: <String, Object?>{'error': error.toString()});
      if (error is AIServiceException) rethrow;
      throw AIServiceException('AI request failed: $error');
    }
  }

  String _simulateAnswer({
    required String systemPrompt,
    required String userPrompt,
  }) {
    final userLine = userPrompt.replaceFirst('USER:', '').trim();
    return [
      '[SIMULATED_AI_RESPONSE]',
      'Request: $userLine',
      'Context chars: ${systemPrompt.length}',
      'Status: Ready to connect a real AI provider in AIService._completionAdapter.',
    ].join('\n');
  }
}

class AIServiceException implements Exception {
  const AIServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
