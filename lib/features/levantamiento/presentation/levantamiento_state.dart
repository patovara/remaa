import 'package:flutter_riverpod/flutter_riverpod.dart';

class ActiveLevantamientoSession {
  const ActiveLevantamientoSession({
    required this.projectId,
    required this.universeId,
    required this.projectTypeId,
    this.quoteId,
    this.isCompleted = false,
  });

  final String projectId;
  final String universeId;
  final String projectTypeId;
  final String? quoteId;
  final bool isCompleted;

  bool get isActive => !isCompleted;

  ActiveLevantamientoSession copyWith({
    String? projectId,
    String? universeId,
    String? projectTypeId,
    String? quoteId,
    bool? isCompleted,
  }) {
    return ActiveLevantamientoSession(
      projectId: projectId ?? this.projectId,
      universeId: universeId ?? this.universeId,
      projectTypeId: projectTypeId ?? this.projectTypeId,
      quoteId: quoteId ?? this.quoteId,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}

final activeLevantamientoProvider =
    NotifierProvider<ActiveLevantamientoController, ActiveLevantamientoSession?>(
  ActiveLevantamientoController.new,
);

class ActiveLevantamientoController
    extends Notifier<ActiveLevantamientoSession?> {
  @override
  ActiveLevantamientoSession? build() {
    return null;
  }

  void activate({
    required String projectId,
    required String universeId,
    required String projectTypeId,
    String? quoteId,
  }) {
    state = ActiveLevantamientoSession(
      projectId: projectId,
      universeId: universeId,
      projectTypeId: projectTypeId,
      quoteId: quoteId,
      isCompleted: false,
    );
  }

  void attachQuote(String quoteId) {
    final current = state;
    if (current == null) {
      return;
    }
    state = current.copyWith(quoteId: quoteId, isCompleted: false);
  }

  bool canUseUniverse(String universeId) {
    final current = state;
    if (current == null || current.isCompleted) {
      return true;
    }
    return current.universeId == universeId;
  }

  void finish() {
    final current = state;
    if (current == null) {
      return;
    }
    state = current.copyWith(isCompleted: true);
  }

  void clear() {
    state = null;
  }
}
