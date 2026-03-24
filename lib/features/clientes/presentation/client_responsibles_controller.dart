import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/client_responsibles_repository.dart';
import 'clientes_mock_data.dart';

final clientResponsiblesRepositoryProvider = Provider<ClientResponsiblesRepository>(
  (ref) => ClientResponsiblesRepository(),
);

final clientResponsiblesProvider = AsyncNotifierProvider.family<
    ClientResponsiblesController,
    List<ClientResponsibleRecord>,
    String>(ClientResponsiblesController.new);

class ClientResponsiblesController extends FamilyAsyncNotifier<List<ClientResponsibleRecord>, String> {
  late final ClientResponsiblesRepository _repository = ref.read(clientResponsiblesRepositoryProvider);
  late String _clientId;

  @override
  FutureOr<List<ClientResponsibleRecord>> build(String arg) async {
    _clientId = arg;
    return _repository.fetchByClientId(arg);
  }

  Future<void> save(ClientResponsibleRecord record) async {
    final previous = state.valueOrNull ?? const <ClientResponsibleRecord>[];
    final next = await AsyncValue.guard(
      () => _repository.saveResponsible(clientId: _clientId, record: record),
    );

    if (next.hasError) {
      state = AsyncData(previous);
      Error.throwWithStackTrace(next.error!, next.stackTrace!);
    }

    state = next;
  }

  Future<void> remove(ClientResponsibleRecord record) async {
    final previous = state.valueOrNull ?? const <ClientResponsibleRecord>[];
    final next = await AsyncValue.guard(
      () => _repository.deleteResponsible(clientId: _clientId, record: record),
    );

    if (next.hasError) {
      state = AsyncData(previous);
      Error.throwWithStackTrace(next.error!, next.stackTrace!);
    }

    state = next;
  }

  Future<void> reload() async {
    state = await AsyncValue.guard(() => _repository.fetchByClientId(_clientId));
  }
}