import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/config/supabase_bootstrap.dart';
import '../../../core/config/company_profile.dart';
import '../../../core/auth/admin_access.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/theme/rema_colors.dart';
import '../../../core/utils/image_optimizer.dart';
import '../../../core/utils/rema_feedback.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/rema_panels.dart';
import '../../clientes/data/client_responsibles_repository.dart';
import '../../clientes/presentation/clientes_mock_data.dart';
import '../../cotizaciones/data/quotes_repository.dart';
import '../../cotizaciones/domain/quote_models.dart';
import '../../cotizaciones/presentation/quotes_controller.dart';
import '../../levantamiento/presentation/levantamiento_state.dart';

Future<Uint8List> _buildActaPdfBytesInBackground(Map<String, Object?> payload) async {
  final pdf = pw.Document();
  final logoBytes = payload['logoBytes'] as Uint8List?;
  final watermarkBytes = payload['watermarkBytes'] as Uint8List?;
  final logo = logoBytes != null && logoBytes.isNotEmpty ? pw.MemoryImage(logoBytes) : null;
  final watermark =
      watermarkBytes != null && watermarkBytes.isNotEmpty ? pw.MemoryImage(watermarkBytes) : null;

  final ingresoBytes = payload['ingresoBytes'] as Uint8List?;
  final antesBytes = payload['antesBytes'] as Uint8List?;
  final despuesBytes = payload['despuesBytes'] as Uint8List?;
  final duranteBytes = (payload['duranteBytes'] as List?)?.cast<Uint8List>() ?? const <Uint8List>[];

  final ingresoImage = ingresoBytes != null && ingresoBytes.isNotEmpty ? pw.MemoryImage(ingresoBytes) : null;
  final antesImage = antesBytes != null && antesBytes.isNotEmpty ? pw.MemoryImage(antesBytes) : null;
  final despuesImage = despuesBytes != null && despuesBytes.isNotEmpty ? pw.MemoryImage(despuesBytes) : null;
  final duranteImages = [
    for (final bytes in duranteBytes)
      if (bytes.isNotEmpty) pw.MemoryImage(bytes),
  ];

  final renderedActa = payload['renderedActa'] as String? ?? '';
  final gerenteNombre = payload['gerenteNombre'] as String? ?? '{nombre_del_gerente_del_cliente}';
  final gerentePuesto = payload['gerentePuesto'] as String? ?? '{nombre_del_puesto_del_gerente_del_cliente}';
  final responsableNombre = payload['responsableNombre'] as String? ?? '{nombre_del_responsable_del_cliente}';
  final responsablePuesto = payload['responsablePuesto'] as String? ?? '{nombre_del_puesto_del_responsable_del_cliente}';
  final brandName = payload['brandName'] as String? ?? CompanyProfile.brandName;
  final legalName = payload['legalName'] as String? ?? CompanyProfile.legalName;

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(36),
      build: (context) {
        return pw.Stack(
          children: [
            if (watermark != null)
              pw.Positioned.fill(
                child: pw.Center(
                  child: pw.Opacity(
                    opacity: 0.10,
                    child: pw.Image(
                      watermark,
                      width: 380,
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                ),
              ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildPdfHeader(logo: logo, brandName: brandName, legalName: legalName),
                pw.SizedBox(height: 16),
                pw.Text(renderedActa, style: const pw.TextStyle(fontSize: 11)),
                pw.Spacer(),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildSignatureBlock(gerenteNombre, gerentePuesto),
                    _buildSignatureBlock(responsableNombre, responsablePuesto),
                    _buildSignatureBlock('ING. MIGUEL VAZQUEZ', 'GRUPO REMAA'),
                  ],
                ),
                pw.SizedBox(height: 16),
                _buildPageFooter(1),
              ],
            ),
          ],
        );
      },
    ),
  );

  pdf.addPage(
    _buildPhotoPage(
      logo: logo,
      brandName: brandName,
      legalName: legalName,
      title: 'REPORTE FOTOGRAFICO - INGRESO A INSTALACIONES',
      image: ingresoImage,
      page: 2,
    ),
  );
  pdf.addPage(
    _buildPhotoPage(
      logo: logo,
      brandName: brandName,
      legalName: legalName,
      title: 'REPORTE FOTOGRAFICO - ANTES',
      image: antesImage,
      page: 3,
    ),
  );

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(36),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildPdfHeader(logo: logo, brandName: brandName, legalName: legalName),
            pw.SizedBox(height: 20),
            pw.Text(
              'REPORTE FOTOGRAFICO - DURANTE',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
            ),
            pw.SizedBox(height: 12),
            pw.Wrap(
              alignment: pw.WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final image in duranteImages)
                  pw.Container(
                    width: 240,
                    height: 140,
                    alignment: pw.Alignment.center,
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300)),
                    child: pw.Image(image, fit: pw.BoxFit.contain),
                  ),
                if (duranteImages.isEmpty)
                  pw.Container(
                    width: 240,
                    height: 140,
                    alignment: pw.Alignment.center,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                      color: PdfColors.grey100,
                    ),
                    child: pw.Text('Sin evidencia cargada'),
                  ),
              ],
            ),
            pw.Spacer(),
            _buildPageFooter(4),
          ],
        );
      },
    ),
  );

  pdf.addPage(
    _buildPhotoPage(
      logo: logo,
      brandName: brandName,
      legalName: legalName,
      title: 'REPORTE FOTOGRAFICO - DESPUÉS',
      image: despuesImage,
      page: 5,
    ),
  );

  return pdf.save();
}

pw.Widget _buildPdfHeader({
  required pw.MemoryImage? logo,
  required String brandName,
  required String legalName,
}) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 92,
            height: 46,
            alignment: pw.Alignment.centerLeft,
            child: logo != null
                ? pw.Image(logo, fit: pw.BoxFit.contain)
                : pw.Text(
                    brandName,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
                  ),
          ),
          pw.Spacer(),
          pw.SizedBox(
            width: 280,
            child: pw.Text(
              legalName,
              textAlign: pw.TextAlign.right,
              style: const pw.TextStyle(fontSize: 9),
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 8),
      pw.Center(
        child: pw.Text(
          'ACTA ENTREGA - RECEPCIÓN',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
        ),
      ),
    ],
  );
}

pw.Widget _buildPageFooter(int page) {
  return pw.Align(
    alignment: pw.Alignment.centerRight,
    child: pw.Text('Pagina $page de 5', style: const pw.TextStyle(fontSize: 9)),
  );
}

pw.Page _buildPhotoPage({
  required pw.MemoryImage? logo,
  required String brandName,
  required String legalName,
  required String title,
  required pw.MemoryImage? image,
  required int page,
}) {
  return pw.Page(
    pageFormat: PdfPageFormat.letter,
    margin: const pw.EdgeInsets.all(36),
    build: (context) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _buildPdfHeader(logo: logo, brandName: brandName, legalName: legalName),
          pw.SizedBox(height: 20),
          _buildPhotoSection(title, image),
          pw.Spacer(),
          _buildPageFooter(page),
        ],
      );
    },
  );
}

pw.Widget _buildPhotoSection(String title, pw.MemoryImage? image) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 6),
      pw.Container(
        width: double.infinity,
        height: 380,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          color: PdfColors.grey100,
        ),
        child: image != null
            ? pw.Image(image, fit: pw.BoxFit.contain)
            : pw.Center(child: pw.Text('Sin evidencia cargada')),
      ),
    ],
  );
}

pw.Widget _buildSignatureBlock(String title, String subtitle) {
  return pw.Container(
    width: 165,
    padding: const pw.EdgeInsets.only(top: 18),
    decoration: const pw.BoxDecoration(
      border: pw.Border(top: pw.BorderSide(color: PdfColors.black)),
    ),
    child: pw.Column(
      children: [
        pw.Text(
          title,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          subtitle,
          textAlign: pw.TextAlign.center,
          style: const pw.TextStyle(fontSize: 8),
        ),
      ],
    ),
  );
}

class ActasPage extends ConsumerStatefulWidget {
  const ActasPage({super.key, this.clientId, this.quoteId});

  final String? clientId;
  final String? quoteId;

  @override
  ConsumerState<ActasPage> createState() => _ActasPageState();
}

class _ActasPageState extends ConsumerState<ActasPage> {
  final _formatter = DateFormat('dd/MM/yyyy');
  final _responsiblesRepository = ClientResponsiblesRepository();
  final _quotesRepository = QuotesRepository();
  static final RegExp _textOnlyPattern = RegExp(r'^[A-ZÁÉÍÓÚÜÑ ]+$');
  static final RegExp _hour24Pattern = RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$');

  final _clienteController = TextEditingController();
  final _razonSocialController = TextEditingController();
  final _direccionController = TextEditingController();
  final _ubicacionController = TextEditingController();
  final _horaEstablecidaController = TextEditingController();
  final _servicioController = TextEditingController();
  final _gerenteClienteController = TextEditingController();
  final _puestoGerenteController = TextEditingController();
  final _responsableController = TextEditingController();
  final _puestoResponsableController = TextEditingController();

  final _fechaInicioController = TextEditingController();
  final _fechaConclusionController = TextEditingController();
  final _numeroPedidoController = TextEditingController();
  final _fechaAprobacionPedidoController = TextEditingController();
  final _actaTemplateController = TextEditingController(text: _defaultActaTemplate);

  int _step = 0;

  _PickedMedia? _fotoIngreso;
  _PickedMedia? _fotoAntes;
  _PickedMedia? _fotoDespues;
  final List<_PickedMedia> _fotosDurante = [];

  ClientRecord? _loadedClient;
  bool _isLoadingClient = false;
  bool _isGeneratingPdf = false;
  double _pdfProgressValue = 0;
  Timer? _pdfProgressTimer;
  String? _pdfGenerationMessage;
  String? _missingResponsiblesError;
  bool _actaFinalizada = false;
  bool _isProcessingSinglePhoto = false;
  String? _processingSingleStage;
  bool _isProcessingDurantePhotos = false;

  bool get _isAdmin => ref.read(isAdminProvider);

  @override
  void initState() {
    super.initState();
    _refreshClientData(showFeedback: false);
    if (widget.quoteId != null && widget.quoteId!.isNotEmpty) {
      _loadServiceDescriptionFromQuote(widget.quoteId!);
      _checkActaStatus(widget.quoteId!);
    }
    // Cargar automáticamente evidencia del levantamiento o desde registros persistidos
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadEvidenceForActa();
    });
  }

  Future<void> _loadServiceDescriptionFromQuote(String quoteId) async {
    try {
      final items = await _quotesRepository.fetchItemsByQuoteId(quoteId);

      final firstConcept = items
          .map((item) => item.concept.trim())
          .firstWhere((concept) => concept.isNotEmpty, orElse: () => '');

      if (!mounted || firstConcept.isEmpty) {
        return;
      }

      setState(() {
        _servicioController.text = _normalizeServiceDescriptionForActa(firstConcept);
      });
    } catch (error) {
      AppLogger.error(
        'actas_load_service_description_failed',
        data: {'quoteId': quoteId, 'error': error.toString()},
      );
    }
  }

  String _normalizeServiceDescriptionForActa(String rawConcept) {
    final normalized = rawConcept.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      return '';
    }

    // Remueve notas comerciales/operativas que suelen iniciar con "incluye".
    final lower = normalized.toLowerCase();
    final includesMatch = RegExp(r'\bincluye\b').firstMatch(lower);
    if (includesMatch != null) {
      return normalized.substring(0, includesMatch.start).trim();
    }

    const marker = 'superficie preparada';
    final markerIndex = lower.indexOf(marker);
    if (markerIndex >= 0) {
      final cut = markerIndex + marker.length;
      return normalized.substring(0, cut).trim();
    }

    return normalized;
  }

  Future<void> _checkActaStatus(String quoteId) async {
    final client = SupabaseBootstrap.client;
    if (client == null || !_isUuid(quoteId)) return;
    try {
      final row = await client
          .from('quotes')
          .select('status')
          .eq('id', quoteId)
          .single();
      final status = row['status'] as String? ?? '';
      if (mounted && (status == QuoteStatus.actaFinalizada || status == QuoteStatus.paid)) {
        setState(() => _actaFinalizada = true);
      }
    } catch (_) {}
  }

  Future<void> _loadEvidenceForActa() async {
    final loadedFromActive = _loadEvidenceFromActiveLevantamiento();
    if (loadedFromActive) {
      return;
    }
    await _loadEvidenceFromPersistedSurveyEntries();
  }

  bool _loadEvidenceFromActiveLevantamiento() {
    final activeLevantamiento = ref.read(activeLevantamientoProvider);
    if (activeLevantamiento == null) {
      return false;
    }

    final evidenceList = <Uint8List>[
      ...activeLevantamiento.evidencePreviewList,
      for (final entry in activeLevantamiento.entries)
        for (final bytes in entry.evidencePreviewList)
          if (bytes.isNotEmpty) bytes,
    ];
    if (evidenceList.isEmpty) {
      return false;
    }

    if (!mounted) {
      return false;
    }

    _applyEvidenceImages(evidenceList);

    if (mounted && evidenceList.isNotEmpty) {
      showRemaMessage(
        context,
        'Se cargaron ${evidenceList.length} imagen(es) del levantamiento automaticamente.',
      );
    }
    return true;
  }

  Future<void> _loadEvidenceFromPersistedSurveyEntries() async {
    final quoteId = widget.quoteId?.trim();
    final client = SupabaseBootstrap.client;
    if (quoteId == null || quoteId.isEmpty || client == null || !_isUuid(quoteId)) {
      return;
    }

    try {
      final quoteRow = await client
          .from('quotes')
          .select('project_id')
          .eq('id', quoteId)
          .maybeSingle();
      final projectId = (quoteRow?['project_id'] as String? ?? '').trim();
      if (projectId.isEmpty || !_isUuid(projectId)) {
        return;
      }

      final rows = await client
          .from('project_survey_entries')
          .select('evidence_paths, evidence_meta, created_at')
          .eq('project_id', projectId)
          .order('created_at', ascending: true);

      final objectPaths = <String>[];
      for (final row in rows) {
        final evidenceMetaDynamic = row['evidence_meta'];
        if (evidenceMetaDynamic is List) {
          for (final item in evidenceMetaDynamic) {
            if (item is Map<String, dynamic>) {
              final path = (item['object_path'] as String? ?? '').trim();
              if (path.isNotEmpty) {
                objectPaths.add(path);
              }
            }
          }
        }

        if (objectPaths.isEmpty) {
          final evidencePathsDynamic = row['evidence_paths'];
          if (evidencePathsDynamic is List) {
            for (final item in evidencePathsDynamic) {
              if (item is String && item.trim().isNotEmpty) {
                objectPaths.add(item.trim());
              }
            }
          }
        }
      }

      if (objectPaths.isEmpty) {
        return;
      }

      final downloaded = await Future.wait(
        objectPaths.map((path) async {
          try {
            final bytes = await client.storage.from('survey-photos').download(path);
            return bytes.isEmpty ? null : bytes;
          } catch (_) {
            return null;
          }
        }),
      );
      final evidenceList = [for (final bytes in downloaded) ?bytes];
      if (evidenceList.isEmpty || !mounted) {
        return;
      }

      _applyEvidenceImages(evidenceList);
      showRemaMessage(
        context,
        'Se cargaron ${evidenceList.length} imagen(es) del levantamiento desde la base.',
      );
    } catch (error) {
      AppLogger.error(
        'actas_load_persisted_evidence_failed',
        data: {'quoteId': quoteId, 'error': error.toString()},
      );
    }
  }

  void _applyEvidenceImages(List<Uint8List> evidenceList) {
    if (!mounted || evidenceList.isEmpty) {
      return;
    }

    setState(() {
      _fotoAntes ??= _PickedMedia(
          name: 'antes_${DateTime.now().millisecondsSinceEpoch}.png',
          bytes: evidenceList.first,
          size: evidenceList.first.length,
        );

      if (_fotosDurante.isEmpty && evidenceList.length > 1) {
        for (var index = 1; index < evidenceList.length; index++) {
          _fotosDurante.add(
            _PickedMedia(
              name: 'durante_${index}_${DateTime.now().millisecondsSinceEpoch}.png',
              bytes: evidenceList[index],
              size: evidenceList[index].length,
            ),
          );
        }
      }
    });
  }

  Future<void> _finalizeActa() async {
    if (widget.quoteId == null) return;
    if (!_validateForFinalization()) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar Acta'),
        content: const Text(
          '¿Confirmas que el acta ha sido entregada y la cotización queda pendiente de pago?\n\n'
          'Esta acción marcará la cotización como "Acta finalizada / Pago pendiente".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final bytes = await _runPdfGeneration(
        message: 'Tu documento se esta generando, te notificaremos cuando este listo.',
        task: _buildPdfBytes,
        estimatedDuration: const Duration(seconds: 8),
      );
      final order = _numeroPedidoController.text.trim().isEmpty
          ? widget.quoteId!
          : _numeroPedidoController.text.trim().replaceAll(' ', '_');
      final savedInSupabase = await ref.read(quotesRepositoryProvider).saveActaDocument(
            quoteId: widget.quoteId!,
            bytes: bytes,
            fileName: 'acta_entrega_$order.pdf',
            photos: _buildActaPhotoInputs(),
          );
      await ref.read(quotesProvider.notifier).updateStatus(
            quoteId: widget.quoteId!,
            status: QuoteStatus.actaFinalizada,
          );
      if (!mounted) return;
      setState(() => _actaFinalizada = true);
      showRemaMessage(
        context,
        savedInSupabase
        ? 'Acta finalizada y guardada en Supabase. La cotizacion queda por cobrar.'
        : 'Acta finalizada y guardada localmente. La cotizacion queda por cobrar.',
      );
      context.go('/cotizaciones');
    } catch (error) {
      if (!mounted) return;
      AppLogger.error('actas_finalize_failed',
          data: {'quoteId': widget.quoteId, 'error': error.toString()});
      showRemaMessage(context, 'Error al finalizar acta: $error');
    }
  }

  Future<void> _loadClientData(String clientId) async {
    setState(() => _isLoadingClient = true);
    try {
      final client = SupabaseBootstrap.client;
      if (client == null || !_isUuid(clientId)) {
        return;
      }
      await _loadSupabaseClient(clientId);
    } catch (error) {
      if (mounted) {
        showRemaMessage(context, 'No se pudo cargar el cliente: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingClient = false);
      }
    }
  }

  Future<void> _refreshClientData({bool showFeedback = true}) async {
    final clientId = await _resolveClientId();
    if (clientId == null || clientId.isEmpty) {
      if (mounted && showFeedback) {
        showRemaMessage(context, 'No se pudo identificar el cliente para actualizar datos del acta.');
      }
      return;
    }
    await _loadClientData(clientId);
    if (mounted && showFeedback) {
      showRemaMessage(context, 'Datos del cliente actualizados.');
    }
  }

  Future<String?> _resolveClientId() async {
    final directClientId = widget.clientId?.trim();
    if (directClientId != null && directClientId.isNotEmpty) {
      return directClientId;
    }

    final activeLevantamiento = ref.read(activeLevantamientoProvider);
    final activeClientId = activeLevantamiento?.clientId?.trim();
    if (activeClientId != null && activeClientId.isNotEmpty) {
      return activeClientId;
    }

    final quoteId = widget.quoteId?.trim();
    final client = SupabaseBootstrap.client;
    if (quoteId == null || quoteId.isEmpty || client == null || !_isUuid(quoteId)) {
      return null;
    }

    try {
      final quoteRow = await client.from('quotes').select('project_id').eq('id', quoteId).single();
      final projectId = quoteRow['project_id'] as String?;
      if (projectId == null || projectId.isEmpty || !_isUuid(projectId)) {
        return null;
      }
      final projectRow = await client.from('projects').select('client_id').eq('id', projectId).single();
      final clientId = projectRow['client_id'] as String?;
      return clientId?.trim();
    } catch (error) {
      AppLogger.error(
        'actas_resolve_client_failed',
        data: {'quoteId': quoteId, 'error': error.toString()},
      );
      return null;
    }
  }

  Future<void> _loadSupabaseClient(String clientId) async {
    final client = SupabaseBootstrap.client;
    if (client == null) return;

    try {
      final row = await client
          .from('clients')
          .select('id, business_name, contact_name, city, state, address_line')
          .eq('id', clientId)
          .single();

        final businessName = (row['business_name'] as String? ?? '').trim();
        final contactName = (row['contact_name'] as String? ?? '').trim();
        final clientNameForActa = contactName.isNotEmpty ? contactName : businessName;
      final address = row['address_line'] as String? ?? '';
      final city = row['city'] as String? ?? '';
      final state = row['state'] as String? ?? '';
      final location = [city, state].where((v) => v.isNotEmpty).join(', ');
      final responsibles = await _responsiblesRepository.fetchByClientId(clientId);

      if (mounted) {
        setState(() {
          _loadedClient = ClientRecord(
            id: clientId,
            name: businessName,
            contactName: contactName,
            sector: '',
            badge: '',
            activeProjects: '',
            months: '',
            icon: Icons.business,
            contactEmail: '',
            phone: '',
            address: address,
            responsibles: responsibles,
          );
          _clienteController.text = clientNameForActa;
          _razonSocialController.text = businessName;
          _direccionController.text = address;
          _ubicacionController.text = location;
          _applyResponsiblesToActa(responsibles);
        });
      }
    } catch (e) {
      AppLogger.error('actas_load_client_failed', data: {'clientId': clientId, 'error': e.toString()});
    }
  }

  void _loadClientIntoControllers(ClientRecord client) {
    setState(() {
      _loadedClient = client;
      final contactName = (client.contactName ?? '').trim();
      _clienteController.text = contactName.isNotEmpty ? contactName : client.name;
      _razonSocialController.text = client.name;
      _direccionController.text = client.address;
      _ubicacionController.text = client.address;
      _applyResponsiblesToActa(client.responsibles);
    });
  }

  void _applyResponsiblesToActa(List<ClientResponsibleRecord> responsibles) {
    final supervisor = responsibles
        .where((item) => item.role == ResponsibleRole.supervisor)
        .cast<ClientResponsibleRecord?>()
        .firstWhere((item) => item != null, orElse: () => null);
    final gerente = responsibles
        .where((item) => item.role == ResponsibleRole.gerente)
        .cast<ClientResponsibleRecord?>()
        .firstWhere((item) => item != null, orElse: () => null);

    if (responsibles.length < 2 || supervisor == null || gerente == null) {
      _missingResponsiblesError =
          'No se encontraron ambos responsables guardados para este cliente. Puedes capturarlos manualmente o actualizar datos.';
    } else {
      _missingResponsiblesError = null;
    }

    if (supervisor != null) {
      _responsableController.text = _sanitizeTextOnly(supervisor.fullName);
      _puestoResponsableController.text = _sanitizeTextOnly(supervisor.position);
    }

    if (gerente != null) {
      _gerenteClienteController.text = _sanitizeTextOnly(gerente.fullName);
      _puestoGerenteController.text = _sanitizeTextOnly(gerente.position);
    }
  }

  String _sanitizeTextOnly(String value) {
    final collapsed = value
        .replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return collapsed.toUpperCase();
  }

  bool _isUuid(String value) {
    final uuidPattern = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    );
    return uuidPattern.hasMatch(value);
  }

  @override
  void dispose() {
    _pdfProgressTimer?.cancel();
    _clienteController.dispose();
    _razonSocialController.dispose();
    _direccionController.dispose();
    _ubicacionController.dispose();
    _horaEstablecidaController.dispose();
    _servicioController.dispose();
    _gerenteClienteController.dispose();
    _puestoGerenteController.dispose();
    _responsableController.dispose();
    _puestoResponsableController.dispose();
    _fechaInicioController.dispose();
    _fechaConclusionController.dispose();
    _numeroPedidoController.dispose();
    _fechaAprobacionPedidoController.dispose();
    _actaTemplateController.dispose();
    super.dispose();
  }

  Future<void> _pickSinglePhoto({
    required String stage,
    required void Function(_PickedMedia?) setTarget,
  }) async {
    setState(() {
      _isProcessingSinglePhoto = true;
      _processingSingleStage = stage;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );

      if (!mounted || result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        showRemaMessage(context, 'No se pudo leer la imagen seleccionada.');
        return;
      }
      OptimizedImageResult optimized;
      try {
        optimized = await optimizeImageForDocument(
          inputBytes: bytes,
          fileName: file.name,
          profile: ImageOptimizationProfile.mainDocument,
        );
      } on ImageOptimizationException catch (error) {
        if (mounted) {
          showRemaMessage(context, error.message);
        }
        return;
      }

      setState(() {
        setTarget(
          _PickedMedia(
            name: optimized.fileName,
            bytes: optimized.bytes,
            size: optimized.bytes.length,
            mimeType: optimized.mimeType,
          ),
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingSinglePhoto = false;
          _processingSingleStage = null;
        });
      }
    }
  }

  Future<void> _pickMultipleDurante() async {
    setState(() => _isProcessingDurantePhotos = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: true,
      );

      if (!mounted || result == null || result.files.isEmpty) {
        return;
      }

      final optimizedMedia = <_PickedMedia>[];
      final rejectedMessages = <String>[];
      for (final file in result.files.where((item) => item.bytes != null)) {
        try {
          final optimized = await optimizeImageForDocument(
            inputBytes: file.bytes!,
            fileName: file.name,
            profile: ImageOptimizationProfile.gridDocument,
          );
          optimizedMedia.add(
            _PickedMedia(
              name: optimized.fileName,
              bytes: optimized.bytes,
              size: optimized.bytes.length,
              mimeType: optimized.mimeType,
            ),
          );
        } on ImageOptimizationException catch (error) {
          rejectedMessages.add('${file.name}: ${error.message}');
        }
      }

      if (!mounted) {
        return;
      }

      if (optimizedMedia.isNotEmpty) {
        setState(() {
          _fotosDurante.addAll(optimizedMedia);
        });
      }

      if (optimizedMedia.isNotEmpty && rejectedMessages.isEmpty) {
        showRemaMessage(context, 'Se agregaron ${optimizedMedia.length} fotos optimizadas de avance.');
        return;
      }
      if (optimizedMedia.isNotEmpty && rejectedMessages.isNotEmpty) {
        showRemaMessage(
          context,
          'Se agregaron ${optimizedMedia.length} fotos optimizadas. ${rejectedMessages.first}',
        );
        return;
      }
      if (rejectedMessages.isNotEmpty) {
        showRemaMessage(context, rejectedMessages.first);
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingDurantePhotos = false);
      }
    }
  }

  void _startPdfProgressSimulation(Duration estimatedDuration) {
    _pdfProgressTimer?.cancel();
    _pdfProgressValue = 0;
    const tick = Duration(milliseconds: 120);
    final totalTicks =
        (estimatedDuration.inMilliseconds / tick.inMilliseconds).clamp(1, 100000).round();
    var currentTick = 0;
    _pdfProgressTimer = Timer.periodic(tick, (_) {
      if (!mounted) {
        return;
      }
      currentTick += 1;
      final progress = (currentTick / totalTicks) * 0.90;
      setState(() => _pdfProgressValue = progress.clamp(0.0, 0.90));
    });
  }

  Future<void> _selectDate(TextEditingController controller) async {
    try {
      final firstDate = _pickerFirstDateFor(controller);
      final lastDate = _pickerLastDateFor(controller);
      if (lastDate.isBefore(firstDate)) {
        showRemaMessage(context, 'Primero captura una fecha compatible para continuar.');
        return;
      }

      final selected = await showDatePicker(
        context: context,
        initialDate: _pickerInitialDateFor(
          controller: controller,
          firstDate: firstDate,
          lastDate: lastDate,
        ),
        firstDate: firstDate,
        lastDate: lastDate,
      );

      if (selected == null) {
        return;
      }

      final previousValue = controller.text;
      final nextValue = _formatter.format(selected);

      setState(() {
        controller.text = nextValue;
      });

      final dateErrors = _collectDateValidationErrors();
      if (dateErrors.isNotEmpty) {
        setState(() {
          controller.text = previousValue;
        });
        if (mounted) {
          showRemaMessage(context, dateErrors.first);
        }
      }
    } catch (e) {
      // Fallback si el DatePicker falla
      if (!mounted) {
        return;
      }
      showRemaMessage(context, 'Ingresa la fecha en formato DD/MM/YYYY');
    }
  }

  bool _validateForPdf() {
    final errors = _collectValidationErrors();
    if (errors.isNotEmpty) {
      showRemaMessage(
        context,
        'Faltan o son invalidos estos campos: ${errors.join(', ')}.',
      );
      return false;
    }
    return true;
  }

  bool _validateForFinalization() {
    final errors = _collectValidationErrors();
    if (errors.isNotEmpty) {
      showRemaMessage(
        context,
        'No se puede finalizar el acta. Revisa: ${errors.join(', ')}.',
      );
      return false;
    }
    return true;
  }

  List<String> _collectValidationErrors() {
    final missing = <String>[];

    if (_clienteController.text.trim().isEmpty) {
      missing.add('Cliente');
    }
    if (_razonSocialController.text.trim().isEmpty) {
      missing.add('Razon social');
    }
    if (_direccionController.text.trim().isEmpty) {
      missing.add('Direccion');
    }
    if (_ubicacionController.text.trim().isEmpty) {
      missing.add('Ubicacion');
    }
    if (_servicioController.text.trim().isEmpty) {
      missing.add('Descripcion del servicio');
    }
    if (_responsableController.text.trim().isEmpty) {
      missing.add('Supervisor del cliente');
    } else if (!_textOnlyPattern.hasMatch(_responsableController.text.trim())) {
      missing.add('Supervisor del cliente solo texto');
    }
    if (_puestoResponsableController.text.trim().isEmpty) {
      missing.add('Puesto del supervisor');
    } else if (!_textOnlyPattern.hasMatch(_puestoResponsableController.text.trim())) {
      missing.add('Puesto del supervisor solo texto');
    }
    if (_gerenteClienteController.text.trim().isEmpty) {
      missing.add('Gerente del cliente');
    } else if (!_textOnlyPattern.hasMatch(_gerenteClienteController.text.trim())) {
      missing.add('Gerente del cliente solo texto');
    }
    if (_puestoGerenteController.text.trim().isEmpty) {
      missing.add('Puesto del gerente');
    } else if (!_textOnlyPattern.hasMatch(_puestoGerenteController.text.trim())) {
      missing.add('Puesto del gerente solo texto');
    }
    if (_horaEstablecidaController.text.trim().isEmpty) {
      missing.add('Hora establecida por usuario');
    } else if (!_hour24Pattern.hasMatch(_horaEstablecidaController.text.trim())) {
      missing.add('Hora en formato 24 hrs');
    }

    if (_fechaInicioController.text.trim().isEmpty) {
      missing.add('Fecha de inicio');
    }
    if (_fechaConclusionController.text.trim().isEmpty) {
      missing.add('Fecha de conclusion');
    }
    if (_numeroPedidoController.text.trim().isEmpty) {
      missing.add('Numero de pedido');
    }
    if (_fechaAprobacionPedidoController.text.trim().isEmpty) {
      missing.add('Fecha de aprobacion del pedido');
    }

    missing.addAll(_collectDateValidationErrors());

    if (_fotoIngreso == null && _fotoAntes == null && _fotoDespues == null && _fotosDurante.isEmpty) {
      missing.add('Registro fotografico');
    }

    return missing;
  }

  List<String> _collectDateValidationErrors() {
    final errors = <String>[];
    final fechaInicio = _tryParseDate(_fechaInicioController.text);
    final fechaConclusion = _tryParseDate(_fechaConclusionController.text);
    final fechaAprobacion = _tryParseDate(_fechaAprobacionPedidoController.text);

    if (_fechaInicioController.text.trim().isNotEmpty && fechaInicio == null) {
      errors.add('Fecha de inicio invalida');
    }
    if (_fechaConclusionController.text.trim().isNotEmpty && fechaConclusion == null) {
      errors.add('Fecha de conclusion invalida');
    }
    if (_fechaAprobacionPedidoController.text.trim().isNotEmpty && fechaAprobacion == null) {
      errors.add('Fecha de aprobacion del pedido invalida');
    }

    if (fechaInicio != null && fechaConclusion != null && fechaConclusion.isBefore(fechaInicio)) {
      errors.add('La fecha de conclusion no puede ser menor que la fecha de inicio');
    }

    if (fechaAprobacion != null && fechaConclusion != null && !fechaAprobacion.isBefore(fechaConclusion)) {
      errors.add('La fecha de aprobacion del pedido debe ser anterior a la fecha de conclusion');
    }

    return errors;
  }

  DateTime? _tryParseDate(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      final parsed = _formatter.parseStrict(trimmed);
      return DateTime(parsed.year, parsed.month, parsed.day);
    } catch (_) {
      return null;
    }
  }

  DateTime _pickerFirstDateFor(TextEditingController controller) {
    if (identical(controller, _fechaConclusionController)) {
      return _tryParseDate(_fechaInicioController.text) ?? DateTime(2020);
    }
    return DateTime(2020);
  }

  DateTime _pickerLastDateFor(TextEditingController controller) {
    if (identical(controller, _fechaAprobacionPedidoController)) {
      final conclusion = _tryParseDate(_fechaConclusionController.text);
      if (conclusion != null) {
        return conclusion.subtract(const Duration(days: 1));
      }
    }
    return DateTime(2040);
  }

  DateTime _pickerInitialDateFor({
    required TextEditingController controller,
    required DateTime firstDate,
    required DateTime lastDate,
  }) {
    final parsed = _tryParseDate(controller.text) ?? DateTime.now();
    if (parsed.isBefore(firstDate)) {
      return firstDate;
    }
    if (parsed.isAfter(lastDate)) {
      return lastDate;
    }
    return parsed;
  }

  List<ActaPhotoAssetInput> _buildActaPhotoInputs() {
    final photos = <ActaPhotoAssetInput>[];

    void addPhoto(String slot, _PickedMedia? media) {
      if (media == null || media.bytes.isEmpty) {
        return;
      }
      photos.add(
        ActaPhotoAssetInput(
          slot: slot,
          fileName: media.name,
          bytes: media.bytes,
          fileSizeBytes: media.size,
          mimeType: media.mimeType ?? _guessMimeType(media.name),
        ),
      );
    }

    addPhoto('ingreso', _fotoIngreso);
    addPhoto('antes', _fotoAntes);
    addPhoto('despues', _fotoDespues);

    for (var index = 0; index < _fotosDurante.length; index++) {
      addPhoto('durante_${index + 1}', _fotosDurante[index]);
    }

    return photos;
  }

  String _guessMimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    return 'image/jpeg';
  }

  Future<Uint8List> _buildPdfBytes() async {
    final logoBytes = await _loadAssetBytes('assets/images/logo_remaa.png');
    final watermarkBytes = await _loadAssetBytes('assets/images/marca_agua_remaa.png');

    return compute(
      _buildActaPdfBytesInBackground,
      <String, Object?>{
        'logoBytes': logoBytes,
        'watermarkBytes': watermarkBytes,
        'ingresoBytes': _fotoIngreso?.bytes,
        'antesBytes': _fotoAntes?.bytes,
        'despuesBytes': _fotoDespues?.bytes,
        'duranteBytes': [for (final media in _fotosDurante.take(4)) media.bytes],
        'renderedActa': _renderTemplate(_actaTemplateController.text, _templateValues),
        'gerenteNombre': _gerenteClienteController.text.trim().isEmpty
            ? '{nombre_del_gerente_del_cliente}'
            : _gerenteClienteController.text.trim(),
        'gerentePuesto': _puestoGerenteController.text.trim().isEmpty
            ? '{nombre_del_puesto_del_gerente_del_cliente}'
            : _puestoGerenteController.text.trim(),
        'responsableNombre': _responsableController.text.trim().isEmpty
            ? '{nombre_del_responsable_del_cliente}'
            : _responsableController.text.trim(),
        'responsablePuesto': _puestoResponsableController.text.trim().isEmpty
            ? '{nombre_del_puesto_del_responsable_del_cliente}'
            : _puestoResponsableController.text.trim(),
        'brandName': CompanyProfile.brandName,
        'legalName': CompanyProfile.legalName,
      },
    );
  }

  Future<Uint8List?> _loadAssetBytes(String assetPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Map<String, String> get _templateValues => {
        'hora_establecida_por_usuario': _horaEstablecidaController.text.trim(),
      'fecha_actual': DateFormat('dd/MM/yyyy').format(DateTime.now()),
      // Alias legacy para plantillas viejas.
      'fecha_acutal': DateFormat('dd/MM/yyyy').format(DateTime.now()),
        'nombre_del_cliente': _clienteController.text.trim(),
        'direccion_del_cliente': _direccionController.text.trim(),
        'ubicacion_del_cliente': _ubicacionController.text.trim(),
        'descripcion_del_servicio': _servicioController.text.trim(),
        'numero_de_pedido': _numeroPedidoController.text.trim(),
      'fecha_aprobacion_del_pedido': _fechaAprobacionPedidoController.text.trim(),
        'fecha_aprobacion_pedido': _fechaAprobacionPedidoController.text.trim(),
      'razon_social_del_cliente': _razonSocialController.text.trim(),
      'titulo_del_responsable_del_cliente': _puestoResponsableController.text.trim(),
      'titulo_del_supervisor_del_cliente': _puestoResponsableController.text.trim(),
        'razon_social_facturacion': _razonSocialController.text.trim(),
      'nombre_del_gerente_del_cliente': _gerenteClienteController.text.trim(),
      'nombre_del_supervisor_del_cliente': _responsableController.text.trim(),
      'nombre_del_responsable_del_cliente': _responsableController.text.trim(),
      'nombre_del_titulo_del_responsable_del_cliente': _puestoResponsableController.text.trim(),
      'nombre_del_titulo_del_supervisor_del_cliente': _puestoResponsableController.text.trim(),
      'nombre_del_puesto_del_gerente_del_cliente': _puestoGerenteController.text.trim(),
      'nombre_del_puesto_del_supervisor_del_cliente': _puestoResponsableController.text.trim(),
      'nombre_del_puesto_del_responsable_del_cliente': _puestoResponsableController.text.trim(),
      'fecha_de_inicio': _fechaInicioController.text.trim(),
      'fecha_de_conclusion': _fechaConclusionController.text.trim(),
        'fecha_inicio': _fechaInicioController.text.trim(),
        'fecha_conclusion': _fechaConclusionController.text.trim(),
      };

  String _renderTemplate(String template, Map<String, String> values) {
    return template.replaceAllMapped(RegExp(r'\{[^{}]+\}'), (match) {
      final token = match.group(0)!;
      final key = token.substring(1, token.length - 1);
      final value = values[key];
      if (value == null || value.isEmpty) {
        return token;
      }
      return value;
    });
  }

  Future<void> _previewPdf() async {
    if (!_isAdmin) {
      showRemaMessage(context, 'Solo admin puede generar el acta final.');
      return;
    }
    if (!_validateForPdf()) {
      return;
    }

    final bytes = await _runPdfGeneration(
      message: 'Generando previsualizacion del acta...',
      task: _buildPdfBytes,
      estimatedDuration: const Duration(seconds: 7),
    );
    if (!mounted) {
      return;
    }

    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> _downloadPdf() async {
    if (!_isAdmin) {
      showRemaMessage(context, 'Solo admin puede descargar el PDF final.');
      return;
    }
    if (!_validateForPdf()) {
      return;
    }

    final bytes = await _runPdfGeneration(
      message: 'Generando PDF final del acta...',
      task: _buildPdfBytes,
      estimatedDuration: const Duration(seconds: 8),
    );
    final rawOrder = _numeroPedidoController.text.trim();
    final order = rawOrder.isEmpty ? 'sin_pedido' : rawOrder.replaceAll(' ', '_');

    await Printing.sharePdf(
      bytes: bytes,
      filename: 'acta_entrega_$order.pdf',
    );

    if (!mounted) {
      return;
    }
    showRemaMessage(context, 'Acta PDF lista para descarga/compartir.');
  }

  Future<T> _runPdfGeneration<T>({
    required String message,
    required Future<T> Function() task,
    required Duration estimatedDuration,
  }) async {
    if (mounted) {
      setState(() {
        _isGeneratingPdf = true;
        _pdfGenerationMessage = message;
        _pdfProgressValue = 0;
      });
      _startPdfProgressSimulation(estimatedDuration);
    }
    try {
      final result = await task();
      if (mounted) {
        setState(() => _pdfProgressValue = 1);
      }
      return result;
    } finally {
      _pdfProgressTimer?.cancel();
      _pdfProgressTimer = null;
      if (mounted) {
        setState(() {
          _isGeneratingPdf = false;
          _pdfGenerationMessage = null;
          _pdfProgressValue = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'Actas de Entrega',
      subtitle: 'Flujo final de cierre: cuerpo de acta y reporte fotografico.',
      trailing: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (widget.quoteId != null && widget.quoteId!.isNotEmpty && _isAdmin)
            _actaFinalizada
                ? Chip(
                    avatar: const Icon(Icons.check_circle, color: Colors.green, size: 18),
                    label: const Text('ACTA FINALIZADA'),
                    backgroundColor: const Color(0xFFDFF4DD),
                    side: BorderSide.none,
                  )
                : ElevatedButton.icon(
                    onPressed: _isGeneratingPdf ? null : _finalizeActa,
                    icon: const Icon(Icons.task_alt),
                    label: const Text('Finalizar Acta'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                    ),
                  ),
          OutlinedButton.icon(
            onPressed: _isGeneratingPdf ? null : _previewPdf,
            icon: const Icon(Icons.print_outlined),
            label: const Text('Previsualizar'),
          ),
          ElevatedButton.icon(
            onPressed: _isGeneratingPdf ? null : _downloadPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Descargar PDF'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_missingResponsiblesError != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                border: Border.all(color: Colors.red.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.red.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Responsables Incompletos',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _missingResponsiblesError!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
          _RoleAndSteps(
            step: _step,
            onStepChanged: (step) => setState(() => _step = step),
          ),
          if (_isLoadingClient) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 3),
          ],
          if (_isGeneratingPdf) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                border: Border.all(color: const Color(0xFFFFCC80)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _pdfGenerationMessage ?? 'Tu documento se esta generando, te notificaremos cuando este listo.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  const LinearProgressIndicator(minHeight: 3),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          if (_step == 0)
            _ActaBodyStep(
              isAdmin: _isAdmin,
              isLoadingClient: _isLoadingClient,
              clienteController: _clienteController,
              razonSocialController: _razonSocialController,
              direccionController: _direccionController,
              servicioController: _servicioController,
              gerenteClienteController: _gerenteClienteController,
              responsableController: _responsableController,
              puestoGerenteController: _puestoGerenteController,
              puestoResponsableController: _puestoResponsableController,
              fechaInicioController: _fechaInicioController,
              fechaConclusionController: _fechaConclusionController,
              numeroPedidoController: _numeroPedidoController,
              fechaAprobacionPedidoController: _fechaAprobacionPedidoController,
              ubicacionController: _ubicacionController,
              horaEstablecidaController: _horaEstablecidaController,
              actaTemplateController: _actaTemplateController,
              onPickDate: _selectDate,
              onRefreshClientData: _refreshClientData,
            )
          else
            _PhotoReportStep(
              isAdmin: _isAdmin,
              fotoIngreso: _fotoIngreso,
              fotoAntes: _fotoAntes,
              fotoDespues: _fotoDespues,
              fotosDurante: _fotosDurante,
              isProcessingSinglePhoto: _isProcessingSinglePhoto,
              processingSingleStage: _processingSingleStage,
              isProcessingDurantePhotos: _isProcessingDurantePhotos,
              onPickIngreso: () => _pickSinglePhoto(stage: 'ingreso', setTarget: (value) => _fotoIngreso = value),
              onPickAntes: () => _pickSinglePhoto(stage: 'antes', setTarget: (value) => _fotoAntes = value),
              onPickDespues: () => _pickSinglePhoto(stage: 'despues', setTarget: (value) => _fotoDespues = value),
              onPickDurante: _pickMultipleDurante,
              onRemoveDurante: (item) => setState(() => _fotosDurante.remove(item)),
              onClearSingle: (stage) {
                setState(() {
                  switch (stage) {
                    case 'ingreso':
                      _fotoIngreso = null;
                      break;
                    case 'antes':
                      _fotoAntes = null;
                      break;
                    case 'despues':
                      _fotoDespues = null;
                      break;
                  }
                });
              },
            ),
        ],
      ),
    );
  }

  pw.Widget _photoSection(String title, pw.MemoryImage? image) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Container(
          width: double.infinity,
          height: 380,
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            color: PdfColors.grey100,
          ),
          child: image != null
              ? pw.Image(image, fit: pw.BoxFit.contain)
              : pw.Center(child: pw.Text('Sin evidencia cargada')),
        ),
      ],
    );
  }

  Future<pw.MemoryImage?> _loadHeaderLogo() async {
    try {
      final data = await rootBundle.load('assets/images/logo_remaa.png');
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  Future<pw.MemoryImage?> _loadWatermarkImage() async {
    try {
      final data = await rootBundle.load('assets/images/marca_agua_remaa.png');
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  pw.Widget _pdfHeader(pw.MemoryImage? logo) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: 92,
              height: 46,
              alignment: pw.Alignment.centerLeft,
              child: logo != null
                  ? pw.Image(logo, fit: pw.BoxFit.contain)
                  : pw.Text(
                      CompanyProfile.brandName,
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
                    ),
            ),
            pw.Spacer(),
            pw.SizedBox(
              width: 280,
              child: pw.Text(
                CompanyProfile.legalName,
                textAlign: pw.TextAlign.right,
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Center(
          child: pw.Text(
            'ACTA ENTREGA - RECEPCIÓN',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
          ),
        ),
      ],
    );
  }

  pw.Widget _pageFooter(int page) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text(
        'Pagina $page de 5',
        style: const pw.TextStyle(fontSize: 9),
      ),
    );
  }

  pw.Page _photoPage({
    required pw.MemoryImage? logo,
    required String title,
    required pw.MemoryImage? image,
    required int page,
  }) {
    return pw.Page(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(36),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _pdfHeader(logo),
            pw.SizedBox(height: 20),
            _photoSection(title, image),
            pw.Spacer(),
            _pageFooter(page),
          ],
        );
      },
    );
  }

  pw.Widget _signatureBlock(String title, String subtitle) {
    return pw.Container(
      width: 165,
      padding: const pw.EdgeInsets.only(top: 18),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.black),
        ),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            title,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
          ),
          pw.Text(
            subtitle,
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 8),
          ),
        ],
      ),
    );
  }
}

const String _defaultActaTemplate = '''A las {hora_establecida_por_usuario} hrs del {fecha_actual}, se reúnen en {nombre_del_cliente}, ubicado en {direccion_del_cliente}, {ubicacion_del_cliente}, Ing. Miguel Vázquez, Representante de Soluciones Integrales Sustentables Inteligentes y Dinámicas REMA, S.A.S. de C.V. y el {titulo_del_responsable_del_cliente} {nombre_del_responsable_del_cliente}, {nombre_del_puesto_del_responsable_del_cliente} del {nombre_del_cliente}.

  Para la Revisión de la Entrega-Recepción de Servicio de 
  {descripcion_del_servicio}

  Confirmado con el Pedido No. {numero_de_pedido} de fecha {fecha_aprobacion_del_pedido}, 
  Facturado a: {nombre_del_cliente}

  Dicho servicio dio inicio el {fecha_de_inicio} y concluyendo el {fecha_de_conclusion}.

  Se hace constar la Terminación del Proyecto de conformidad.

  La Presente Acta No exime a Soluciones Integrales Sustentables Inteligentes y Dinámicas REMA, S.A.S. de C.V., de los Vicios Ocultos que Resultaran y se Obliga por la Presente a Corregir las Deficiencias por el Periodo de Un Año sin Costo Alguno para: {nombre_del_cliente}, 

  Se Firma de Conformidad de Ambas partes:

  
  
  ''';

class _RoleAndSteps extends StatelessWidget {
  const _RoleAndSteps({
    required this.step,
    required this.onStepChanged,
  });

  final int step;
  final ValueChanged<int> onStepChanged;

  @override
  Widget build(BuildContext context) {
    return RemaPanel(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Cuerpo Acta'),
                selected: step == 0,
                onSelected: (_) => onStepChanged(0),
              ),
              ChoiceChip(
                label: const Text('Reporte Fotografico'),
                selected: step == 1,
                onSelected: (_) => onStepChanged(1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActaBodyStep extends StatelessWidget {
  const _ActaBodyStep({
    required this.isAdmin,
    required this.isLoadingClient,
    required this.clienteController,
    required this.razonSocialController,
    required this.direccionController,
    required this.servicioController,
    required this.gerenteClienteController,
    required this.responsableController,
    required this.puestoGerenteController,
    required this.puestoResponsableController,
    required this.fechaInicioController,
    required this.fechaConclusionController,
    required this.numeroPedidoController,
    required this.fechaAprobacionPedidoController,
    required this.ubicacionController,
    required this.horaEstablecidaController,
    required this.actaTemplateController,
    required this.onPickDate,
    required this.onRefreshClientData,
  });

  final bool isAdmin;
  final bool isLoadingClient;
  final TextEditingController clienteController;
  final TextEditingController razonSocialController;
  final TextEditingController direccionController;
  final TextEditingController servicioController;
  final TextEditingController gerenteClienteController;
  final TextEditingController responsableController;
  final TextEditingController puestoGerenteController;
  final TextEditingController puestoResponsableController;
  final TextEditingController fechaInicioController;
  final TextEditingController fechaConclusionController;
  final TextEditingController numeroPedidoController;
  final TextEditingController fechaAprobacionPedidoController;
  final TextEditingController ubicacionController;
  final TextEditingController horaEstablecidaController;
  final TextEditingController actaTemplateController;
  final ValueChanged<TextEditingController> onPickDate;
  final Future<void> Function({bool showFeedback}) onRefreshClientData;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        RemaPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: RemaSectionHeader(title: 'Datos base (BBDD)')),
                  TextButton.icon(
                    onPressed: isLoadingClient ? null : () => onRefreshClientData(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Actualizar'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _ActaField(label: 'Cliente', controller: clienteController),
              const SizedBox(height: 16),
              _ActaField(label: 'Razon social', controller: razonSocialController),
              const SizedBox(height: 16),
              _ActaField(label: 'Direccion', controller: direccionController),
              const SizedBox(height: 16),
              _ActaField(label: 'Ubicacion', controller: ubicacionController),
              const SizedBox(height: 16),
              _ActaField(
                label: 'Descripcion del servicio',
                controller: servicioController,
                maxLines: 6,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _ActaField(
                      label: 'Supervisor del cliente',
                      controller: responsableController,
                      forceUppercase: true,
                      allowOnlyText: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActaField(
                      label: 'Puesto del supervisor',
                      controller: puestoResponsableController,
                      forceUppercase: true,
                      allowOnlyText: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _ActaField(
                      label: 'Gerente del cliente',
                      controller: gerenteClienteController,
                      forceUppercase: true,
                      allowOnlyText: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActaField(
                      label: 'Puesto del gerente',
                      controller: puestoGerenteController,
                      forceUppercase: true,
                      allowOnlyText: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        RemaPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const RemaSectionHeader(title: 'Campos manuales para cierre'),
              const SizedBox(height: 8),
              Text(
                'Variables manuales confirmadas: fecha inicio, fecha conclusion, numero pedido y fecha aprobacion.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: RemaColors.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _ActaField(
                      label: 'Hora establecida por usuario',
                      controller: horaEstablecidaController,
                      forceUppercase: false,
                      isHour24: true,
                      hintText: 'Ej. 18:30',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DateField(
                      label: 'Fecha de inicio',
                      controller: fechaInicioController,
                      enabled: true,
                      onTap: () => onPickDate(fechaInicioController),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DateField(
                      label: 'Fecha de conclusion',
                      controller: fechaConclusionController,
                      enabled: true,
                      onTap: () => onPickDate(fechaConclusionController),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _ActaField(
                      label: 'Numero de pedido',
                      controller: numeroPedidoController,
                      enabled: isAdmin,
                      forceUppercase: true,
                      helperText: isAdmin ? null : 'Solo admin puede capturar este campo.',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DateField(
                      label: 'Fecha aprobacion pedido',
                      controller: fechaAprobacionPedidoController,
                      enabled: isAdmin,
                      onTap: () => onPickDate(fechaAprobacionPedidoController),
                      helperText: isAdmin ? null : 'Solo admin puede capturar este campo.',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _ActaField(
                label: 'Plantilla base del acta (motor de reemplazo)',
                controller: actaTemplateController,
                maxLines: 10,
                forceUppercase: false,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PhotoReportStep extends StatelessWidget {
  const _PhotoReportStep({
    required this.isAdmin,
    required this.fotoIngreso,
    required this.fotoAntes,
    required this.fotoDespues,
    required this.fotosDurante,
    required this.isProcessingSinglePhoto,
    required this.processingSingleStage,
    required this.isProcessingDurantePhotos,
    required this.onPickIngreso,
    required this.onPickAntes,
    required this.onPickDespues,
    required this.onPickDurante,
    required this.onRemoveDurante,
    required this.onClearSingle,
  });

  final bool isAdmin;
  final _PickedMedia? fotoIngreso;
  final _PickedMedia? fotoAntes;
  final _PickedMedia? fotoDespues;
  final List<_PickedMedia> fotosDurante;
  final bool isProcessingSinglePhoto;
  final String? processingSingleStage;
  final bool isProcessingDurantePhotos;
  final VoidCallback onPickIngreso;
  final VoidCallback onPickAntes;
  final VoidCallback onPickDespues;
  final VoidCallback onPickDurante;
  final ValueChanged<_PickedMedia> onRemoveDurante;
  final ValueChanged<String> onClearSingle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        RemaPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const RemaSectionHeader(title: 'Paginas 2-5 / Reporte Fotografico'),
              const SizedBox(height: 18),
              _SinglePhotoCard(
                title: 'Ingreso a las instalaciones',
                subtitle: 'Pagina 2',
                media: fotoIngreso,
                isProcessing: isProcessingSinglePhoto && processingSingleStage == 'ingreso',
                onPick: onPickIngreso,
                onClear: () => onClearSingle('ingreso'),
              ),
              const SizedBox(height: 12),
              _SinglePhotoCard(
                title: 'Antes (levantamiento)',
                subtitle: 'Pagina 3',
                media: fotoAntes,
                isProcessing: isProcessingSinglePhoto && processingSingleStage == 'antes',
                onPick: onPickAntes,
                onClear: () => onClearSingle('antes'),
              ),
              const SizedBox(height: 12),
              _SinglePhotoCard(
                title: 'Despues (entrega final)',
                subtitle: 'Pagina 5',
                media: fotoDespues,
                isProcessing: isProcessingSinglePhoto && processingSingleStage == 'despues',
                onPick: onPickDespues,
                onClear: () => onClearSingle('despues'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Durante (pagina 4): evidencia de staff durante ejecucion.',
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: isProcessingDurantePhotos ? null : onPickDurante,
                    icon: isProcessingDurantePhotos
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_a_photo_outlined),
                    label: Text(isProcessingDurantePhotos ? 'Cargando...' : 'Agregar fotos'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final item in fotosDurante)
                    _ThumbPhoto(
                      media: item,
                      onRemove: () => onRemoveDurante(item),
                    ),
                ],
              ),
              if (fotosDurante.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(top: 6),
                  color: RemaColors.surfaceLow,
                  child: const Text('Sin evidencia DURANTE cargada.'),
                ),
              if (!isAdmin) ...[
                const SizedBox(height: 16),
                const Text(
                  'Modo Staff: puedes capturar evidencia. El cierre y emision PDF final son acciones de admin.',
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ActaField extends StatelessWidget {
  const _ActaField({
    required this.label,
    required this.controller,
    this.maxLines = 1,
    this.enabled = true,
    this.forceUppercase = true,
    this.helperText,
    this.hintText,
    this.allowOnlyText = false,
    this.isHour24 = false,
  });

  final String label;
  final TextEditingController controller;
  final int maxLines;
  final bool enabled;
  final bool forceUppercase;
  final String? helperText;
  final String? hintText;
  final bool allowOnlyText;
  final bool isHour24;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      enabled: enabled,
      keyboardType: isHour24 ? TextInputType.datetime : TextInputType.text,
      textCapitalization: forceUppercase ? TextCapitalization.characters : TextCapitalization.sentences,
      inputFormatters: [
        if (allowOnlyText)
          FilteringTextInputFormatter.allow(RegExp(r'[A-Za-zÁÉÍÓÚÜÑáéíóúüñ ]')),
        if (isHour24) const _Hour24TextFormatter(),
        if (forceUppercase && !isHour24) const _UpperCaseTextFormatter(),
      ],
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText ?? 'Ingresa $label',
        helperText: helperText,
      ),
    );
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

class _Hour24TextFormatter extends TextInputFormatter {
  const _Hour24TextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final clamped = digits.length > 4 ? digits.substring(0, 4) : digits;
    final buffer = StringBuffer();
    for (var index = 0; index < clamped.length; index++) {
      if (index == 2) {
        buffer.write(':');
      }
      buffer.write(clamped[index]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.controller,
    required this.onTap,
    this.enabled = true,
    this.helperText,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onTap;
  final bool enabled;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: true,
      enabled: enabled,
      onTap: enabled ? onTap : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'Selecciona $label',
        helperText: helperText,
        suffixIcon: const Icon(Icons.event),
      ),
    );
  }
}

class _SinglePhotoCard extends StatelessWidget {
  const _SinglePhotoCard({
    required this.title,
    required this.subtitle,
    required this.media,
    required this.isProcessing,
    required this.onPick,
    required this.onClear,
  });

  final String title;
  final String subtitle;
  final _PickedMedia? media;
  final bool isProcessing;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: RemaColors.surfaceLow,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$title · $subtitle',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              TextButton.icon(
                onPressed: isProcessing ? null : onPick,
                icon: isProcessing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file_outlined),
                label: Text(isProcessing ? 'Cargando...' : 'Cargar'),
              ),
            ],
          ),
          if (media == null)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Sin imagen seleccionada.'),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.memory(
                    media!.bytes,
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(child: Text(media!.name, overflow: TextOverflow.ellipsis)),
                    IconButton(
                      onPressed: onClear,
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Quitar imagen',
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ThumbPhoto extends StatelessWidget {
  const _ThumbPhoto({required this.media, required this.onRemove});

  final _PickedMedia media;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 144,
      decoration: BoxDecoration(
        color: RemaColors.surfaceLow,
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.memory(
              media.bytes,
              height: 92,
              width: 128,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            media.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 18),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _PickedMedia {
  const _PickedMedia({
    required this.name,
    required this.bytes,
    required this.size,
    this.mimeType,
  });

  final String name;
  final Uint8List bytes;
  final int size;
  final String? mimeType;
}
