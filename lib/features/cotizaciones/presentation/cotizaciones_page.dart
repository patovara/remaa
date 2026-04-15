import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../../core/config/supabase_bootstrap.dart';
import '../../../core/theme/rema_colors.dart';
import '../../../core/utils/rema_feedback.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/rema_panels.dart';
import '../domain/concept_generation.dart';
import '../domain/quote_models.dart';
import 'concepts_catalog_controller.dart';
import 'quotes_controller.dart';

// Global lock to prevent stacked email dialogs across rapid taps and widget instances.
bool _isSendQuoteEmailDialogOpenGlobal = false;

class CotizacionesPage extends ConsumerStatefulWidget {
  const CotizacionesPage({
    super.key,
    this.initialClientId,
    this.openComposerOnLoad = false,
  });

  final String? initialClientId;
  final bool openComposerOnLoad;

  @override
  ConsumerState<CotizacionesPage> createState() => _CotizacionesPageState();
}

class _CotizacionesPageState extends ConsumerState<CotizacionesPage> {
  String _search = '';
  String? _statusFilter; // null = todos, 'draft', 'concluded', 'approved', 'declined'
  bool _didOpenComposerFromRoute = false;
  late final Future<List<ClientOption>> _clientOptionsFuture;

  @override
  void initState() {
    super.initState();
    _clientOptionsFuture = _fetchClientOptions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _didOpenComposerFromRoute) {
        return;
      }
      final initialClientId = widget.initialClientId?.trim();
      if (widget.openComposerOnLoad && initialClientId != null && initialClientId.isNotEmpty) {
        _didOpenComposerFromRoute = true;
        _openNewQuoteDialog(fixedClientId: initialClientId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final quotesAsync = ref.watch(quotesProvider);
    final projectsAsync = ref.watch(quoteProjectsProvider);
    final usdRateAsync = ref.watch(quoteUsdRateProvider);
    final projectById = {
      for (final project in projectsAsync.valueOrNull ?? const <ProjectLookup>[])
        project.id: project,
    };

    return PageFrame(
      title: 'Gestión de Cotizaciones',
      subtitle: 'Resumen operativo y detalle de cotizaciones activas.',
      trailing: FilledButton.icon(
        onPressed: () => _openNewQuoteDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Nueva Cotización'),
      ),
      child: quotesAsync.when(
        data: (quotes) {
          final filtered = _filterQuotes(quotes);
          return FutureBuilder<List<ClientOption>>(
            future: _clientOptionsFuture,
            builder: (context, clientsSnapshot) {
              final clientNameById = {
                for (final client in clientsSnapshot.data ?? const <ClientOption>[])
                  client.id: client.name,
              };
              final groupedQuotes = _buildGroupedQuotes(
                quotes: filtered,
                projectById: projectById,
                clientNameById: clientNameById,
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Buscar cotización por folio...',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => setState(() => _search = value.trim().toLowerCase()),
                  ),
                  const SizedBox(height: 24),
                  _StatusFilterBar(
                    current: _statusFilter,
                    onChanged: (value) => setState(() => _statusFilter = value),
                  ),
                  const SizedBox(height: 16),
                  _QuotesMetrics(quotes: filtered),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final mobile = constraints.maxWidth < 600;

                      if (mobile) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Listado Detallado', style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 12),
                            if (groupedQuotes.isEmpty)
                              const Text('No hay cotizaciones para mostrar.')
                            else
                              for (final clientGroup in groupedQuotes)
                                _ClientQuotesGroup(
                                  clientGroup: clientGroup,
                                  mobile: true,
                                  quoteBuilder: (entry) => _QuoteMobileCard(
                                    quote: entry.quote,
                                    projectName: entry.projectName,
                                    estimatedUsdRate: usdRateAsync.valueOrNull?.rate,
                                    onViewProjectDescription: () => _showProjectDescription(
                                      entry.quote,
                                      projectById[entry.quote.projectId],
                                    ),
                                    onEdit: () => context.go('/presupuesto/${entry.quote.id}'),
                                    onShare: () => showRemaMessage(
                                      context,
                                      'Compartir ${entry.quote.quoteNumber} listo para integrar.',
                                    ),
                                    onSendEmail: () => _sendQuoteByEmail(
                                      entry.quote,
                                      projectById[entry.quote.projectId],
                                    ),
                                    onAttachPdf: entry.quote.isConcluded
                                        ? () => _attachApprovalPdf(
                                              entry.quote,
                                              projectById[entry.quote.projectId],
                                            )
                                        : null,
                                    onPreviewPdf: entry.quote.hasApprovalPdf
                                        ? () => _previewApprovalPdf(context, entry.quote)
                                        : null,
                                    onPreviewActa: entry.quote.isActaFinalizada || entry.quote.isPaid
                                        ? () => _previewFinalActa(context, entry.quote)
                                        : null,
                                    onDownloadActa: entry.quote.isActaFinalizada || entry.quote.isPaid
                                        ? () => _downloadFinalActa(context, entry.quote)
                                        : null,
                                    onShareActa: entry.quote.isActaFinalizada || entry.quote.isPaid
                                        ? () => _shareFinalActa(context, entry.quote)
                                        : null,
                                    onMarkPaid: entry.quote.isActaFinalizada
                                        ? () => _changeStatus(entry.quote.id, QuoteStatus.paid)
                                        : null,
                                        onGoToActas: (entry.quote.isConcluded ||
                                          entry.quote.isApproved ||
                                          entry.quote.isActaFinalizada ||
                                          entry.quote.isPaid)
                                        ? () => _goToActas(
                                              context,
                                              entry.quote,
                                              projectById[entry.quote.projectId],
                                            )
                                        : null,
                                    onConclude: entry.quote.isDraft
                                        ? () => _changeStatus(entry.quote.id, QuoteStatus.concluded)
                                        : null,
                                    onApprove: entry.quote.isConcluded
                                        ? () => _changeStatus(entry.quote.id, QuoteStatus.approved)
                                        : null,
                                    onDecline: !entry.quote.isDeclined &&
                                            !entry.quote.isActaFinalizada &&
                                            !entry.quote.hasApprovalPdf
                                        ? () => _changeStatus(entry.quote.id, QuoteStatus.declined)
                                        : null,
                                    onReactivate: (entry.quote.isDeclined || entry.quote.isConcluded)
                                        ? () => _changeStatus(entry.quote.id, QuoteStatus.draft)
                                        : null,
                                  ),
                                ),
                          ],
                        );
                      }

                      return RemaPanel(
                        padding: EdgeInsets.zero,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                              child: Text('Listado Detallado', style: Theme.of(context).textTheme.titleLarge),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 24),
                              child: _QuoteTableHeader(),
                            ),
                            if (groupedQuotes.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(24),
                                child: Text('No hay cotizaciones para mostrar.'),
                              )
                            else
                              for (final clientGroup in groupedQuotes)
                                _ClientQuotesGroup(
                                  clientGroup: clientGroup,
                                  mobile: false,
                                  quoteBuilder: (entry) => _QuoteRow(
                                    quote: entry.quote,
                                    projectName: entry.projectName,
                                    estimatedUsdRate: usdRateAsync.valueOrNull?.rate,
                                    onViewProjectDescription: () => _showProjectDescription(
                                      entry.quote,
                                      projectById[entry.quote.projectId],
                                    ),
                                    onEdit: () => context.go('/presupuesto/${entry.quote.id}'),
                                    onShare: () => showRemaMessage(
                                      context,
                                      'Compartir ${entry.quote.quoteNumber} listo para integrar.',
                                    ),
                                    onSendEmail: () => _sendQuoteByEmail(
                                      entry.quote,
                                      projectById[entry.quote.projectId],
                                    ),
                                    onAttachPdf: entry.quote.isConcluded
                                        ? () => _attachApprovalPdf(
                                              entry.quote,
                                              projectById[entry.quote.projectId],
                                            )
                                        : null,
                                    onPreviewPdf: entry.quote.hasApprovalPdf
                                        ? () => _previewApprovalPdf(context, entry.quote)
                                        : null,
                                    onPreviewActa: entry.quote.isActaFinalizada || entry.quote.isPaid
                                        ? () => _previewFinalActa(context, entry.quote)
                                        : null,
                                    onDownloadActa: entry.quote.isActaFinalizada || entry.quote.isPaid
                                        ? () => _downloadFinalActa(context, entry.quote)
                                        : null,
                                    onShareActa: entry.quote.isActaFinalizada || entry.quote.isPaid
                                        ? () => _shareFinalActa(context, entry.quote)
                                        : null,
                                    onMarkPaid: entry.quote.isActaFinalizada
                                        ? () => _changeStatus(entry.quote.id, QuoteStatus.paid)
                                        : null,
                                        onGoToActas: (entry.quote.isConcluded ||
                                          entry.quote.isApproved ||
                                          entry.quote.isActaFinalizada ||
                                          entry.quote.isPaid)
                                        ? () => _goToActas(
                                              context,
                                              entry.quote,
                                              projectById[entry.quote.projectId],
                                            )
                                        : null,
                                    onConclude: entry.quote.isDraft
                                        ? () => _changeStatus(entry.quote.id, QuoteStatus.concluded)
                                        : null,
                                    onApprove: entry.quote.isConcluded
                                        ? () => _changeStatus(entry.quote.id, QuoteStatus.approved)
                                        : null,
                                    onDecline: !entry.quote.isDeclined &&
                                            !entry.quote.isActaFinalizada &&
                                            !entry.quote.hasApprovalPdf
                                        ? () => _changeStatus(entry.quote.id, QuoteStatus.declined)
                                        : null,
                                    onReactivate: (entry.quote.isDeclined || entry.quote.isConcluded)
                                        ? () => _changeStatus(entry.quote.id, QuoteStatus.draft)
                                        : null,
                                  ),
                                ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: RemaPanel(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('No se pudo cargar cotizaciones.'),
                const SizedBox(height: 8),
                Text(error.toString(), style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => ref.read(quotesProvider.notifier).reload(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<QuoteRecord> _filterQuotes(List<QuoteRecord> quotes) {
    var result = quotes;
    if (_statusFilter != null) {
      result = result.where((q) => q.status == _statusFilter).toList();
    }
    if (_search.isNotEmpty) {
      result = result.where((q) => q.quoteNumber.toLowerCase().contains(_search)).toList();
    }
    return result;
  }

  List<_ClientQuoteGroup> _buildGroupedQuotes({
    required List<QuoteRecord> quotes,
    required Map<String, ProjectLookup> projectById,
    required Map<String, String> clientNameById,
  }) {
    final byClient = <String, List<_QuoteListEntry>>{};

    for (final quote in quotes) {
      final project = projectById[quote.projectId];
      final clientId = project?.clientId?.trim();
      final clientName =
          (clientId != null && clientId.isNotEmpty)
              ? (clientNameById[clientId]?.trim().isNotEmpty ?? false)
                  ? clientNameById[clientId]!.trim()
                  : 'Cliente sin nombre'
              : 'Sin cliente';

      byClient.putIfAbsent(clientName, () => <_QuoteListEntry>[]).add(
            _QuoteListEntry(
              quote: quote,
              projectName: (project?.name.trim().isNotEmpty ?? false)
                  ? project!.name.trim()
                  : 'Proyecto sin nombre',
            ),
          );
    }

    final clients = <_ClientQuoteGroup>[];
    for (final entry in byClient.entries) {
      final yearMap = <int?, List<_QuoteListEntry>>{};
      for (final item in entry.value) {
        yearMap.putIfAbsent(item.quote.createdAt?.year, () => <_QuoteListEntry>[]).add(item);
      }

      final years = <_YearQuoteGroup>[];
      for (final yearEntry in yearMap.entries) {
        final monthMap = <int?, List<_QuoteListEntry>>{};
        for (final item in yearEntry.value) {
          monthMap.putIfAbsent(item.quote.createdAt?.month, () => <_QuoteListEntry>[]).add(item);
        }

        final months = <_MonthQuoteGroup>[];
        for (final monthEntry in monthMap.entries) {
          final items = List<_QuoteListEntry>.from(monthEntry.value)
            ..sort((a, b) {
              final left = a.quote.createdAt;
              final right = b.quote.createdAt;
              if (left != null && right != null) {
                final byDate = right.compareTo(left);
                if (byDate != 0) {
                  return byDate;
                }
              }
              return b.quote.quoteNumber.compareTo(a.quote.quoteNumber);
            });
          months.add(
            _MonthQuoteGroup(
              month: monthEntry.key,
              label: _monthLabel(monthEntry.key),
              items: items,
            ),
          );
        }

        months.sort((a, b) {
          if (a.month == null && b.month == null) {
            return 0;
          }
          if (a.month == null) {
            return 1;
          }
          if (b.month == null) {
            return -1;
          }
          return b.month!.compareTo(a.month!);
        });

        years.add(
          _YearQuoteGroup(
            year: yearEntry.key,
            label: yearEntry.key?.toString() ?? 'SIN FECHA',
            months: months,
          ),
        );
      }

      years.sort((a, b) {
        if (a.year == null && b.year == null) {
          return 0;
        }
        if (a.year == null) {
          return 1;
        }
        if (b.year == null) {
          return -1;
        }
        return b.year!.compareTo(a.year!);
      });

      clients.add(_ClientQuoteGroup(clientName: entry.key, years: years));
    }

    clients.sort((a, b) => a.clientName.compareTo(b.clientName));
    return clients;
  }

  String _monthLabel(int? month) {
    if (month == null || month < 1 || month > 12) {
      return 'SIN FECHA';
    }
    const names = [
      'ENERO',
      'FEBRERO',
      'MARZO',
      'ABRIL',
      'MAYO',
      'JUNIO',
      'JULIO',
      'AGOSTO',
      'SEPTIEMBRE',
      'OCTUBRE',
      'NOVIEMBRE',
      'DICIEMBRE',
    ];
    return names[month - 1];
  }

  Future<void> _changeStatus(String quoteId, String newStatus) async {
    try {
      await ref
          .read(quotesProvider.notifier)
          .updateStatusWithOptions(quoteId: quoteId, status: newStatus);
      if (mounted) {
        final label = switch (newStatus) {
          QuoteStatus.concluded => 'Concluida',
          QuoteStatus.approved => 'Aprobada',
          QuoteStatus.actaFinalizada => 'Por cobrar',
          QuoteStatus.paid => 'Pagada',
          'declined' => 'Declinada',
          _ => 'Reactivada',
        };
        showRemaMessage(context, 'Cotizacion $label.');
      }
    } catch (error) {
      final message = error.toString();
      if (newStatus == QuoteStatus.approved &&
          message.contains(approveWithoutPdfConfirmationRequired)) {
        final confirmed = await _confirmApproveWithoutPdf();
        if (confirmed == true) {
          try {
            await ref.read(quotesProvider.notifier).updateStatusWithOptions(
                  quoteId: quoteId,
                  status: newStatus,
                  allowApproveWithoutPdf: true,
                );
            if (mounted) {
              showRemaMessage(
                context,
                'Cotizacion aprobada sin PDF de confirmacion.',
              );
            }
            return;
          } catch (retryError) {
            if (mounted) {
              showRemaMessage(context, '$retryError');
            }
            return;
          }
        }
        return;
      }
      if (mounted) {
        showRemaMessage(context, message);
      }
    }
  }

  Future<bool?> _confirmApproveWithoutPdf() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Continuar sin aprobación PDF'),
        content: const Text(
          'Esta cotización no tiene PDF de confirmación.\n\n'
          'Para sectores no hotelería puedes continuar sin aprobación.\n\n'
          '¿Deseas aprobar de todos modos?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendQuoteByEmail(QuoteRecord quote, ProjectLookup? project) async {
    if (_isSendQuoteEmailDialogOpenGlobal) {
      return;
    }
    _isSendQuoteEmailDialogOpenGlobal = true;

    try {
      final suggested = await ref
          .read(quotesProvider.notifier)
          .fetchRecipientEmailForQuote(quote.id);

      if (!mounted) {
        return;
      }

      final payload = await showDialog<({String email, String note})>(
        context: context,
        builder: (dialogContext) => _SendQuoteEmailDialog(
          initialEmail: (suggested ?? quote.recipientEmail ?? '').trim(),
          quoteNumber: quote.quoteNumber,
          projectName: project?.name ?? 'Proyecto sin nombre',
        ),
      );

      if (!mounted || payload == null) {
        return;
      }

      await ref.read(quotesProvider.notifier).sendQuoteEmail(
            quoteId: quote.id,
            recipientEmail: payload.email,
            note: payload.note,
          );
      await ref.read(quotesProvider.notifier).reload();
      if (mounted) {
        showRemaMessage(context, 'Cotizacion enviada a ${payload.email}.');
      }
    } catch (error) {
      if (mounted) {
        showRemaMessage(context, '$error');
      }
    } finally {
      _isSendQuoteEmailDialogOpenGlobal = false;
    }
  }

  Future<void> _attachApprovalPdf(QuoteRecord quote, ProjectLookup? project) async {
    ProjectLookup? resolvedProject = project;
    if (resolvedProject == null || (resolvedProject.clientId?.trim().isEmpty ?? true)) {
      try {
        final projects = await ref.read(quoteProjectsProvider.future);
        for (final item in projects) {
          if (item.id == quote.projectId) {
            resolvedProject = item;
            break;
          }
        }
      } catch (_) {}
    }

    if (!mounted) {
      return;
    }

    final validationError = _approvalPdfPrerequisiteError(quote, resolvedProject);
    if (validationError != null) {
      showRemaMessage(context, validationError);
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );

    if (!mounted || result == null || result.files.isEmpty) {
      return;
    }

    final file = result.files.first;
    final Uint8List? bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      showRemaMessage(context, 'No se pudo leer el PDF seleccionado.');
      return;
    }

    try {
      await ref.read(quotesProvider.notifier).attachApprovalPdf(
            quoteId: quote.id,
            bytes: bytes,
            fileName: file.name,
          );
      if (mounted) {
        showRemaMessage(context, 'PDF del pedido adjuntado en ${quote.quoteNumber}.');
      }
    } catch (error) {
      if (mounted) {
        showRemaMessage(context, '$error');
      }
    }
  }

  String? _approvalPdfPrerequisiteError(QuoteRecord quote, ProjectLookup? project) {
    if (quote.isDeclined) {
      return 'No puedes adjuntar el PDF de aprobacion a una cotizacion declinada.';
    }
    if (quote.isActaFinalizada) {
      return 'No puedes adjuntar el PDF de aprobacion a una cotizacion con acta finalizada.';
    }
    if (!quote.isConcluded) {
      return 'Primero debes concluir la cotizacion antes de adjuntar el PDF de aprobacion.';
    }
    if (project != null && (project.clientId?.trim().isEmpty ?? true)) {
      return 'Debes vincular la cotizacion a un cliente registrado antes de adjuntar el PDF de aprobacion.';
    }
    if (quote.total <= 0) {
      return 'La cotizacion debe estar concluida: agrega al menos un concepto con importe antes de adjuntar el PDF de aprobacion.';
    }
    return null;
  }

  Future<void> _previewApprovalPdf(BuildContext context, QuoteRecord quote) async {
    if (quote.approvalPdfPath == null || quote.approvalPdfPath!.isEmpty) {
      showRemaMessage(context, 'No hay PDF adjunto para previsualizar.');
      return;
    }

    try {
      final client = SupabaseBootstrap.client;
      if (client == null) {
        showRemaMessage(context, 'No hay conexion activa con Supabase.');
        return;
      }

      // Descargar el PDF desde storage
      final bytes = await client.storage
          .from('quote-approvals')
          .download(quote.approvalPdfPath!);

      if (!context.mounted) return;

      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        format: PdfPageFormat.letter,
        name: 'confirmacion_pedido_${quote.quoteNumber}.pdf',
      );
    } catch (error) {
      if (context.mounted) {
        showRemaMessage(context, 'No se pudo cargar el PDF: $error');
      }
    }
  }

  Future<ActaDocumentRecord?> _loadFinalActaDocument(QuoteRecord quote) async {
    return ref.read(quotesRepositoryProvider).fetchActaDocument(quote.id);
  }

  Future<void> _previewFinalActa(BuildContext context, QuoteRecord quote) async {
    final document = await _loadFinalActaDocument(quote);
    if (!context.mounted) return;
    if (document == null) {
      showRemaMessage(context, 'No hay acta final guardada para esta cotizacion.');
      return;
    }
    await Printing.layoutPdf(onLayout: (_) async => document.bytes, name: document.fileName);
  }

  Future<void> _downloadFinalActa(BuildContext context, QuoteRecord quote) async {
    final document = await _loadFinalActaDocument(quote);
    if (!context.mounted) return;
    if (document == null) {
      showRemaMessage(context, 'No hay acta final guardada para esta cotizacion.');
      return;
    }
    await Printing.sharePdf(bytes: document.bytes, filename: document.fileName);
    if (context.mounted) {
      showRemaMessage(context, 'Acta final lista para descarga.');
    }
  }

  Future<void> _shareFinalActa(BuildContext context, QuoteRecord quote) async {
    final document = await _loadFinalActaDocument(quote);
    if (!context.mounted) return;
    if (document == null) {
      showRemaMessage(context, 'No hay acta final guardada para esta cotizacion.');
      return;
    }
    await Printing.sharePdf(bytes: document.bytes, filename: document.fileName);
    if (context.mounted) {
      showRemaMessage(context, 'Acta final lista para compartir.');
    }
  }

  Future<void> _goToActas(BuildContext context, QuoteRecord quote, ProjectLookup? project) async {
    try {
      ProjectLookup? resolvedProject = project;
      if (resolvedProject == null) {
        try {
          final projects = await ref.read(quoteProjectsProvider.future);
          for (final item in projects) {
            if (item.id == quote.projectId) {
              resolvedProject = item;
              break;
            }
          }
        } catch (_) {}
      }

      String? clientId = resolvedProject?.clientId?.trim();
      if (clientId == null || clientId.isEmpty) {
        final client = SupabaseBootstrap.client;
        if (client != null && RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(quote.projectId)) {
          final projectRow = await client
              .from('projects')
              .select('client_id')
              .eq('id', quote.projectId)
              .maybeSingle();
          clientId = (projectRow?['client_id'] as String?)?.trim();
        }
      }

      if (!context.mounted) return;

      if (clientId == null || clientId.isEmpty) {
        showRemaMessage(context, 'Este proyecto no tiene cliente asignado.');
        return;
      }

      if (!context.mounted) return;

      // Navegar a ACTAS con el clientId
      context.push('/actas?clientId=$clientId&quoteId=${quote.id}');
    } catch (error) {
      if (context.mounted) {
        showRemaMessage(context, 'Error al cargar datos del cliente: $error');
      }
    }
  }

  Future<void> _openNewQuoteDialog({String? fixedClientId}) async {
    final catalogState = ref.read(conceptsCatalogProvider);
    final catalog = catalogState.valueOrNull;
    if (catalog == null) {
      showRemaMessage(context, 'Catalogo de conceptos no disponible aun.');
      await ref.read(conceptsCatalogProvider.notifier).reload();
      return;
    }

    final clientOptions = await _fetchClientOptions();
    if (!mounted) {
      return;
    }

    final normalizedFixedClientId = fixedClientId?.trim();
    ClientOption? fixedClient;
    if (normalizedFixedClientId != null && normalizedFixedClientId.isNotEmpty) {
      for (final item in clientOptions) {
        if (item.id == normalizedFixedClientId) {
          fixedClient = item;
          break;
        }
      }
      if (fixedClient == null) {
        showRemaMessage(context, 'No se pudo resolver el cliente para la nueva cotizacion.');
        return;
      }
    }

    if (fixedClient == null && clientOptions.isEmpty) {
      showRemaMessage(context, 'No hay clientes disponibles para crear cotizacion.');
      return;
    }

    if (!mounted) {
      return;
    }

    final result = await showDialog<_NewQuoteResult>(
      context: context,
      builder: (context) => _NewQuoteDialog(
        catalog: catalog,
        clients: clientOptions,
        fixedClient: fixedClient,
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    ProjectLookup project;
    try {
      final projectKey = await ref.read(quotesProvider.notifier).reserveProjectKey(
        clientId: result.clientId,
        projectTypeId: result.projectTypeId,
          );
      project = await ref.read(quotesProvider.notifier).createProject(
            input: NewProjectInput(
              code: projectKey,
              name: result.projectName,
              clientId: result.clientId,
            ),
          );
      final quote = await ref.read(quotesProvider.notifier).createDraft(
            projectId: project.id,
            universeId: result.universeId,
            projectTypeId: result.projectTypeId,
            projectKey: projectKey,
          );

      if (!mounted) {
        return;
      }
      showRemaMessage(context, 'Cotizacion ${quote.quoteNumber} creada para ${project.name}.');
      context.go('/presupuesto/${quote.id}');
    } catch (error) {
      if (!mounted) {
        return;
      }
      showRemaMessage(context, '$error');
    }
  }

  Future<List<ClientOption>> _fetchClientOptions() async {
    final mergedById = <String, ClientOption>{};

    final client = SupabaseBootstrap.client;
    if (client == null) {
      return const <ClientOption>[];
    }

    try {
      final rows = await client
          .from('clients')
          .select('id, business_name, contact_name')
          .order('business_name');
      for (final row in rows) {
        final id = (row['id'] as String? ?? '').trim();
        final contactName = (row['contact_name'] as String? ?? '').trim();
        final businessName = (row['business_name'] as String? ?? '').trim();
        final displayName = contactName.isNotEmpty ? contactName : businessName;
        if (id.isEmpty || displayName.isEmpty) {
          continue;
        }
        mergedById[id] = ClientOption(id: id, name: displayName);
      }
    } catch (_) {}

    final result = mergedById.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  Future<void> _showProjectDescription(
    QuoteRecord quote,
    ProjectLookup? project,
  ) async {
    final description = project?.description?.trim() ?? '';
    final hasDescription = description.isNotEmpty;

    // Cargar entradas de levantamiento del proyecto (admin y staff ven lo que RLS permite)
    List<SurveyEntryRecord> entries = const [];
    if (project != null) {
      try {
        entries = await ref.read(projectSurveyEntriesProvider(project.id).future);
      } catch (_) {
        entries = const [];
      }
    }

    if (!mounted) return;

    final allImages = [
      for (final entry in entries) ...entry.evidencePreviewList,
    ];
    final hasImages = allImages.isNotEmpty;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Descripcion de levantamiento'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  project == null
                      ? 'Proyecto no encontrado para ${quote.quoteNumber}.'
                      : '${project.code} - ${project.name}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 12),
                if (project?.siteAddress != null && project!.siteAddress!.trim().isNotEmpty) ...[
                  Text(
                    project.siteAddress!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: RemaColors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                ],
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: RemaColors.surfaceLow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    hasDescription
                        ? description
                        : 'Este proyecto no tiene descripcion capturada en levantamiento.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 12),
                if (hasImages) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final bytes in allImages)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: 88,
                            height: 88,
                            child: Image.memory(bytes, fit: BoxFit.cover),
                          ),
                        ),
                    ],
                  ),
                ] else
                  Text(
                    'No hay evidencias fotograficas para este levantamiento.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: RemaColors.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}

class _QuotesMetrics extends StatelessWidget {
  const _QuotesMetrics({required this.quotes});

  final List<QuoteRecord> quotes;

  @override
  Widget build(BuildContext context) {
    final pending = quotes.where((quote) => quote.isDraft).length;
    final concluded = quotes.where((quote) => quote.isConcluded).length;
    final approved = quotes.where((quote) => quote.isApproved).length;
    final pendingPayment = quotes.where((quote) => quote.isActaFinalizada).length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final tiles = [
          RemaMetricTile(
            label: 'Pendientes',
            value: '$pending',
            caption: 'Estado draft',
          ),
          RemaMetricTile(
            label: 'Concluidas',
            value: '$concluded',
            caption: 'Listas para aprobacion',
            backgroundColor: RemaColors.surfaceWhite,
          ),
          RemaMetricTile(
            label: 'Aprobadas',
            value: '$approved',
            caption: 'Con autorizacion',
            backgroundColor: RemaColors.surfaceLow,
          ),
          RemaMetricTile(
            label: 'Por cobrar',
            value: '$pendingPayment',
            caption: 'Acta finalizada',
            backgroundColor: const Color(0xFFFFDEA0),
          ),
        ];

        if (constraints.maxWidth < 960) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final tile in tiles) ...[
                tile,
                if (tile != tiles.last) const SizedBox(height: 16),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (final tile in tiles) ...[
              Expanded(child: tile),
              if (tile != tiles.last) const SizedBox(width: 16),
            ],
          ],
        );
      },
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    Color bg;
    String label;
    switch (status) {
      case QuoteStatus.concluded:
        bg = const Color(0xFFFFF1CC);
        label = 'Concluida';
        break;
      case QuoteStatus.approved:
        bg = const Color(0xFFDFF4DD);
        label = 'Aprobada';
        break;
      case QuoteStatus.declined:
        bg = const Color(0xFFFFDDDD);
        label = 'Declinada';
        break;
      case QuoteStatus.actaFinalizada:
        bg = const Color(0xFFD0E8FF);
        label = 'Por cobrar';
        break;
      case QuoteStatus.paid:
        bg = const Color(0xFFE3F2FD);
        label = 'Pagada';
        break;
      default:
        bg = const Color(0xFFFFDEA0);
        label = 'Pendiente';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: bg,
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({required this.current, required this.onChanged});

  final String? current;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = <(String?, String)>[
      (null, 'Todos'),
      ('draft', 'Pendientes'),
      ('concluded', 'Concluidas'),
      ('approved', 'Aprobadas'),
      ('declined', 'Declinadas'),
      ('acta_finalizada', 'Por cobrar'),
      ('paid', 'Pagadas'),
    ];
    return Wrap(
      spacing: 8,
      children: [
        for (final (value, label) in options)
          FilterChip(
            label: Text(label),
            selected: current == value,
            onSelected: (_) => onChanged(value),
          ),
      ],
    );
  }
}

class _QuoteTableHeader extends StatelessWidget {
  const _QuoteTableHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        _HeaderCell(flex: 3, label: 'Folio'),
        _HeaderCell(flex: 2, label: 'Total'),
        _HeaderCell(flex: 2, label: 'Estado'),
        _HeaderCell(flex: 2, label: 'Acciones'),
      ],
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({required this.flex, required this.label});

  final int flex;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(label, style: Theme.of(context).textTheme.labelSmall),
      ),
    );
  }
}

class _QuoteListEntry {
  const _QuoteListEntry({
    required this.quote,
    required this.projectName,
  });

  final QuoteRecord quote;
  final String projectName;
}

class _MonthQuoteGroup {
  const _MonthQuoteGroup({
    required this.month,
    required this.label,
    required this.items,
  });

  final int? month;
  final String label;
  final List<_QuoteListEntry> items;
}

class _YearQuoteGroup {
  const _YearQuoteGroup({
    required this.year,
    required this.label,
    required this.months,
  });

  final int? year;
  final String label;
  final List<_MonthQuoteGroup> months;
}

class _ClientQuoteGroup {
  const _ClientQuoteGroup({
    required this.clientName,
    required this.years,
  });

  final String clientName;
  final List<_YearQuoteGroup> years;
}

class _ClientQuotesGroup extends StatelessWidget {
  const _ClientQuotesGroup({
    required this.clientGroup,
    required this.mobile,
    required this.quoteBuilder,
  });

  final _ClientQuoteGroup clientGroup;
  final bool mobile;
  final Widget Function(_QuoteListEntry entry) quoteBuilder;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        title: Text(clientGroup.clientName.toUpperCase(), style: titleStyle),
        children: [
          for (final yearGroup in clientGroup.years)
            ExpansionTile(
              title: Text(yearGroup.label, style: const TextStyle(fontWeight: FontWeight.w700)),
              children: [
                for (final monthGroup in yearGroup.months)
                  ExpansionTile(
                    title: Text(monthGroup.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                    childrenPadding: EdgeInsets.only(bottom: mobile ? 6 : 0),
                    children: [
                      for (final entry in monthGroup.items) quoteBuilder(entry),
                    ],
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _QuoteRow extends StatelessWidget {
  const _QuoteRow({
    required this.quote,
    required this.projectName,
    required this.estimatedUsdRate,
    required this.onViewProjectDescription,
    required this.onEdit,
    required this.onShare,
    required this.onSendEmail,
    this.onAttachPdf,
    this.onPreviewPdf,
    this.onPreviewActa,
    this.onDownloadActa,
    this.onShareActa,
    this.onMarkPaid,
    this.onConclude,
    this.onApprove,
    this.onDecline,
    this.onReactivate,
    this.onGoToActas,
  });

  final QuoteRecord quote;
  final String projectName;
  final double? estimatedUsdRate;
  final VoidCallback onViewProjectDescription;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onSendEmail;
  final VoidCallback? onAttachPdf;
  final VoidCallback? onPreviewPdf;
  final VoidCallback? onPreviewActa;
  final VoidCallback? onDownloadActa;
  final VoidCallback? onShareActa;
  final VoidCallback? onMarkPaid;
  final VoidCallback? onConclude;
  final VoidCallback? onApprove;
  final VoidCallback? onDecline;
  final VoidCallback? onReactivate;
  final VoidCallback? onGoToActas;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: RemaColors.surfaceLow.withValues(alpha: 0.8)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  quote.quoteNumber,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: RemaColors.primaryDark),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Text(
                  projectName,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: RemaColors.onSurfaceVariant, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: _DualCurrencyAmount(
              mxnLabel: _money(quote.total),
              usdLabel: _quoteUsdLabel(quote: quote, estimatedRate: estimatedUsdRate),
            ),
          ),
          Expanded(
            flex: 2,
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _StatusBadge(status: quote.status),
                Icon(
                  quote.hasApprovalPdf ? Icons.picture_as_pdf : Icons.picture_as_pdf_outlined,
                  color: quote.hasApprovalPdf ? Colors.green : Colors.grey,
                  size: 18,
                ),
                if (quote.hasApprovalPdf)
                  const Icon(
                    Icons.visibility_outlined,
                    color: Colors.blue,
                    size: 18,
                  ),
                if (quote.status == 'acta_finalizada')
                  const Tooltip(
                    message: 'Pago pendiente',
                    child: Icon(
                      Icons.payments_outlined,
                      color: Colors.amber,
                      size: 20,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                if (quote.isActaFinalizada || quote.isPaid) ...[
                  IconButton(
                    onPressed: onShareActa,
                    icon: const Icon(Icons.share_outlined),
                    tooltip: 'Compartir acta final',
                  ),
                  IconButton(
                    onPressed: onPreviewActa,
                    icon: const Icon(Icons.visibility),
                    tooltip: 'Previsualizar acta final',
                    color: Colors.blue,
                  ),
                  IconButton(
                    onPressed: onDownloadActa,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    tooltip: 'Descargar acta final',
                    color: Colors.deepPurple,
                  ),
                  if (quote.isActaFinalizada)
                    IconButton(
                      onPressed: onMarkPaid,
                      icon: const Icon(Icons.payments_outlined),
                      tooltip: 'Marcar como pagada',
                      color: Colors.green,
                    ),
                ] else ...[
                IconButton(
                  onPressed: onViewProjectDescription,
                  icon: const Icon(Icons.description_outlined),
                  tooltip: 'Ver descripcion del levantamiento',
                  color: RemaColors.primaryDark,
                ),
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: quote.isDraft ? 'Editar conceptos' : 'Ver presupuesto',
                ),
                IconButton(onPressed: onShare, icon: const Icon(Icons.share_outlined), tooltip: 'Compartir'),
                IconButton(
                  onPressed: onSendEmail,
                  icon: const Icon(Icons.mail_outline),
                  tooltip: 'Enviar cotizacion por correo',
                ),
                if (onAttachPdf != null)
                  IconButton(
                    onPressed: onAttachPdf,
                    icon: const Icon(Icons.attach_file),
                    tooltip: quote.hasApprovalPdf ? 'Reemplazar PDF pedido' : 'Adjuntar PDF pedido',
                  ),
                if (onConclude != null)
                  IconButton(
                    onPressed: onConclude,
                    icon: const Icon(Icons.task_alt_outlined),
                    tooltip: 'Concluir cotización',
                    color: Colors.orange.shade700,
                  ),
                if (onPreviewPdf != null)
                  IconButton(
                    onPressed: onPreviewPdf,
                    icon: const Icon(Icons.visibility),
                    tooltip: 'Previsualizar PDF',
                    color: Colors.blue,
                  ),
                if (onApprove != null)
                  IconButton(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check_circle_outline),
                    tooltip: 'Aprobar',
                    color: Colors.green,
                  ),
                if (onDecline != null)
                  IconButton(
                    onPressed: onDecline,
                    icon: const Icon(Icons.cancel_outlined),
                    tooltip: 'Declinar',
                    color: Colors.red,
                  ),
                if (onReactivate != null)
                  IconButton(
                    onPressed: onReactivate,
                    icon: const Icon(Icons.undo),
                    tooltip: quote.isConcluded ? 'Reabrir cotización' : 'Reactivar cotización',
                    color: Colors.orange,
                  ),
                if (onGoToActas != null)
                  IconButton(
                    onPressed: onGoToActas,
                    icon: const Icon(Icons.assignment_outlined),
                    tooltip: 'Ir a ACTAS',
                    color: Colors.purple,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuoteMobileCard extends StatelessWidget {
  const _QuoteMobileCard({
    required this.quote,
    required this.projectName,
    required this.estimatedUsdRate,
    required this.onViewProjectDescription,
    required this.onEdit,
    required this.onShare,
    required this.onSendEmail,
    this.onAttachPdf,
    this.onPreviewPdf,
    this.onPreviewActa,
    this.onDownloadActa,
    this.onShareActa,
    this.onMarkPaid,
    this.onConclude,
    this.onApprove,
    this.onDecline,
    this.onReactivate,
    this.onGoToActas,
  });

  final QuoteRecord quote;
  final String projectName;
  final double? estimatedUsdRate;
  final VoidCallback onViewProjectDescription;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onSendEmail;
  final VoidCallback? onAttachPdf;
  final VoidCallback? onPreviewPdf;
  final VoidCallback? onPreviewActa;
  final VoidCallback? onDownloadActa;
  final VoidCallback? onShareActa;
  final VoidCallback? onMarkPaid;
  final VoidCallback? onConclude;
  final VoidCallback? onApprove;
  final VoidCallback? onDecline;
  final VoidCallback? onReactivate;
  final VoidCallback? onGoToActas;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          quote.quoteNumber,
                          style: const TextStyle(fontWeight: FontWeight.w700, color: RemaColors.primaryDark),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          projectName,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: RemaColors.onSurfaceVariant, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusBadge(status: quote.status),
                ],
              ),
              const SizedBox(height: 4),
              _DualCurrencyAmount(
                mxnLabel: _money(quote.total),
                usdLabel: _quoteUsdLabel(quote: quote, estimatedRate: estimatedUsdRate),
                compact: true,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  if (quote.isActaFinalizada || quote.isPaid) ...[
                    IconButton(
                      onPressed: onShareActa,
                      icon: const Icon(Icons.share_outlined),
                      tooltip: 'Compartir acta final',
                    ),
                    IconButton(
                      onPressed: onPreviewActa,
                      icon: const Icon(Icons.visibility),
                      tooltip: 'Previsualizar acta final',
                      color: Colors.blue,
                    ),
                    IconButton(
                      onPressed: onDownloadActa,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      tooltip: 'Descargar acta final',
                      color: Colors.deepPurple,
                    ),
                    if (quote.isActaFinalizada)
                      IconButton(
                        onPressed: onMarkPaid,
                        icon: const Icon(Icons.payments_outlined),
                        tooltip: 'Marcar como pagada',
                        color: Colors.green,
                      ),
                  ] else ...[
                    IconButton(
                      onPressed: onViewProjectDescription,
                      icon: const Icon(Icons.description_outlined),
                      tooltip: 'Ver descripcion del levantamiento',
                      color: RemaColors.primaryDark,
                    ),
                    IconButton(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: quote.isDraft ? 'Editar conceptos' : 'Ver presupuesto',
                    ),
                    IconButton(onPressed: onShare, icon: const Icon(Icons.share_outlined), tooltip: 'Compartir'),
                    IconButton(
                      onPressed: onSendEmail,
                      icon: const Icon(Icons.mail_outline),
                      tooltip: 'Enviar cotizacion por correo',
                    ),
                    if (onAttachPdf != null)
                      IconButton(
                        onPressed: onAttachPdf,
                        icon: const Icon(Icons.attach_file),
                        tooltip: quote.hasApprovalPdf ? 'Reemplazar PDF pedido' : 'Adjuntar PDF pedido',
                      ),
                    if (onConclude != null)
                      IconButton(
                        onPressed: onConclude,
                        icon: const Icon(Icons.task_alt_outlined),
                        tooltip: 'Concluir cotización',
                        color: Colors.orange,
                      ),
                    if (onPreviewPdf != null)
                      IconButton(
                        onPressed: onPreviewPdf,
                        icon: const Icon(Icons.visibility),
                        tooltip: 'Previsualizar PDF',
                        color: Colors.blue,
                      ),
                    if (onApprove != null)
                      IconButton(
                        onPressed: onApprove,
                        icon: const Icon(Icons.check_circle_outline),
                        tooltip: 'Aprobar',
                        color: Colors.green,
                      ),
                    if (onDecline != null)
                      IconButton(
                        onPressed: onDecline,
                        icon: const Icon(Icons.cancel_outlined),
                        tooltip: 'Declinar',
                        color: Colors.red,
                      ),
                    if (onReactivate != null)
                      IconButton(
                        onPressed: onReactivate,
                        icon: const Icon(Icons.undo),
                        tooltip: quote.isConcluded ? 'Reabrir cotización' : 'Reactivar cotización',
                        color: Colors.orange,
                      ),
                    if (onGoToActas != null)
                      IconButton(
                        onPressed: onGoToActas,
                        icon: const Icon(Icons.assignment_outlined),
                        tooltip: 'Ir a ACTAS',
                        color: Colors.purple,
                      ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendQuoteEmailDialog extends StatefulWidget {
  const _SendQuoteEmailDialog({
    required this.initialEmail,
    required this.quoteNumber,
    required this.projectName,
  });

  final String initialEmail;
  final String quoteNumber;
  final String projectName;

  @override
  State<_SendQuoteEmailDialog> createState() => _SendQuoteEmailDialogState();
}

class _SendQuoteEmailDialogState extends State<_SendQuoteEmailDialog> {
  late final TextEditingController _emailController =
      TextEditingController(text: widget.initialEmail);
  late final TextEditingController _noteController = TextEditingController();
  String? _emailError;

  @override
  void dispose() {
    _emailController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  bool _areEmailsValid(String value) {
    final parts = value.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return false;
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return parts.every((e) => emailRegex.hasMatch(e));
  }

  void _submit() {
    final emails = _emailController.text.trim();
    if (!_areEmailsValid(emails)) {
      setState(() => _emailError = 'Ingresa correos válidos separados por coma.');
      return;
    }
    Navigator.of(context).pop((
      email: emails.toLowerCase(),
      note: _noteController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enviar cotizacion por correo'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Folio: ${widget.quoteNumber}'),
            const SizedBox(height: 4),
            Text('Proyecto: ${widget.projectName}'),
            const SizedBox(height: 12),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Correo(s) del destinatario',
                hintText: 'cliente@ejemplo.com, otro@ejemplo.com',
                errorText: _emailError,
              ),
              onChanged: (_) {
                if (_emailError != null) {
                  setState(() => _emailError = null);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Mensaje adicional (opcional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.send_outlined),
          label: const Text('Enviar'),
        ),
      ],
    );
  }
}

class _NewQuoteResult {
  const _NewQuoteResult({
    required this.clientId,
    required this.projectName,
    required this.universeId,
    required this.projectTypeId,
  });

  final String clientId;
  final String projectName;
  final String universeId;
  final String projectTypeId;
}

class ClientOption {
  const ClientOption({required this.id, required this.name});

  final String id;
  final String name;
}

class _NewQuoteDialog extends StatefulWidget {
  const _NewQuoteDialog({
    required this.catalog,
    required this.clients,
    this.fixedClient,
  });

  final ConceptCatalogSnapshot catalog;
  final List<ClientOption> clients;
  final ClientOption? fixedClient;

  @override
  State<_NewQuoteDialog> createState() => _NewQuoteDialogState();
}

class _NewQuoteDialogState extends State<_NewQuoteDialog> {
  static const int _minimumProjectNameLength = 4;

  String? _clientId;
  String? _universeId;
  String? _projectTypeId;
  late final TextEditingController _projectNameController;
  late final TextEditingController _clientSearchController;
  String? _projectNameError;
  String? _clientError;
  String? _projectTypeError;

  @override
  void initState() {
    super.initState();
    _projectNameController = TextEditingController();
    _clientSearchController = TextEditingController(text: widget.fixedClient?.name ?? '');
    _clientId = widget.fixedClient?.id;
    if (widget.catalog.universes.isNotEmpty) {
      _universeId = widget.catalog.universes.first.id;
    }
    _projectTypeId = _normalizedProjectTypeId(
      universeId: _universeId,
      currentProjectTypeId: widget.catalog.projectTypes.isNotEmpty
          ? widget.catalog.projectTypes.first.id
          : null,
    );
  }

  @override
  void dispose() {
    _projectNameController.dispose();
    _clientSearchController.dispose();
    super.dispose();
  }

  String _normalizedProjectName(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  List<ProjectTypeCatalogItem> _compatibleProjectTypes(String? universeId) {
    if (universeId == null || universeId.trim().isEmpty) {
      return widget.catalog.projectTypes;
    }
    final compatible = widget.catalog.projectTypesForUniverse(universeId);
    return compatible.isNotEmpty ? compatible : widget.catalog.projectTypes;
  }

  String? _normalizedProjectTypeId({
    required String? universeId,
    required String? currentProjectTypeId,
  }) {
    final compatible = _compatibleProjectTypes(universeId);
    if (compatible.isEmpty) {
      return currentProjectTypeId;
    }
    if (currentProjectTypeId != null &&
        compatible.any((item) => item.id == currentProjectTypeId)) {
      return currentProjectTypeId;
    }
    return compatible.first.id;
  }

  @override
  Widget build(BuildContext context) {
    final compatibleProjectTypes = _compatibleProjectTypes(_universeId);

    return AlertDialog(
      title: const Text('Nueva cotización'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.fixedClient != null)
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Cliente'),
                child: Text(widget.fixedClient!.name),
              )
            else
              Autocomplete<ClientOption>(
                displayStringForOption: (option) => option.name,
                optionsBuilder: (textEditingValue) {
                  final query = textEditingValue.text.trim().toLowerCase();
                  if (query.isEmpty) {
                    return widget.clients;
                  }
                  return widget.clients.where(
                    (client) => client.name.toLowerCase().contains(query),
                  );
                },
                onSelected: (option) {
                  setState(() {
                    _clientId = option.id;
                    _clientError = null;
                  });
                  _clientSearchController.value = TextEditingValue(
                    text: option.name,
                    selection: TextSelection.collapsed(offset: option.name.length),
                  );
                },
                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                  if (controller.text != _clientSearchController.text) {
                    controller.value = _clientSearchController.value;
                  }
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      labelText: 'Cliente',
                      hintText: 'Busca y selecciona un cliente',
                      errorText: _clientError,
                    ),
                    onChanged: (value) {
                      _clientSearchController.value = controller.value;
                      if (_clientError != null) {
                        setState(() => _clientError = null);
                      }
                      final normalized = value.trim().toLowerCase();
                      final selected = widget.clients.where(
                        (client) => client.name.toLowerCase() == normalized,
                      );
                      setState(() {
                        _clientId = selected.isNotEmpty ? selected.first.id : null;
                      });
                    },
                    onSubmitted: (_) => onFieldSubmitted(),
                  );
                },
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _projectNameController,
              decoration: InputDecoration(
                labelText: 'Proyecto',
                hintText: 'Escribe el proyecto a realizar',
                errorText: _projectNameError,
              ),
              textCapitalization: TextCapitalization.words,
              onChanged: (_) {
                if (_projectNameError != null) {
                  setState(() => _projectNameError = null);
                }
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _universeId,
              decoration: const InputDecoration(labelText: 'Universo'),
              items: [
                for (final universe in widget.catalog.universes)
                  DropdownMenuItem(value: universe.id, child: Text(universe.name)),
              ],
              onChanged: (value) {
                setState(() {
                  _universeId = value;
                  _projectTypeId = _normalizedProjectTypeId(
                    universeId: value,
                    currentProjectTypeId: _projectTypeId,
                  );
                  _projectTypeError = null;
                });
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _projectTypeId,
              decoration: InputDecoration(
                labelText: 'Tipo de proyecto',
                errorText: _projectTypeError,
              ),
              items: [
                for (final projectType in compatibleProjectTypes)
                  DropdownMenuItem(value: projectType.id, child: Text(projectType.name)),
              ],
              onChanged: (value) => setState(() {
                _projectTypeId = value;
                _projectTypeError = null;
              }),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final projectName = _normalizedProjectName(_projectNameController.text);
            if (projectName.isEmpty) {
              setState(() => _projectNameError = 'Escribe el nombre del proyecto a realizar.');
              return;
            }
            if (projectName.length < _minimumProjectNameLength) {
              setState(
                () => _projectNameError =
                    'El nombre del proyecto debe tener al menos $_minimumProjectNameLength caracteres.',
              );
              return;
            }
            if (_clientId == null) {
              setState(() => _clientError = 'Selecciona un cliente valido de la lista.');
              return;
            }
            if (_universeId == null || _projectTypeId == null) {
              return;
            }
            if (!widget.catalog.hasTemplatesForUniverseAndProjectType(
              _universeId!,
              _projectTypeId!,
            )) {
              setState(
                () => _projectTypeError =
                    'No hay conceptos cargados para la combinacion seleccionada.',
              );
              return;
            }
            Navigator.of(context).pop(
              _NewQuoteResult(
                clientId: _clientId!,
                projectName: projectName,
                universeId: _universeId!,
                projectTypeId: _projectTypeId!,
              ),
            );
          },
          child: const Text('Crear'),
        ),
      ],
    );
  }
}

class _DualCurrencyAmount extends StatelessWidget {
  const _DualCurrencyAmount({
    required this.mxnLabel,
    required this.usdLabel,
    this.compact = false,
  });

  final String mxnLabel;
  final String? usdLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final usdStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: RemaColors.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          fontSize: compact ? 11 : 12,
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          mxnLabel,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        if (usdLabel != null)
          Text(
            usdLabel!,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: usdStyle,
          ),
      ],
    );
  }
}

String? _quoteUsdLabel({required QuoteRecord quote, required double? estimatedRate}) {
  if (quote.finalTotalUsd != null) {
    return '${quote.finalTotalUsd!.round()} USD';
  }
  if (estimatedRate == null) {
    return null;
  }
  return '${(quote.total * estimatedRate).round()} USD';
}

String _money(double value) {
  return '\$${value.toStringAsFixed(2)}';
}
