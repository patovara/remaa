import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/surveys_staff_provider.dart';
import '../data/surveys_staff_repository.dart';

class SurveysStaffPage extends ConsumerWidget {
  const SurveysStaffPage({Key? key}) : super(key: key);

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

class _QuoteExpansionTile extends StatefulWidget {
  final String quoteId;
  final List<SurveyWithQuoteContext> surveys;
  final bool isDesktop;

  const _QuoteExpansionTile({
    required this.quoteId,
    required this.surveys,
    this.isDesktop = false,
  });

  @override
  State<_QuoteExpansionTile> createState() => _QuoteExpansionTileState();
}

class _QuoteExpansionTileState extends State<_QuoteExpansionTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.surveys.isEmpty) {
      return const SizedBox.shrink();
    }

    final firstSurvey = widget.surveys.first;
    final statusColor = _getStatusColor(firstSurvey.quoteStatus);

    return Card(
      elevation: 2,
      child: ExpansionTile(
        onExpansionChanged: (value) {
          setState(() => _expanded = value);
        },
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
                color: statusColor.withOpacity(0.1),
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
                  _SurveyEntryCard(survey: survey),
              ],
            ),
          ),
        ],
      ),
    );
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

  const _SurveyEntryCard({required this.survey});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
