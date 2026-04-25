import '../logging/app_logger.dart';
import 'ai_service.dart';
import 'memory_service.dart';

class AIAgent {
  const AIAgent({
    required MemoryService memoryService,
    required AIService aiService,
  })  : _memoryService = memoryService,
        _aiService = aiService;

  final MemoryService _memoryService;
  final AIService _aiService;

  Future<String> ask(
    String input, {
    bool saveMemory = false,
    Map<String, dynamic>? stateUpdate,
  }) async {
    final trimmedInput = input.trim();
    if (trimmedInput.isEmpty) {
      throw const AIAgentException('input is required');
    }

    try {
      final context = await _memoryService.buildContext(trimmedInput);
      final systemPrompt = (context['system_prompt'] as String? ?? '').trim();
      final userPrompt = (context['user_prompt'] as String? ?? '').trim();

      if (systemPrompt.isEmpty || userPrompt.isEmpty) {
        throw const AIAgentException('Invalid context received from memory service');
      }

      final response = await _aiService.ask(
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
      );

      final persistMemory = saveMemory || shouldSave(trimmedInput);
      if (persistMemory) {
        await _memoryService.updateMemory(
          event: _buildEventFromInput(trimmedInput),
          stateUpdate: stateUpdate,
        );
      }

      return response;
    } catch (error) {
      AppLogger.error('ai_agent_ask_failed', data: <String, Object?>{'error': error.toString()});
      if (error is AIAgentException || error is MemoryServiceException || error is AIServiceException) {
        rethrow;
      }
      throw AIAgentException('Unable to complete AI request: $error');
    }
  }

  bool shouldSave(String input) {
    final normalized = input.toLowerCase();
    final triggers = <RegExp>[
      RegExp(r'\bse\s+implement[oó]\b'),
      RegExp(r'\bimplement[eé]\b'),
      RegExp(r'\bse\s+agreg[oó]\b'),
      RegExp(r'\bagregu[eé]\b'),
      RegExp(r'\bse\s+cre[oó]\b'),
      RegExp(r'\bse\s+integr[oó]\b'),
    ];

    for (final pattern in triggers) {
      if (pattern.hasMatch(normalized)) {
        return true;
      }
    }
    return false;
  }

  String _buildEventFromInput(String input) {
    final trimmed = input.trim();
    final normalized = trimmed.toLowerCase();

    if (normalized.contains('paginacion') && normalized.contains('pdf')) {
      return 'Se agrego paginacion al PDF de cotizaciones';
    }

    if (normalized.startsWith('implementa ') || normalized.startsWith('implementar ')) {
      final remainder = trimmed.replaceFirst(RegExp(r'^(?i)implementa(r)?\s+'), '').trim();
      return remainder.isEmpty ? 'Se implemento un cambio' : 'Se implemento $remainder';
    }

    if (normalized.startsWith('agrega ') || normalized.startsWith('agregar ')) {
      final remainder = trimmed.replaceFirst(RegExp(r'^(?i)agrega(r)?\s+'), '').trim();
      return remainder.isEmpty ? 'Se agrego un cambio' : 'Se agrego $remainder';
    }

    if (normalized.startsWith('crea ') || normalized.startsWith('crear ')) {
      final remainder = trimmed.replaceFirst(RegExp(r'^(?i)crea(r)?\s+'), '').trim();
      return remainder.isEmpty ? 'Se creo un cambio' : 'Se creo $remainder';
    }

    if (normalized.startsWith('integra ') || normalized.startsWith('integrar ')) {
      final remainder = trimmed.replaceFirst(RegExp(r'^(?i)integra(r)?\s+'), '').trim();
      return remainder.isEmpty ? 'Se integro un cambio' : 'Se integro $remainder';
    }

    return 'Cambio realizado: $trimmed';
  }
}

class AIAgentException implements Exception {
  const AIAgentException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<String> exampleAIAgentUsage() async {
  final agent = AIAgent(
    memoryService: const MemoryService(),
    aiService: const AIService(),
  );

  return agent.ask(
    'Agrega paginacion al PDF de cotizaciones',
    saveMemory: true,
  );
}
