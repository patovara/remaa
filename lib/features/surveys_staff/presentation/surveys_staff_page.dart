import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/image_optimizer.dart';
import '../data/surveys_staff_provider.dart';
import '../data/surveys_staff_repository.dart';
import '../../levantamiento/presentation/levantamiento_state.dart';
import '../../cotizaciones/domain/quote_models.dart';

class SurveysStaffPage extends ConsumerWidget {
  const SurveysStaffPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final surveysAsync = ref.watch(surveysByStaffProvider);
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Levantamientos'),
      ),
      body: surveysAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (err, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('Error: $err'),
            ],
          ),
        ),
        data: (surveys) {
          if (surveys.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.assignment_turned_in, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'No hay surveys capturadas',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Inicia un levantamiento en la sección "Levantamiento"',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      context.go('/levantamiento');
                    },
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Ir a Levantamiento'),
                  ),
                ],
              ),
            );
          }

          // Group surveys by quote
          final groupedByQuote = <String, List<SurveyWithQuoteContext>>{};
          for (final survey in surveys) {
            final key = survey.quoteId;
            groupedByQuote.putIfAbsent(key, () => []).add(survey);
          }

          return isMobile
              ? _MobileSurveysList(grouped: groupedByQuote)
              : _DesktopSurveysView(grouped: groupedByQuote);
        },
      ),
    );
  }
}

class _MobileSurveysList extends StatelessWidget {
  final Map<String, List<SurveyWithQuoteContext>> grouped;

  const _MobileSurveysList({required this.grouped});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        for (final quoteId in grouped.keys)
          _QuoteExpansionTile(
            quoteId: quoteId,
            surveys: grouped[quoteId] ?? [],
          ),
      ],
    );
  }
}

class _DesktopSurveysView extends StatelessWidget {
  final Map<String, List<SurveyWithQuoteContext>> grouped;

  const _DesktopSurveysView({required this.grouped});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (final quoteId in grouped.keys)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _QuoteExpansionTile(
                  quoteId: quoteId,
                  surveys: grouped[quoteId] ?? [],
                  isDesktop: true,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _QuoteExpansionTile extends ConsumerStatefulWidget {
  final String quoteId;
  final List<SurveyWithQuoteContext> surveys;
  final bool isDesktop;

  const _QuoteExpansionTile({
    required this.quoteId,
    required this.surveys,
    this.isDesktop = false,
  });

  @override
  ConsumerState<_QuoteExpansionTile> createState() => _QuoteExpansionTileState();
}

class _QuoteExpansionTileState extends ConsumerState<_QuoteExpansionTile> {
  @override
  Widget build(BuildContext context) {
    if (widget.surveys.isEmpty) {
      return const SizedBox.shrink();
    }

    final firstSurvey = widget.surveys.first;
    final statusColor = _getStatusColor(firstSurvey.quoteStatus);
    final isDraft = firstSurvey.quoteStatus.toLowerCase() == 'draft';

    return Card(
      elevation: 2,
      child: ExpansionTile(
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Folio: ${firstSurvey.quoteNumber}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    firstSurvey.clientName,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                firstSurvey.quoteStatus.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
            ),
            if (isDraft) ...[
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => _openEditSurveyDialog(firstSurvey),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Editar'),
              ),
            ],
          ],
        ),
        subtitle: Text(
          'Total: \$${firstSurvey.quoteTotal.toStringAsFixed(2)} | ${widget.surveys.length} levantamiento${widget.surveys.length == 1 ? '' : 's'}',
          style: const TextStyle(fontSize: 11),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Project info header
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Proyecto: ${firstSurvey.projectName}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      if (firstSurvey.projectCode.isNotEmpty)
                        Text(
                          'Código: ${firstSurvey.projectCode}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      if (firstSurvey.projectDescription != null &&
                          firstSurvey.projectDescription!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            firstSurvey.projectDescription!,
                            style: const TextStyle(fontSize: 11),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Surveys list
                const Text(
                  'Levantamientos',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                for (final survey in widget.surveys)
                  _SurveyEntryCard(
                    survey: survey,
                    onEdit: survey.quoteStatus.toLowerCase() == 'draft'
                        ? () => _openEditSurveyDialog(survey)
                        : null,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openEditSurveyDialog(SurveyWithQuoteContext survey) async {
    if (survey.quoteStatus.toLowerCase() != 'draft') {
      return;
    }

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _SurveyEditDialog(survey: survey),
    );

    if (!mounted || saved != true) {
      return;
    }

    ref.invalidate(surveysByStaffProvider);
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'draft':
        return Colors.grey;
      case 'approved':
        return Colors.green;
      case 'concluded':
        return Colors.blue;
      case 'paid':
        return Colors.teal;
      default:
        return Colors.orange;
    }
  }
}

class _SurveyEntryCard extends StatelessWidget {
  final SurveyWithQuoteContext survey;
  final VoidCallback? onEdit;

  const _SurveyEntryCard({required this.survey, this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (onEdit != null)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Editar levantamiento',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                ),
              ),
            // Description
            if (survey.description.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Descripción',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    survey.description,
                    style: const TextStyle(fontSize: 12),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            // Evidence section
            if (survey.evidencePaths.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Fotos',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: survey.evidencePaths.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _EvidenceThumbnail(
                            path: survey.evidencePaths[index],
                            onTap: () {
                              _showEvidenceCarousel(context, survey.evidencePaths, index);
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            // Metadata
            const SizedBox(height: 8),
            Text(
              'Capturado: ${_formatDate(survey.createdAt)}',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  void _showEvidenceCarousel(BuildContext context, List<String> paths, int initialIndex) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: _EvidenceCarouselDialog(evidencePaths: paths, initialIndex: initialIndex),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _SurveyEditDialog extends ConsumerStatefulWidget {
  const _SurveyEditDialog({required this.survey});

  final SurveyWithQuoteContext survey;

  @override
  ConsumerState<_SurveyEditDialog> createState() => _SurveyEditDialogState();
}

class _SurveyEditDialogState extends ConsumerState<_SurveyEditDialog> {
  final _repository = SurveysStaffRepository();
  late final TextEditingController _projectNameController;
  late final TextEditingController _descriptionController;
  final List<_EditablePhotoItem> _photos = [];
  bool _isDirty = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _projectNameController = TextEditingController(text: widget.survey.projectName);
    _descriptionController = TextEditingController(text: widget.survey.description);
    _projectNameController.addListener(_markDirty);
    _descriptionController.addListener(_markDirty);
    _photos.addAll([
      for (final photo in widget.survey.evidenceMetadata)
        _EditablePhotoItem.existing(
          path: (photo['object_path'] as String? ?? '').trim(),
          name: (photo['original_name'] as String? ?? '').trim().isNotEmpty
              ? (photo['original_name'] as String).trim()
              : (photo['object_path'] as String? ?? 'foto.jpg'),
          sizeBytes: (photo['file_size_bytes'] as num?)?.toInt() ?? 0,
          mimeType: photo['mime_type'] as String?,
          sortOrder: (photo['sort_order'] as num?)?.toInt() ?? 0,
        ),
    ]);
    _photos.removeWhere((item) => item.path.trim().isEmpty);
    _photos.sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
  }

  @override
  void dispose() {
    _projectNameController.removeListener(_markDirty);
    _descriptionController.removeListener(_markDirty);
    _projectNameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (_isDirty) {
      return;
    }
    setState(() => _isDirty = true);
  }

  Future<void> _addPhotos() async {
    if (_isSaving) {
      return;
    }

    final remaining = 2 - _photos.length;
    if (remaining <= 0) {
      if (mounted) {
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Límite alcanzado'),
            content: const Text('Solo se permiten 2 fotos por levantamiento.'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
      }
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );

    if (!mounted || result == null || result.files.isEmpty) {
      return;
    }

    final accepted = result.files.take(remaining).toList();
    final items = <_EditablePhotoItem>[];
    for (final file in accepted) {
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        continue;
      }
      try {
        final optimized = await optimizeImageForDocument(
          inputBytes: bytes,
          fileName: file.name,
          profile: ImageOptimizationProfile.gridDocument,
        );
        items.add(
          _EditablePhotoItem.newPhoto(
            name: optimized.fileName,
            bytes: optimized.bytes,
            sizeBytes: optimized.bytes.length,
            mimeType: optimized.mimeType,
          ),
        );
      } on ImageOptimizationException catch (error) {
        if (mounted) {
          showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('No se pudo agregar la foto'),
              content: Text('${file.name}: ${error.message}'),
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
    }

    if (items.isEmpty) {
      return;
    }

    setState(() {
      _photos.addAll(items);
      _isDirty = true;
    });
  }

  void _removePhoto(_EditablePhotoItem item) {
    setState(() {
      _photos.remove(item);
      _isDirty = true;
    });
  }

  Future<void> _requestClose() async {
    if (_isSaving) {
      return;
    }

    if (!_isDirty) {
      if (mounted) {
        Navigator.of(context).pop(false);
      }
      return;
    }

    final discard = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Salir sin guardar'),
        content: const Text('Hay cambios sin guardar. ¿Deseas salir sin guardar los cambios?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Salir sin guardar'),
          ),
        ],
      ),
    );

    if (discard == true && mounted) {
      Navigator.of(context).pop(false);
    }
  }

  Future<void> _saveChanges() async {
    if (_isSaving) {
      return;
    }

    final projectName = _projectNameController.text.trim();
    if (projectName.isEmpty) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Falta información'),
          content: const Text('El título visible del proyecto no puede quedar vacío.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
      return;
    }

    final retainedPhotos = _photos.where((item) => item.isExisting).toList();
    final newPhotos = _photos.where((item) => !item.isExisting).toList();
    if (retainedPhotos.length + newPhotos.length > 2) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Límite de fotos'),
          content: const Text('Solo se permiten hasta 2 fotos por levantamiento.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final retainedPaths = retainedPhotos
          .map((item) => item.path.trim())
          .where((path) => path.isNotEmpty)
          .toList();
      final retainedMeta = [
        for (final meta in widget.survey.evidenceMetadata)
          if (meta['object_path'] is String && retainedPaths.contains((meta['object_path'] as String).trim()))
            meta,
      ];
      final newInputs = [
        for (final item in newPhotos)
          if (item.bytes != null && item.bytes!.isNotEmpty)
            SurveyEvidenceInput(
              bytes: item.bytes!,
              originalName: item.name,
              fileSizeBytes: item.sizeBytes,
              mimeType: item.mimeType,
            ),
      ];

      final updated = await _repository.updateSurveyEntry(
        survey: widget.survey,
        projectName: projectName,
        description: _descriptionController.text.trim(),
        retainedEvidenceMetadata: retainedMeta,
        retainedEvidencePaths: retainedPaths,
        newEvidenceInputs: newInputs,
      );

      if (!mounted) {
        return;
      }

      final active = ref.read(activeLevantamientoProvider);
      if (active != null && active.isActive &&
          (active.quoteId == widget.survey.quoteId || active.projectId == widget.survey.projectId)) {
        final evidencePreviewList = <Uint8List>[
          for (final item in retainedPhotos)
            if (item.isExisting)
              await _repository.fetchSurveyImagePreview(item.path).then((bytes) => bytes ?? Uint8List(0)),
          for (final item in newPhotos)
            if (item.bytes != null && item.bytes!.isNotEmpty) item.bytes!,
        ].where((bytes) => bytes.isNotEmpty).toList();

        ref.read(activeLevantamientoProvider.notifier).updateSnapshot(
              projectName: updated.projectName,
            );
        ref.read(activeLevantamientoProvider.notifier).updateEntry(
              widget.survey.surveyId,
              SurveyEntryRecord(
                id: updated.surveyId,
                projectId: updated.projectId,
                quoteId: updated.quoteId,
                description: updated.description,
                evidencePaths: updated.evidencePaths,
                evidencePreviewList: evidencePreviewList,
                evidenceMetadata: [
                  for (final meta in updated.evidenceMetadata)
                    SurveyEvidenceMeta(
                      objectPath: meta['object_path'] as String? ?? '',
                      originalName: meta['original_name'] as String? ?? '',
                      fileSizeBytes: (meta['file_size_bytes'] as num?)?.toInt() ?? 0,
                      sortOrder: (meta['sort_order'] as num?)?.toInt() ?? 0,
                      mimeType: meta['mime_type'] as String?,
                      widthPx: (meta['width_px'] as num?)?.toInt(),
                      heightPx: (meta['height_px'] as num?)?.toInt(),
                      takenAt: meta['taken_at'] == null ? null : DateTime.tryParse(meta['taken_at'].toString()),
                    ),
                ],
                createdAt: updated.createdAt,
              ),
            );
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('No se pudo guardar'),
            content: Text('$error'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalPhotos = _photos.length;
    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 44),
                      child: Text(
                        'Editar levantamiento',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _projectNameController,
                      decoration: const InputDecoration(
                        labelText: 'Título visible del proyecto',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _descriptionController,
                      minLines: 4,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        labelText: 'Descripción',
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Fotos ($totalPhotos/2)',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: totalPhotos >= 2 ? null : _addPhotos,
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: const Text('Agregar fotos'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_photos.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Aun no hay fotos cargadas en este levantamiento.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      )
                    else
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final item in _photos)
                            _EditablePhotoTile(
                              item: item,
                              onRemove: _isSaving ? null : () => _removePhoto(item),
                              repository: _repository,
                            ),
                        ],
                      ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        FilledButton.icon(
                          onPressed: _isSaving ? null : _saveChanges,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(_isSaving ? 'Guardando...' : 'Guardar cambios'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  tooltip: 'Cerrar',
                  onPressed: _isSaving ? null : _requestClose,
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditablePhotoItem {
  const _EditablePhotoItem.existing({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.mimeType,
    required this.sortOrder,
  })  : bytes = null,
        isExisting = true;

  const _EditablePhotoItem.newPhoto({
    required this.name,
    required this.bytes,
    required this.sizeBytes,
    required this.mimeType,
  })  : path = '',
        sortOrder = 0,
        isExisting = false;

  final String path;
  final String name;
  final Uint8List? bytes;
  final int sizeBytes;
  final String? mimeType;
  final int sortOrder;
  final bool isExisting;
}

class _EditablePhotoTile extends StatefulWidget {
  const _EditablePhotoTile({
    required this.item,
    required this.onRemove,
    required this.repository,
  });

  final _EditablePhotoItem item;
  final VoidCallback? onRemove;
  final SurveysStaffRepository repository;

  @override
  State<_EditablePhotoTile> createState() => _EditablePhotoTileState();
}

class _EditablePhotoTileState extends State<_EditablePhotoTile> {
  late final Future<Uint8List?> _imageFuture;

  @override
  void initState() {
    super.initState();
    _imageFuture = widget.item.isExisting
        ? widget.repository.fetchSurveyImagePreview(widget.item.path)
        : Future<Uint8List?>.value(widget.item.bytes);
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.item.isExisting
        ? FutureBuilder<Uint8List?>(
            future: _imageFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _photoPlaceholder(context);
              }
              final bytes = snapshot.data;
              if (bytes != null && bytes.isNotEmpty) {
                return Image.memory(bytes, fit: BoxFit.cover);
              }
            : Image.memory(widget.item.bytes!, fit: BoxFit.cover);
            },
          )
        : Image.memory(item.bytes!, fit: BoxFit.cover);

    return SizedBox(
      width: 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(width: 160, height: 120, child: child),
              ),
              if (widget.onRemove != null)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: IconButton(
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                      onPressed: widget.onRemove,
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            widget.item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _photoPlaceholder(BuildContext context, {IconData icon = Icons.image_outlined}) {
    return Container(
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.grey.shade600),
    );
  }
}

class _EvidenceThumbnail extends StatefulWidget {
  final String path;
  final VoidCallback onTap;

  const _EvidenceThumbnail({required this.path, required this.onTap});

  @override
  State<_EvidenceThumbnail> createState() => _EvidenceThumbnailState();
}

class _EvidenceThumbnailState extends State<_EvidenceThumbnail> {
  late Future<Uint8List?> _imageFuture;

  @override
  void initState() {
    super.initState();
    _imageFuture = SurveysStaffRepository().fetchSurveyImagePreview(widget.path);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: FutureBuilder<Uint8List?>(
          future: _imageFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(
                width: 100,
                height: 100,
                color: Colors.grey[200],
                child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator())),
              );
            }
            if (snapshot.data != null) {
              return Image.memory(
                snapshot.data!,
                width: 100,
                height: 100,
                fit: BoxFit.cover,
              );
            }
            return Container(
              width: 100,
              height: 100,
              color: Colors.grey[300],
              child: const Center(child: Icon(Icons.image_not_supported)),
            );
          },
        ),
      ),
    );
  }
}

class _EvidenceCarouselDialog extends ConsumerStatefulWidget {
  final List<String> evidencePaths;
  final int initialIndex;

  const _EvidenceCarouselDialog({
    required this.evidencePaths,
    required this.initialIndex,
  });

  @override
  ConsumerState<_EvidenceCarouselDialog> createState() => _EvidenceCarouselDialogState();
}

class _EvidenceCarouselDialogState extends ConsumerState<_EvidenceCarouselDialog> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    
    return Container(
      constraints: BoxConstraints(
        maxWidth: isMobile ? MediaQuery.of(context).size.width * 0.9 : 600,
        maxHeight: isMobile ? MediaQuery.of(context).size.height * 0.8 : 600,
      ),
      child: Column(
        children: [
          // Header with close button
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Fotos Capturadas',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                if (isMobile)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
              ],
            ),
          ),
          // Carousel with images
          Expanded(
            child: Stack(
              children: [
                PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() => _currentIndex = index);
                  },
                  itemCount: widget.evidencePaths.length,
                  itemBuilder: (context, index) {
                    return _ImageViewerItem(path: widget.evidencePaths[index]);
                  },
                ),
                // Desktop navigation arrows
                if (!isMobile && widget.evidencePaths.length > 1)
                  Positioned(
                    left: 8,
                    top: 50,
                    child: _currentIndex > 0
                        ? FloatingActionButton.small(
                            onPressed: () {
                              _pageController.previousPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            },
                            child: const Icon(Icons.chevron_left),
                          )
                        : const SizedBox.shrink(),
                  ),
                if (!isMobile && widget.evidencePaths.length > 1)
                  Positioned(
                    right: 8,
                    top: 50,
                    child: _currentIndex < widget.evidencePaths.length - 1
                        ? FloatingActionButton.small(
                            onPressed: () {
                              _pageController.nextPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            },
                            child: const Icon(Icons.chevron_right),
                          )
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
          // Footer with counter
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Foto ${_currentIndex + 1} de ${widget.evidencePaths.length}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (!isMobile)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageViewerItem extends ConsumerWidget {
  final String path;

  const _ImageViewerItem({required this.path});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageFuture = SurveysStaffRepository().fetchSurveyImagePreview(path);
    
    return FutureBuilder<Uint8List?>(
      future: imageFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data != null) {
          return InteractiveViewer(
            child: Image.memory(
              snapshot.data!,
              fit: BoxFit.contain,
            ),
          );
        }
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [Icon(Icons.error), SizedBox(height: 8), Text('Error loading image')],
          ),
        );
      },
    );
  }
}
