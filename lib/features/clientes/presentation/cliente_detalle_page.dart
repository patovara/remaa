import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../core/config/supabase_bootstrap.dart';
import '../../../core/theme/rema_colors.dart';
import '../../../core/utils/client_input_rules.dart';
import '../../../core/utils/rema_feedback.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/rema_panels.dart';
import '../data/client_metadata_repository.dart';
import 'client_responsibles_controller.dart';
import 'clientes_mock_data.dart';
import '../../cotizaciones/domain/quote_models.dart';
import '../../cotizaciones/presentation/quotes_controller.dart';

class ClienteDetallePage extends ConsumerStatefulWidget {
  const ClienteDetallePage({super.key, required this.clientId});

  final String clientId;

  @override
  ConsumerState<ClienteDetallePage> createState() => _ClienteDetallePageState();
}

class _ClienteDetallePageState extends ConsumerState<ClienteDetallePage> {
  final _metadataRepository = ClientMetadataRepository();
  ClientRecord? _resolvedClient;
  late final Future<ClientRecord?> _clientFuture = _resolveClient();
  ClientRecord? _editedClient;
  bool _isClientSummaryEditing = false;
  bool _isEditingResponsibles = false;

  bool _isUuid(String value) {
    final uuidPattern = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    );
    return uuidPattern.hasMatch(value);
  }

  Future<ClientRecord?> _resolveClient() async {
    final local = findClientById(widget.clientId);
    if (local != null) {
      _resolvedClient = local;
      return local;
    }

    if (!_isUuid(widget.clientId) || SupabaseBootstrap.client == null) {
      return null;
    }

    try {
      final row = await SupabaseBootstrap.client!
          .from('clients')
          .select('id, business_name, contact_name, notes, rfc, email, phone, address_line, city, sector_label, logo_path, is_hidden')
          .eq('id', widget.clientId)
          .maybeSingle();

      if (row == null) {
        return null;
      }

      final businessName = (row['business_name'] as String? ?? '').trim();
      if (businessName.isEmpty) {
        return null;
      }

      final addressLine = (row['address_line'] as String? ?? '').trim();
      final city = (row['city'] as String? ?? '').trim();
      final fullAddress = [
        if (addressLine.isNotEmpty) addressLine,
        if (city.isNotEmpty) city,
      ].join(', ');
      final contactName = _metadataRepository.resolveContactName(
        contactName: row['contact_name'] as String?,
        notes: row['notes'] as String?,
      );
      final rawSector = (row['sector_label'] as String? ?? '').trim();
      final logoPath = (row['logo_path'] as String? ?? '').trim();
      final logoBytes = await _metadataRepository.downloadLogo(logoPath);

      final remote = ClientRecord(
        id: row['id'] as String? ?? widget.clientId,
        name: businessName,
        contactName: contactName,
        rfc: (row['rfc'] as String? ?? '').trim().isEmpty ? null : (row['rfc'] as String? ?? '').trim(),
        sector: rawSector.isEmpty ? 'SIN SECTOR' : _metadataRepository.normalizeSectorLabel(rawSector),
        badge: 'Activo',
        activeProjects: '00',
        months: '--',
        icon: Icons.apartment,
        contactEmail: (row['email'] as String? ?? 'sin-correo@cliente.com').trim(),
        phone: (row['phone'] as String? ?? 'Sin telefono').trim(),
        address: fullAddress.isEmpty ? 'Sin direccion registrada' : fullAddress,
        responsibles: const [],
        logoPath: logoPath.isEmpty ? null : logoPath,
        logoBytes: logoBytes,
        isHidden: row['is_hidden'] as bool? ?? false,
      );
      _resolvedClient = remote;
      return remote;
    } catch (_) {
      return null;
    }
  }

  List<ClientResponsibleRecord> _sorted(List<ClientResponsibleRecord> input) {
    final items = [...input];
    items.sort((left, right) => left.role.index.compareTo(right.role.index));
    return items;
  }

  _ClientQuoteCounters _buildQuoteCounters({
    required String clientId,
    required AsyncValue<List<QuoteRecord>> quotesAsync,
    required AsyncValue<List<ProjectLookup>> projectsAsync,
  }) {
    if (quotesAsync.valueOrNull == null || projectsAsync.valueOrNull == null) {
      return const _ClientQuoteCounters.loading();
    }

    final projectIds = projectsAsync.valueOrNull!
        .where((project) => project.clientId == clientId)
        .map((project) => project.id)
        .toSet();
    final clientQuotes = quotesAsync.valueOrNull!
        .where((quote) => projectIds.contains(quote.projectId))
        .toList();

    final payableQuotes = clientQuotes.where((quote) => quote.isActaFinalizada).length;
    final concludedQuotes = clientQuotes.where((quote) => quote.isConcluded).length;
    final approvedQuotes = clientQuotes.where((quote) => quote.isApproved).length;

    return _ClientQuoteCounters(
      payableQuotes: payableQuotes,
      concludedQuotes: concludedQuotes,
      approvedQuotes: approvedQuotes,
    );
  }

  List<ClientResponsibleRecord> get _currentResponsibles {
    final currentState = ref.read(clientResponsiblesProvider(widget.clientId));
    return _sorted(currentState.valueOrNull ?? _resolvedClient?.responsibles ?? const []);
  }

  Future<void> _addResponsible() async {
    if (_isClientSummaryEditing) {
      _showMessage(
        ScaffoldMessenger.of(context),
        'Guarda o cancela la edicion de la ficha del cliente antes de modificar responsables.',
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final responsibles = _currentResponsibles;
    setState(() => _isEditingResponsibles = true);
    final created = await showDialog<ClientResponsibleRecord>(
      context: context,
      builder: (context) => ResponsibleEditorDialog(
        takenRoles: responsibles.map((item) => item.role).toSet(),
      ),
    );
    if (mounted) {
      setState(() => _isEditingResponsibles = false);
    }

    if (!mounted || created == null) {
      return;
    }

    try {
      await ref.read(clientResponsiblesProvider(widget.clientId).notifier).save(created);
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showMessage(messenger, 'No fue posible guardar el responsable.');
      return;
    }

    _showMessage(messenger, 'Responsable ${created.role.label.toLowerCase()} agregado.');
  }

  Future<void> _editResponsible(ClientResponsibleRecord responsible) async {
    if (_isClientSummaryEditing) {
      _showMessage(
        ScaffoldMessenger.of(context),
        'Guarda o cancela la edicion de la ficha del cliente antes de modificar responsables.',
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final responsibles = _currentResponsibles;
    setState(() => _isEditingResponsibles = true);
    final updated = await showDialog<ClientResponsibleRecord>(
      context: context,
      builder: (context) => ResponsibleEditorDialog(
        initialValue: responsible,
        takenRoles: responsibles
            .where((item) => item.id != responsible.id)
            .map((item) => item.role)
            .toSet(),
      ),
    );
    if (mounted) {
      setState(() => _isEditingResponsibles = false);
    }

    if (!mounted || updated == null) {
      return;
    }

    try {
      await ref.read(clientResponsiblesProvider(widget.clientId).notifier).save(updated);
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showMessage(messenger, 'No fue posible actualizar el responsable.');
      return;
    }

    _showMessage(messenger, 'Responsable ${updated.role.label.toLowerCase()} actualizado.');
  }

  Future<void> _deleteResponsible(ClientResponsibleRecord responsible) async {
    if (_isClientSummaryEditing) {
      _showMessage(
        ScaffoldMessenger.of(context),
        'Guarda o cancela la edicion de la ficha del cliente antes de modificar responsables.',
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isEditingResponsibles = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar responsable'),
        content: Text(
          'Se quitara a ${responsible.fullName} del expediente de cliente. Puedes volver a capturarlo despues.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (mounted) {
      setState(() => _isEditingResponsibles = false);
    }

    if (!mounted || confirmed != true) {
      return;
    }

    try {
      await ref.read(clientResponsiblesProvider(widget.clientId).notifier).remove(responsible);
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showMessage(messenger, 'No fue posible eliminar el responsable.');
      return;
    }

    _showMessage(messenger, 'Responsable ${responsible.role.label.toLowerCase()} eliminado.');
  }

  void _showMessage(ScaffoldMessengerState messenger, String message) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final responsiblesState = ref.watch(clientResponsiblesProvider(widget.clientId));
    final quotesAsync = ref.watch(quotesProvider);
    final projectsAsync = ref.watch(quoteProjectsProvider);
    return FutureBuilder<ClientRecord?>(
      future: _clientFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const PageFrame(
            title: 'Cargando cliente',
            subtitle: 'Obteniendo informacion del expediente...',
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final client = snapshot.data;
        if (client == null) {
          return PageFrame(
            title: 'Cliente no encontrado',
            subtitle: 'El expediente solicitado no existe en este prototipo.',
            trailing: TextButton.icon(
              onPressed: () => context.go('/clientes'),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Volver'),
            ),
            child: const RemaPanel(
              child: Text('Revisa el listado de clientes y vuelve a abrir el expediente desde ahi.'),
            ),
          );
        }

        return PageFrame(
          title: (_editedClient ?? client).name,
          subtitle: 'Expediente del cliente y administracion de responsables para firmas.',
          trailing: TextButton.icon(
            onPressed: () => context.go('/clientes'),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Clientes'),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 1080;
              final effectiveClient = _editedClient ?? client;
              final quoteCounters = _buildQuoteCounters(
                clientId: widget.clientId,
                quotesAsync: quotesAsync,
                projectsAsync: projectsAsync,
              );
              final responsibleItemsFinal = _sorted(responsiblesState.valueOrNull ?? effectiveClient.responsibles);
              final summary = _ClientSummaryPanel(
                client: effectiveClient,
                quoteCounters: quoteCounters,
                onClientUpdated: (updated) => setState(() => _editedClient = updated),
                metadataRepository: _metadataRepository,
                isResponsiblesEditing: _isEditingResponsibles,
                onEditingChanged: (value) => setState(() => _isClientSummaryEditing = value),
              );
              final responsiblesPanel = _ResponsiblesPanel(
                responsibles: responsibleItemsFinal,
                isLoading: responsiblesState.isLoading && !responsiblesState.hasValue,
                canAddMore: responsibleItemsFinal.length < ResponsibleRole.values.length,
                isClientEditing: _isClientSummaryEditing,
                onAdd: _addResponsible,
                onEdit: _editResponsible,
                onDelete: _deleteResponsible,
                onRetry: () => ref.read(clientResponsiblesProvider(widget.clientId).notifier).reload(),
                hasError: responsiblesState.hasError && !responsiblesState.hasValue,
              );

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Column(
                        children: [
                          summary,
                          const SizedBox(height: 24),
                          _ClientQuotesPanel(
                            clientId: widget.clientId,
                            onCreateQuote: () => context.go('/cotizaciones?clientId=${widget.clientId}&new=1'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(flex: 7, child: responsiblesPanel),
                  ],
                );
              }

              return Column(
                children: [
                  summary,
                  const SizedBox(height: 20),
                  responsiblesPanel,
                  const SizedBox(height: 20),
                  _ClientQuotesPanel(
                    clientId: widget.clientId,
                    onCreateQuote: () => context.go('/cotizaciones?clientId=${widget.clientId}&new=1'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _ClientSummaryPanel extends StatefulWidget {
  const _ClientSummaryPanel({
    required this.client,
    required this.quoteCounters,
    required this.onClientUpdated,
    required this.metadataRepository,
    required this.onEditingChanged,
    required this.isResponsiblesEditing,
  });

  final ClientRecord client;
  final _ClientQuoteCounters quoteCounters;
  final ValueChanged<ClientRecord> onClientUpdated;
  final ClientMetadataRepository metadataRepository;
  final ValueChanged<bool> onEditingChanged;
  final bool isResponsiblesEditing;

  @override
  State<_ClientSummaryPanel> createState() => _ClientSummaryPanelState();
}

class _ClientSummaryPanelState extends State<_ClientSummaryPanel> {
  bool _isEditing = false;
  bool _isSaving = false;
  bool _isUpdatingVisibility = false;
  String? _nameError;
  String? _contactNameError;
  String? _rfcError;
  String? _emailError;
  String? _phoneError;
  String? _addressError;
  String? _sectorError;
  List<String> _sectorLabels = ClientMetadataRepository.defaultSectorLabels;
  String? _selectedSector;
  Uint8List? _logoBytes;
  String? _logoName;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _contactNameCtrl;
  late final TextEditingController _rfcCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;

  String? _normalizeSectorSelection(String? value) {
    final normalized = widget.metadataRepository.normalizeSectorLabel(value ?? '');
    if (normalized.isEmpty || normalized == 'SIN SECTOR') {
      return null;
    }
    return normalized;
  }

  List<String> _buildSectorLabels(List<String> labels, [String? preferred]) {
    final normalized = <String>{
      for (final label in labels)
        widget.metadataRepository.normalizeSectorLabel(label),
    }..removeWhere((label) => label.isEmpty || label == 'SIN SECTOR');

    final selected = _normalizeSectorSelection(preferred);
    if (selected != null) {
      normalized.add(selected);
    }

    final result = normalized.toList()..sort();
    return result;
  }

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.client.name);
    _contactNameCtrl = TextEditingController(text: widget.client.contactName ?? '');
    _rfcCtrl = TextEditingController(text: widget.client.rfc ?? '');
    _emailCtrl = TextEditingController(text: widget.client.contactEmail);
    _phoneCtrl = TextEditingController(text: _phoneForEditing(widget.client.phone));
    _addressCtrl = TextEditingController(text: widget.client.address);
    _selectedSector = _normalizeSectorSelection(widget.client.sector);
    _logoBytes = widget.client.logoBytes;
    _loadSectorLabels();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onEditingChanged(_isEditing);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _ClientSummaryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      _nameCtrl.text = widget.client.name;
      _contactNameCtrl.text = widget.client.contactName ?? '';
      _rfcCtrl.text = widget.client.rfc ?? '';
      _emailCtrl.text = widget.client.contactEmail;
      _phoneCtrl.text = _phoneForEditing(widget.client.phone);
      _addressCtrl.text = widget.client.address;
      _selectedSector = _normalizeSectorSelection(widget.client.sector);
      _sectorLabels = _buildSectorLabels(_sectorLabels, _selectedSector);
      _logoBytes = widget.client.logoBytes;
      _logoName = null;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contactNameCtrl.dispose();
    _rfcCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  static final _uuidRe = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  /// Devuelve los 10 dígitos locales quitando el prefijo +52 / 52 si existe.
  static String _phoneForEditing(String stored) {
    final digits = ClientInputRules.digitsOnly(stored);
    if (digits.length == 12 && digits.startsWith('52')) return digits.substring(2);
    if (digits.length == 10) return digits;
    return digits;
  }

  Future<void> _loadSectorLabels() async {
    final labels = await widget.metadataRepository.fetchSectorLabels();
    if (!mounted) {
      return;
    }
    setState(() {
      _sectorLabels = _buildSectorLabels(labels, _selectedSector ?? widget.client.sector);
      final normalizedClientSector = _normalizeSectorSelection(widget.client.sector);
      if (_selectedSector != null && !_sectorLabels.contains(_selectedSector)) {
        _selectedSector = null;
      }
      _selectedSector ??= normalizedClientSector;
    });
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
    );
    if (!mounted || result == null || result.files.isEmpty) {
      return;
    }

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      return;
    }

    setState(() {
      _logoBytes = bytes;
      _logoName = file.name;
    });
  }

  Future<void> _addSector() async {
    final controller = TextEditingController();
    final created = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuevo sector'),
        content: TextField(
          controller: controller,
          autofocus: true,
          inputFormatters: const [_UpperCaseTextFormatter()],
          decoration: const InputDecoration(hintText: 'Ejemplo: INDUSTRIAL'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controller.dispose();

    final normalized = widget.metadataRepository.normalizeSectorLabel(created ?? '');
    if (normalized.isEmpty) {
      return;
    }

    await widget.metadataRepository.ensureSectorLabel(normalized);
    if (!mounted) {
      return;
    }
    setState(() {
      _sectorLabels = _buildSectorLabels(_sectorLabels, normalized);
      _selectedSector = normalized;
    });
  }

  bool _validateInputs() {
    final businessName = _nameCtrl.text.trim();
    final contactName = _contactNameCtrl.text.trim();
    final phoneDigits = ClientInputRules.digitsOnly(_phoneCtrl.text);
    final email = ClientInputRules.normalizeEmail(_emailCtrl.text);
    final address = _addressCtrl.text.trim();
    final rfc = _rfcCtrl.text.trim().toUpperCase();
    final sector = widget.metadataRepository.normalizeSectorLabel(_selectedSector ?? '');

    String? nameError;
    String? contactNameError;
    String? rfcError;
    String? emailError;
    String? phoneError;
    String? addressError;
    String? sectorError;

    if (businessName.length < ClientInputRules.minTextLength) {
      nameError = 'La razon social debe tener al menos ${ClientInputRules.minTextLength} caracteres.';
    } else if (businessName.length > ClientInputRules.maxTextLength) {
      nameError = 'La razon social no puede superar ${ClientInputRules.maxTextLength} caracteres.';
    }

    if (contactName.isNotEmpty && !ClientInputRules.isValidTextOnly(contactName)) {
      contactNameError = ClientInputRules.textOnlyErrorMessage(fieldLabel: 'nombre de contacto');
    }

    if (!ClientInputRules.isValidRfc(rfc)) {
      rfcError = ClientInputRules.rfcErrorMessage();
    }

    if (!ClientInputRules.isValidTenDigitPhone(phoneDigits)) {
      phoneError = ClientInputRules.phoneTenDigitsErrorMessage();
    }

    if (!ClientInputRules.isValidEmail(email)) {
      emailError = ClientInputRules.emailErrorMessage(fieldLabel: 'correo principal');
    }

    if (address.isNotEmpty && !ClientInputRules.isValidAddress(address)) {
      addressError = ClientInputRules.addressErrorMessage();
    } else if (address.isEmpty) {
      addressError = 'Ingresa la direccion del cliente.';
    }

    if (sector.isEmpty) {
      sectorError = 'Selecciona un sector para el cliente.';
    }

    setState(() {
      _nameError = nameError;
      _contactNameError = contactNameError;
      _rfcError = rfcError;
      _emailError = emailError;
      _phoneError = phoneError;
      _addressError = addressError;
      _sectorError = sectorError;
    });

    return nameError == null &&
      contactNameError == null &&
      rfcError == null &&
      emailError == null &&
      phoneError == null &&
      addressError == null &&
      sectorError == null;
  }

  Future<void> _save() async {
    if (!_validateInputs()) {
      return;
    }

    final businessName = _nameCtrl.text.trim().toUpperCase();
    final contactName = ClientInputRules.sanitizeTextOnly(_contactNameCtrl.text);
    final rfc = _rfcCtrl.text.trim().toUpperCase();
    final phoneDigits = ClientInputRules.digitsOnly(_phoneCtrl.text);
    final phoneE164 = ClientInputRules.toE164Mx(phoneDigits) ?? phoneDigits;
    final email = ClientInputRules.normalizeEmail(_emailCtrl.text);
    final address = _addressCtrl.text.trim();
    final sector = widget.metadataRepository.normalizeSectorLabel(_selectedSector ?? '');

    setState(() => _isSaving = true);
    try {
      String? logoPath = widget.client.logoPath;
      if (_logoBytes != null && _logoName != null && _uuidRe.hasMatch(widget.client.id)) {
        logoPath = await widget.metadataRepository.uploadLogo(
          clientId: widget.client.id,
          bytes: _logoBytes!,
          fileName: _logoName!,
        );
      }

      final updated = ClientRecord(
        id: widget.client.id,
        name: businessName,
        contactName: contactName.isEmpty ? null : contactName,
        rfc: rfc.isEmpty ? null : rfc,
        sector: sector,
        badge: widget.client.badge,
        activeProjects: widget.client.activeProjects,
        months: widget.client.months,
        icon: widget.client.icon,
        contactEmail: email,
        phone: phoneE164,
        address: address,
        responsibles: widget.client.responsibles,
        logoPath: logoPath,
        logoBytes: _logoBytes,
        isHidden: widget.client.isHidden,
      );
      if (_uuidRe.hasMatch(widget.client.id) && SupabaseBootstrap.client != null) {
        await widget.metadataRepository.ensureSectorLabel(sector);
        await widget.metadataRepository.updateClientMetadata(
          clientId: updated.id,
          businessName: updated.name,
          contactName: updated.contactName,
          email: updated.contactEmail,
          phone: updated.phone,
          address: updated.address,
          sectorLabel: updated.sector,
          rfc: updated.rfc,
          logoPath: updated.logoPath,
          logoMimeType: _logoName == null ? null : widget.metadataRepository.logoMimeTypeFromFileName(_logoName!),
        );
      }
      widget.onClientUpdated(updated);
      if (mounted) {
        showRemaMessage(
          context,
          'Cliente actualizado correctamente.',
          duration: const Duration(milliseconds: 800),
        );
        setState(() {
          _logoName = null;
          _isEditing = false;
        });
        widget.onEditingChanged(false);
      }
    } catch (error) {
      final dbMsg = ClientInputRules.mapDbError(error.toString());
      if (mounted && dbMsg != null) {
        showRemaMessage(context, dbMsg);
      }
      // keep editing on error
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _toggleHidden() async {
    if (!_uuidRe.hasMatch(widget.client.id) || _isUpdatingVisibility) {
      return;
    }

    final nextHidden = !widget.client.isHidden;
    setState(() => _isUpdatingVisibility = true);
    try {
      await widget.metadataRepository.updateClientVisibility(
        clientId: widget.client.id,
        isHidden: nextHidden,
      );
      widget.onClientUpdated(widget.client.copyWith(isHidden: nextHidden));
      if (!mounted) {
        return;
      }
      showRemaMessage(context, nextHidden ? 'Cliente ocultado.' : 'Cliente restaurado.');
    } catch (_) {
      if (mounted) {
        showRemaMessage(context, 'No fue posible actualizar la visibilidad del cliente.');
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdatingVisibility = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    return Column(
      children: [
        RemaPanel(
          backgroundColor: RemaColors.primaryDark,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 72,
                height: 72,
                color: Colors.white.withValues(alpha: 0.08),
                alignment: Alignment.center,
                child: client.logoBytes != null && client.logoBytes!.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.memory(
                          client.logoBytes!,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                        ),
                      )
                    : Icon(client.icon, color: Colors.white, size: 32),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      client.badge.toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.72),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      client.name,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      client.sector,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        RemaPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RemaSectionHeader(
                title: 'Ficha del cliente',
                icon: Icons.badge_outlined,
                trailing: _isEditing
                    ? null
                    : Wrap(
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: _uuidRe.hasMatch(client.id) && !_isUpdatingVisibility ? _toggleHidden : null,
                            icon: _isUpdatingVisibility
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Icon(client.isHidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                            label: Text(client.isHidden ? 'Restaurar' : 'Ocultar'),
                          ),
                          TextButton.icon(
                            onPressed: widget.isResponsiblesEditing
                                ? null
                                : () {
                                    setState(() => _isEditing = true);
                                    widget.onEditingChanged(true);
                                  },
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: const Text('Editar'),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 24),
              if (_isEditing) ...[
                _EditableLogoCard(
                  logoBytes: _logoBytes,
                  logoName: _logoName,
                  fallbackIcon: client.icon,
                  onPickLogo: _pickLogo,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameCtrl,
                  onChanged: (_) {
                    if (_nameError != null) {
                      setState(() => _nameError = null);
                    }
                  },
                  inputFormatters: const [_UpperCaseTextFormatter()],
                  decoration: InputDecoration(
                    labelText: 'Razon social',
                    errorText: _nameError,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _contactNameCtrl,
                  onChanged: (_) {
                    if (_contactNameError != null) {
                      setState(() => _contactNameError = null);
                    }
                  },
                  inputFormatters: const [_UpperCaseTextFormatter()],
                  decoration: InputDecoration(
                    labelText: 'Nombre de contacto',
                    errorText: _contactNameError,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _rfcCtrl,
                  onChanged: (_) {
                    if (_rfcError != null) {
                      setState(() => _rfcError = null);
                    }
                  },
                  inputFormatters: const [_UpperCaseTextFormatter()],
                  decoration: InputDecoration(
                    labelText: 'RFC',
                    errorText: _rfcError,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailCtrl,
                  onChanged: (_) {
                    if (_emailError != null) {
                      setState(() => _emailError = null);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'Correo principal',
                    errorText: _emailError,
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _phoneCtrl,
                  onChanged: (_) {
                    if (_phoneError != null) {
                      setState(() => _phoneError = null);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'Telefono',
                    errorText: _phoneError,
                  ),
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 680;
                    final sectorField = DropdownButtonFormField<String>(
                      value: _selectedSector,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Sector',
                        errorText: _sectorError,
                      ),
                      items: [
                        for (final sector in _sectorLabels)
                          DropdownMenuItem<String>(
                            value: sector,
                            child: Text(
                              sector,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedSector = value;
                          _sectorError = null;
                        });
                      },
                    );

                    if (compact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          sectorField,
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _addSector,
                            icon: const Icon(Icons.add),
                            label: const Text('Nuevo sector'),
                          ),
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: sectorField),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: _addSector,
                          icon: const Icon(Icons.add),
                          label: const Text('Nuevo sector'),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _addressCtrl,
                  onChanged: (_) {
                    if (_addressError != null) {
                      setState(() => _addressError = null);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'Direccion',
                    errorText: _addressError,
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isSaving
                          ? null
                          : () {
                              _nameCtrl.text = widget.client.name;
                              _contactNameCtrl.text = widget.client.contactName ?? '';
                              _rfcCtrl.text = widget.client.rfc ?? '';
                              _emailCtrl.text = widget.client.contactEmail;
                              _phoneCtrl.text = _phoneForEditing(widget.client.phone);
                              _addressCtrl.text = widget.client.address;
                              setState(() {
                                _selectedSector = _normalizeSectorSelection(widget.client.sector);
                                _sectorLabels = _buildSectorLabels(_sectorLabels, _selectedSector);
                                _logoBytes = widget.client.logoBytes;
                                _logoName = null;
                                _nameError = null;
                                _contactNameError = null;
                                _emailError = null;
                                _phoneError = null;
                                _addressError = null;
                                _sectorError = null;
                                _isEditing = false;
                              });
                              widget.onEditingChanged(false);
                            },
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _isSaving ? null : _save,
                      child: _isSaving
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                SizedBox(width: 8),
                                Text('Guardando...'),
                              ],
                            )
                          : const Text('Guardar'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ] else ...[
                _SummaryRow(label: 'Razon social', value: client.name),
                const SizedBox(height: 16),
                _SummaryRow(
                  label: 'Nombre de contacto',
                  value: client.displayContactName.isEmpty ? 'Sin contacto principal' : client.displayContactName,
                ),
                const SizedBox(height: 16),
                _SummaryRow(
                  label: 'RFC',
                  value: (client.rfc == null || client.rfc!.trim().isEmpty) ? 'Sin RFC' : client.rfc!,
                ),
                const SizedBox(height: 16),
                _SummaryRow(label: 'Sector', value: client.sector),
                const SizedBox(height: 16),
                _SummaryRow(label: 'Estado', value: client.isHidden ? 'Oculto' : 'Visible'),
                const SizedBox(height: 16),
                _SummaryRow(label: 'Correo principal', value: client.contactEmail),
                const SizedBox(height: 16),
                _SummaryRow(label: 'Telefono', value: client.phone),
                const SizedBox(height: 16),
                _SummaryRow(label: 'Direccion', value: client.address),
                const SizedBox(height: 16),
              ],
              Row(
                children: [
                  Expanded(
                    child: _SummaryMetric(
                      label: 'Cotizaciones por pagar',
                      value: widget.quoteCounters.displayPayableQuotes,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _SummaryMetric(
                      label: 'Cotizaciones concluidas',
                      value: widget.quoteCounters.displayConcludedQuotes,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _SummaryMetric(
                      label: 'Cotizaciones aprobadas',
                      value: widget.quoteCounters.displayApprovedQuotes,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResponsiblesPanel extends StatelessWidget {
  const _ResponsiblesPanel({
    required this.responsibles,
    required this.isLoading,
    required this.hasError,
    required this.canAddMore,
    required this.isClientEditing,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onRetry,
  });

  final List<ClientResponsibleRecord> responsibles;
  final bool isLoading;
  final bool hasError;
  final bool canAddMore;
  final bool isClientEditing;
  final VoidCallback onAdd;
  final ValueChanged<ClientResponsibleRecord> onEdit;
  final ValueChanged<ClientResponsibleRecord> onDelete;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return RemaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RemaSectionHeader(
            title: 'Responsables',
            icon: Icons.how_to_reg_outlined,
            trailing: FilledButton.icon(
              onPressed: canAddMore && !isClientEditing ? onAdd : null,
              icon: const Icon(Icons.add),
              label: const Text('Agregar'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isClientEditing
                ? 'La ficha del cliente esta en edicion. Guarda o cancela esos cambios antes de actualizar responsables.'
                : canAddMore
                ? 'Administra supervisor y gerente del cliente. Si Supabase esta configurado, los cambios se sincronizan; si no, la pantalla sigue funcionando en modo local.'
                : 'El expediente ya tiene los dos roles cubiertos. Edita o elimina alguno si necesitas cambiarlo.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: RemaColors.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          if (isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (hasError)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: RemaColors.surfaceLow,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: RemaColors.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('No fue posible cargar los responsables del cliente.'),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                ],
              ),
            )
          else if (responsibles.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: RemaColors.surfaceLow,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: RemaColors.outlineVariant),
              ),
              child: const Text('Aun no hay responsables registrados para este cliente.'),
            )
          else
            for (final responsible in responsibles) ...[
              _ResponsibleCard(
                responsible: responsible,
                isEnabled: !isClientEditing,
                onEdit: () => onEdit(responsible),
                onDelete: () => onDelete(responsible),
              ),
              const SizedBox(height: 16),
            ],
        ],
      ),
    );
  }
}

class _ResponsibleCard extends StatelessWidget {
  const _ResponsibleCard({
    required this.responsible,
    required this.isEnabled,
    required this.onEdit,
    required this.onDelete,
  });

  final ClientResponsibleRecord responsible;
  final bool isEnabled;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: RemaColors.surfaceLow,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: RemaColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: RemaColors.surfaceHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  responsible.role.label.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: isEnabled ? onEdit : null,
                tooltip: 'Editar responsable',
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                onPressed: isEnabled ? onDelete : null,
                tooltip: 'Eliminar responsable',
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '${responsible.title} ${responsible.fullName}'.trim(),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            responsible.position,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: RemaColors.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              _ContactPill(icon: Icons.call_outlined, label: responsible.phone),
              _ContactPill(icon: Icons.mail_outline, label: responsible.email),
            ],
          ),
          if (responsible.contactNotes.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              responsible.contactNotes,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

class _ContactPill extends StatelessWidget {
  const _ContactPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: RemaColors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: RemaColors.primaryDark),
          const SizedBox(width: 10),
          Text(label),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
              ),
        ),
        const SizedBox(height: 6),
        Text(value, style: Theme.of(context).textTheme.bodyLarge),
      ],
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: RemaColors.surfaceLow,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(label),
        ],
      ),
    );
  }
}

class _ClientQuoteCounters {
  const _ClientQuoteCounters({
    required this.payableQuotes,
    required this.concludedQuotes,
    required this.approvedQuotes,
  }) : isLoading = false;

  const _ClientQuoteCounters.loading()
      : payableQuotes = 0,
        concludedQuotes = 0,
        approvedQuotes = 0,
        isLoading = true;

  final int payableQuotes;
  final int concludedQuotes;
  final int approvedQuotes;
  final bool isLoading;

  String get displayPayableQuotes => isLoading ? '--' : payableQuotes.toString().padLeft(2, '0');

  String get displayConcludedQuotes => isLoading ? '--' : concludedQuotes.toString().padLeft(2, '0');

  String get displayApprovedQuotes => isLoading ? '--' : approvedQuotes.toString().padLeft(2, '0');
}

class _EditableLogoCard extends StatelessWidget {
  const _EditableLogoCard({
    required this.logoBytes,
    required this.logoName,
    required this.fallbackIcon,
    required this.onPickLogo,
  });

  final Uint8List? logoBytes;
  final String? logoName;
  final IconData fallbackIcon;
  final VoidCallback onPickLogo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'LOGO DEL CLIENTE',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onPickLogo,
          child: Container(
            width: double.infinity,
            height: 180,
            decoration: BoxDecoration(
              color: RemaColors.surfaceLow,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: RemaColors.outlineVariant),
            ),
            alignment: Alignment.center,
            child: logoBytes != null && logoBytes!.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.memory(
                      logoBytes!,
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(fallbackIcon, size: 42, color: RemaColors.onSurfaceVariant),
                      const SizedBox(height: 10),
                      const Text('Haz clic para actualizar el logo'),
                    ],
                  ),
          ),
        ),
        if (logoName != null) ...[
          const SizedBox(height: 8),
          Text(logoName!, style: Theme.of(context).textTheme.labelMedium),
        ],
      ],
    );
  }
}

class ResponsibleEditorDialog extends StatefulWidget {
  const ResponsibleEditorDialog({super.key, this.initialValue, required this.takenRoles});

  final ClientResponsibleRecord? initialValue;
  final Set<ResponsibleRole> takenRoles;

  @override
  State<ResponsibleEditorDialog> createState() => _ResponsibleEditorDialogState();
}

class _ResponsibleEditorDialogState extends State<ResponsibleEditorDialog> {
  final _formKey = GlobalKey<FormState>();

  late ResponsibleRole _role = widget.initialValue?.role ?? _firstAvailableRole();
  late final TextEditingController _positionController = TextEditingController(
    text: widget.initialValue?.position ?? '',
  );
  late final TextEditingController _fullNameController = TextEditingController(
    text: widget.initialValue?.fullName ?? '',
  );
  late final TextEditingController _phoneController = TextEditingController(
    text: widget.initialValue?.phone ?? '',
  );
  late final TextEditingController _emailController = TextEditingController(
    text: widget.initialValue?.email ?? '',
  );
  late final TextEditingController _notesController = TextEditingController(
    text: widget.initialValue?.contactNotes ?? '',
  );

  ResponsibleRole _firstAvailableRole() {
    for (final role in ResponsibleRole.values) {
      if (!widget.takenRoles.contains(role)) {
        return role;
      }
    }
    return ResponsibleRole.supervisor;
  }

  @override
  void dispose() {
    _positionController.dispose();
    _fullNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _submit() {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      return;
    }

    Navigator.of(context).pop(
      ClientResponsibleRecord(
        id: widget.initialValue?.id ?? '${_role.code}-${DateTime.now().millisecondsSinceEpoch}',
        role: _role,
        title: '',
        position: ClientInputRules.sanitizeTextOnly(_positionController.text),
        fullName: ClientInputRules.sanitizeTextOnly(_fullNameController.text),
        phone: ClientInputRules.digitsOnly(_phoneController.text),
        email: ClientInputRules.normalizeEmail(_emailController.text),
        contactNotes: _notesController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialValue == null ? 'Nuevo responsable' : 'Editar responsable'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<ResponsibleRole>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Rol'),
                  items: [
                    for (final role in ResponsibleRole.values)
                      DropdownMenuItem(
                        value: role,
                        enabled: role == widget.initialValue?.role || !widget.takenRoles.contains(role),
                        child: Text(role.label),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _role = value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _positionController,
                  decoration: const InputDecoration(labelText: 'Puesto'),
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-zÁÉÍÓÚÜÑáéíóúüñ ]')),
                    const _UpperCaseTextFormatter(),
                  ],
                  validator: (value) => _validateTextOnly(
                    value,
                    emptyMessage: 'Ingresa el puesto.',
                    invalidMessage: 'El puesto solo admite letras.',
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _fullNameController,
                  decoration: const InputDecoration(labelText: 'Nombre completo'),
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-zÁÉÍÓÚÜÑáéíóúüñ ]')),
                    const _UpperCaseTextFormatter(),
                  ],
                  validator: (value) => _validateTextOnly(
                    value,
                    emptyMessage: 'Ingresa el nombre completo.',
                    invalidMessage: 'El nombre solo admite letras.',
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(labelText: 'Telefono'),
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (value) => _requiredPhone(value),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Correo electronico'),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) => _requiredEmail(value),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Notas de contacto'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Guardar'),
        ),
      ],
    );
  }

  String? _requiredValue(String? value, String message) {
    if (value == null || value.trim().isEmpty) {
      return message;
    }
    return null;
  }

  String? _validateTextOnly(
    String? value, {
    required String emptyMessage,
    required String invalidMessage,
  }) {
    final raw = value ?? '';
    final normalized = ClientInputRules.sanitizeTextOnly(raw);
    if (normalized.isEmpty) {
      return emptyMessage;
    }
    if (!ClientInputRules.isValidTextOnly(raw)) {
      return invalidMessage;
    }
    return null;
  }

  String? _requiredPhone(String? value) {
    final digits = ClientInputRules.digitsOnly(value ?? '');
    if (digits.isEmpty) {
      return ClientInputRules.phoneRequiredMessage();
    }
    if (!ClientInputRules.isValidTenDigitPhone(digits)) {
      return ClientInputRules.phoneTenDigitsErrorMessage();
    }
    return null;
  }

  String? _requiredEmail(String? value) {
    final email = ClientInputRules.normalizeEmail(value ?? '');
    if (email.isEmpty) {
      return 'Ingresa el correo electronico.';
    }
    if (!ClientInputRules.isValidEmail(email)) {
      return ClientInputRules.emailErrorMessage();
    }
    return null;
  }
}

class _UpperCaseTextFormatter extends TextInputFormatter {
  const _UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final upper = newValue.text.toUpperCase();
    return newValue.copyWith(
      text: upper,
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}

// ─── Client quotes panel ──────────────────────────────────────────────────────

class _ClientQuotesPanel extends ConsumerWidget {
  const _ClientQuotesPanel({required this.clientId, required this.onCreateQuote});

  final String clientId;
  final VoidCallback onCreateQuote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quotesAsync = ref.watch(quotesProvider);
    final projectsAsync = ref.watch(quoteProjectsProvider);

    final projectIds = projectsAsync.valueOrNull
            ?.where((p) => p.clientId == clientId)
            .map((p) => p.id)
            .toSet() ??
        const <String>{};

    final clientQuotes = quotesAsync.valueOrNull
            ?.where((q) => projectIds.contains(q.projectId))
            .toList() ??
        const <QuoteRecord>[];

    return RemaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RemaSectionHeader(
            title: 'Cotizaciones',
            icon: Icons.request_quote_outlined,
            trailing: FilledButton.icon(
              onPressed: onCreateQuote,
              icon: const Icon(Icons.add),
              label: const Text('Nueva'),
            ),
          ),
          const SizedBox(height: 12),
          if (quotesAsync.isLoading || projectsAsync.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (clientQuotes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Sin cotizaciones registradas para este cliente.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: RemaColors.onSurfaceVariant),
              ),
            )
          else
            for (final q in clientQuotes) ...[
              _QuoteRow(quote: q),
              if (q != clientQuotes.last) const Divider(height: 1),
            ],
        ],
      ),
    );
  }
}

class _QuoteRow extends ConsumerWidget {
  const _QuoteRow({required this.quote});

  final QuoteRecord quote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formatter = NumberFormat.currency(symbol: r'$', decimalDigits: 2, locale: 'en_US');
    final canOpenFinalActa = quote.isActaFinalizada || quote.isPaid;

    return ListTile(
      dense: true,
      leading: const Icon(Icons.description_outlined),
      title: Text(quote.quoteNumber),
      subtitle: Text(_statusLabel(quote.status)),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                formatter.format(quote.total),
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (canOpenFinalActa) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Previsualizar acta',
                onPressed: () => _previewFinalActa(context, ref, quote),
                icon: const Icon(Icons.visibility_outlined),
              ),
              IconButton(
                tooltip: 'Descargar acta',
                onPressed: () => _downloadFinalActa(context, ref, quote),
                icon: const Icon(Icons.download_outlined),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<ActaDocumentRecord?> _loadFinalActaDocument(WidgetRef ref, QuoteRecord quote) async {
    return ref.read(quotesRepositoryProvider).fetchActaDocument(quote.id);
  }

  Future<void> _previewFinalActa(BuildContext context, WidgetRef ref, QuoteRecord quote) async {
    final document = await _loadFinalActaDocument(ref, quote);
    if (document == null) {
      if (context.mounted) {
        showRemaMessage(context, 'No hay acta final guardada para esta cotizacion.');
      }
      return;
    }

    await Printing.layoutPdf(onLayout: (_) async => document.bytes, name: document.fileName);
  }

  Future<void> _downloadFinalActa(BuildContext context, WidgetRef ref, QuoteRecord quote) async {
    final document = await _loadFinalActaDocument(ref, quote);
    if (document == null) {
      if (context.mounted) {
        showRemaMessage(context, 'No hay acta final guardada para esta cotizacion.');
      }
      return;
    }

    await Printing.sharePdf(bytes: document.bytes, filename: document.fileName);
    if (context.mounted) {
      showRemaMessage(context, 'Acta final lista para descarga.');
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'concluded':
        return 'Concluida';
      case 'approved':
        return 'Aprobada';
      case 'declined':
        return 'Declinada';
      case 'acta_finalizada':
        return 'Por cobrar';
      case 'paid':
        return 'Pagada';
      default:
        return 'Pendiente';
    }
  }
}