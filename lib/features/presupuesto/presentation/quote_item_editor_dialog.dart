import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../cotizaciones/domain/concept_generation.dart';
import '../../cotizaciones/domain/quote_models.dart';
import '../../cotizaciones/presentation/concepts_catalog_controller.dart';
import '../../cotizaciones/presentation/quotes_controller.dart';

class QuoteItemEditorResult {
  const QuoteItemEditorResult({required this.item});

  final QuoteItemRecord item;
}

class QuoteItemEditorDialog extends ConsumerStatefulWidget {
  const QuoteItemEditorDialog({
    super.key,
    required this.quote,
    required this.catalog,
    this.initialValue,
  });

  final QuoteRecord quote;
  final ConceptCatalogSnapshot catalog;
  final QuoteItemRecord? initialValue;

  @override
  ConsumerState<QuoteItemEditorDialog> createState() => _QuoteItemEditorDialogState();
}

class _QuoteItemEditorDialogState extends ConsumerState<QuoteItemEditorDialog> {
  static const List<String> _partidas = ['Muros', 'Acabados', 'Pintura'];
  static const Map<String, List<String>> _partidaKeywords = {
    'Muros': ['muro', 'tabique', 'block', 'panel', 'yeso', 'tablaroca', 'mamposteria'],
    'Acabados': ['acabado', 'azulejo', 'loseta', 'piso', 'recubrimiento', 'lambrin'],
    'Pintura': ['pintura', 'vinil', 'esmalte', 'sellador', 'impermeabilizante'],
  };

  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _unitController = TextEditingController();
  final _quantityController = TextEditingController();
  final _unitPriceController = TextEditingController();
  final NumberFormat _moneyInputFormat = NumberFormat('#,##0.##', 'en_US');

  ConceptTemplateCatalogItem? _selectedTemplate;
  final Map<String, String> _attributeSelection = {};
  GeneratedConceptResult? _preview;
  bool _manualDescriptionEdit = false;
  bool _formattingUnitPrice = false;
  String _selectedPartida = 'Muros';
  String? _selectedRecentItemId;

  List<ConceptTemplateCatalogItem> get _templates =>
      widget.catalog.templatesForUniverseAndProjectType(
        widget.quote.universeId,
        widget.quote.projectTypeId,
      );

  String get _universeLabel =>
      widget.catalog.universeById(widget.quote.universeId)?.name ?? widget.quote.universeId;

  String get _projectTypeLabel =>
      widget.catalog.projectTypeById(widget.quote.projectTypeId)?.name ?? widget.quote.projectTypeId;

  List<ProjectTypeCatalogItem> get _availableProjectTypesForUniverse =>
      widget.catalog.projectTypesForUniverse(widget.quote.universeId);

  Map<String, List<ConceptTemplateCatalogItem>> get _templatesByPartida {
    final map = {
      for (final partida in _partidas) partida: <ConceptTemplateCatalogItem>[],
    };

    for (final template in _templates) {
      final searchable = '${template.name} ${template.baseDescription}'.toLowerCase();
      String? match;
      for (final partida in _partidas) {
        final keywords = _partidaKeywords[partida] ?? const <String>[];
        final hits = keywords.any(searchable.contains);
        if (hits) {
          match = partida;
          break;
        }
      }
      final target = match ?? 'Muros';
      map[target]!.add(template);
    }

    return map;
  }

  List<ConceptTemplateCatalogItem> get _templatesForSelectedPartida {
    final scoped = _templatesByPartida[_selectedPartida] ?? const <ConceptTemplateCatalogItem>[];
    if (scoped.isNotEmpty) {
      return scoped;
    }
    return _templates;
  }

  String _missingTemplatesMessage() {
    final alternatives = [
      for (final item in _availableProjectTypesForUniverse)
        if (item.id != widget.quote.projectTypeId) item.name,
    ];

    final parts = <String>[
      'No hay conceptos disponibles para $_universeLabel + $_projectTypeLabel.',
    ];
    if (alternatives.isNotEmpty) {
      parts.add('En el catalogo este universo si tiene conceptos para: ${alternatives.join(', ')}.');
    } else {
      parts.add('Revisa que la cotizacion se haya creado con el tipo de proyecto correcto.');
    }
    return parts.join(' ');
  }

  @override
  void initState() {
    super.initState();
    final map = _templatesByPartida;
    final firstWithData = _partidas.firstWhere(
      (key) => (map[key] ?? const <ConceptTemplateCatalogItem>[]).isNotEmpty,
      orElse: () => _partidas.first,
    );
    _selectedPartida = firstWithData;

    if (_templates.isNotEmpty) {
      _selectedTemplate = _templatesForSelectedPartida.firstWhere(
        (item) => item.id == widget.initialValue?.templateId,
        orElse: () => _templatesForSelectedPartida.first,
      );
      _hydrateFromTemplate();
    }
    if (widget.initialValue != null) {
      final item = widget.initialValue!;
      _descriptionController.text = item.concept;
      _manualDescriptionEdit = true;
      _unitController.text = item.unit;
      _quantityController.text = item.quantity.toStringAsFixed(2);
      _unitPriceController.text = _formatMoneyInput(item.unitPrice);
      final attrs = item.generatedData?['attributes'];
      if (attrs is Map) {
        for (final entry in attrs.entries) {
          _attributeSelection['${entry.key}'] = '${entry.value}';
        }
      }
      _regeneratePreview();
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _unitController.dispose();
    _quantityController.dispose();
    _unitPriceController.dispose();
    super.dispose();
  }

  void _selectTemplateById(String conceptId) {
    final match = _templates.where((t) => t.id == conceptId).firstOrNull;
    if (match == null) return;

    _selectPartidaForTemplate(match);
    _selectConcept(match);
  }

  void _selectConcept(ConceptTemplateCatalogItem template) {
    setState(() {
      _selectedTemplate = template;
      _selectedRecentItemId = null;
      _manualDescriptionEdit = false;
      _attributeSelection.clear();
    });
    _hydrateFromTemplate();
  }

  void _selectPartida(String partida) {
    final scoped = _templatesByPartida[partida] ?? const <ConceptTemplateCatalogItem>[];
    setState(() {
      _selectedPartida = partida;
    });
    final currentTemplate = _selectedTemplate;
    if (scoped.isEmpty) {
      return;
    }
    if (currentTemplate == null || !scoped.any((item) => item.id == currentTemplate.id)) {
      _selectConcept(scoped.first);
    }
  }

  void _selectPartidaForTemplate(ConceptTemplateCatalogItem template) {
    for (final partida in _partidas) {
      final scoped = _templatesByPartida[partida] ?? const <ConceptTemplateCatalogItem>[];
      if (scoped.any((item) => item.id == template.id)) {
        _selectedPartida = partida;
        return;
      }
    }
    _selectedPartida = _partidas.first;
  }

  void _useRecentSuggestion(QuoteItemRecord item) {
    final template = _selectedTemplate;
    if (template == null) {
      return;
    }

    setState(() {
      _selectedRecentItemId = item.id;
      _manualDescriptionEdit = true;
    });

    _hydrateFromTemplate();

    _unitController.text = item.unit;
    _quantityController.text = item.quantity.toStringAsFixed(2);
    _unitPriceController.text = _formatMoneyInput(item.unitPrice);
    _descriptionController.text = item.concept;

    final attrs = item.generatedData?['attributes'];
    if (attrs is Map) {
      for (final entry in attrs.entries) {
        _attributeSelection['${entry.key}'] = '${entry.value}';
      }
    }

    _preview = GeneratedConceptResult(
      description: item.concept,
      generatedData: {
        ...?item.generatedData,
        'attributes': Map<String, String>.from(_attributeSelection),
      },
    );
    setState(() {});
  }

  void _createNewFromTemplate() {
    setState(() {
      _selectedRecentItemId = null;
      _manualDescriptionEdit = false;
      _attributeSelection.clear();
    });
    _hydrateFromTemplate();
  }

  void _hydrateFromTemplate() {
    final template = _selectedTemplate;
    if (template == null) {
      return;
    }

    _unitController.text = template.defaultUnit;
    _unitPriceController.text = _formatMoneyInput(template.basePrice);

    final attributes = widget.catalog.attributesForTemplate(template.id);
    for (final attribute in attributes) {
      final options = widget.catalog.optionsForAttribute(attribute.id);
      if (_attributeSelection.containsKey(attribute.name)) {
        continue;
      }
      _attributeSelection[attribute.name] = options.isNotEmpty ? options.first.value : '';
    }

    _regeneratePreview();
  }

  void _regeneratePreview() {
    final template = _selectedTemplate;
    if (template == null) {
      return;
    }
    final projectType = widget.catalog.projectTypeById(widget.quote.projectTypeId);
    final universe = widget.catalog.universeById(widget.quote.universeId);
    final closure = widget.catalog.closureById(template.closureId);
    if (projectType == null || universe == null || closure == null) {
      return;
    }

    final generator = const ConceptGenerator();
    _preview = generator.build(
      projectType: projectType.name,
      action: projectType.actionBase,
      universe: universe.name,
      concept: template.name.toLowerCase(),
      baseDescription: template.baseDescription,
      attributes: Map<String, String>.from(_attributeSelection),
      unit: _unitController.text.trim(),
      basePrice: template.basePrice,
      closure: closure.text,
    );

    if (!_manualDescriptionEdit) {
      _descriptionController.text = _preview!.description;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final template = _selectedTemplate;

    return AlertDialog(
      title: Text(widget.initialValue == null ? 'Nuevo concepto' : 'Editar concepto'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_templates.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      border: Border.all(color: Colors.red),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _missingTemplatesMessage(),
                      style: TextStyle(color: Colors.red),
                    ),
                  )
                else ...[
                  Text(
                    'Partida',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final partida in _partidas)
                        ChoiceChip(
                          label: Text(partida),
                          selected: _selectedPartida == partida,
                          onSelected: (_) => _selectPartida(partida),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _ConceptSuggestionsBar(
                    universeId: widget.quote.universeId,
                    onSelected: _selectTemplateById,
                  ),
                  DropdownButtonFormField<ConceptTemplateCatalogItem>(
                    initialValue: template,
                    decoration: const InputDecoration(labelText: 'Concepto base'),
                    isExpanded: true,
                    items: [
                      for (final item in _templatesForSelectedPartida)
                        DropdownMenuItem(
                          value: item,
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      _selectConcept(value);
                    },
                    validator: (value) => value == null ? 'Selecciona un concepto base.' : null,
                  ),
                  const SizedBox(height: 12),
                  _RecentConceptSuggestionsBar(
                    templateId: template?.id,
                    selectedItemId: _selectedRecentItemId,
                    onSelectSuggestion: _useRecentSuggestion,
                    onCreateNew: _createNewFromTemplate,
                  ),
                ],
                const SizedBox(height: 16),
                if (template != null)
                  ..._buildAttributeSelectors(template),
                TextFormField(
                  controller: _unitController,
                  decoration: const InputDecoration(
                    labelText: 'Unidad',
                    hintText: 'Ej. m2',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ingresa la unidad.';
                    }
                    return null;
                  },
                  onChanged: (_) => _regeneratePreview(),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _quantityController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Cantidad',
                          hintText: 'Ej. 1.00',
                        ),
                        validator: (value) {
                          final parsed = double.tryParse((value ?? '').trim());
                          if (parsed == null || parsed <= 0) {
                            return 'Cantidad invalida.';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _unitPriceController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Precio unitario',
                          hintText: 'Ej. 1250.00',
                        ),
                        onChanged: _onUnitPriceChanged,
                        validator: (value) {
                          final parsed = _parseMoneyInput(value ?? '');
                          if (parsed == null || parsed < 0) {
                            return 'Precio invalido.';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Descripcion final',
                    hintText: 'Describe el concepto final para la cotizacion',
                  ),
                  onChanged: (_) => _manualDescriptionEdit = true,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'La descripcion no puede ir vacia.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                if (_preview != null)
                  Text(
                    'Preview generado listo. Puedes editar la descripcion antes de guardar.',
                    style: Theme.of(context).textTheme.bodySmall,
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
          onPressed: _save,
          child: const Text('Guardar concepto'),
        ),
      ],
    );
  }

  List<Widget> _buildAttributeSelectors(ConceptTemplateCatalogItem template) {
    final attributes = widget.catalog.attributesForTemplate(template.id);
    return [
      for (final attribute in attributes) ...[
        DropdownButtonFormField<String>(
          initialValue: _attributeSelection[attribute.name],
          decoration: InputDecoration(labelText: attribute.name),
          items: [
            for (final option in widget.catalog.optionsForAttribute(attribute.id))
              DropdownMenuItem(
                value: option.value,
                child: Text(option.value),
              ),
          ],
          onChanged: (value) {
            _attributeSelection[attribute.name] = value ?? '';
            _manualDescriptionEdit = false;
            _regeneratePreview();
          },
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Selecciona ${attribute.name}.';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
      ],
    ];
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final template = _selectedTemplate;
    if (template == null) {
      return;
    }

    final quantity = double.tryParse(_quantityController.text.trim()) ?? 0;
    final unitPrice = _parseMoneyInput(_unitPriceController.text.trim()) ?? 0;
    final lineTotal = quantity * unitPrice;

    final generatedData = {
      ...?_preview?.generatedData,
      'attributes': Map<String, String>.from(_attributeSelection),
    };

    final item = QuoteItemRecord(
      id: widget.initialValue?.id ?? 'seed-item-${DateTime.now().millisecondsSinceEpoch}',
      quoteId: widget.quote.id,
      templateId: template.id,
      concept: _descriptionController.text.trim(),
      generatedData: generatedData,
      unit: _unitController.text.trim(),
      quantity: quantity,
      unitPrice: unitPrice,
      lineTotal: lineTotal,
    );

    Navigator.of(context).pop(QuoteItemEditorResult(item: item));
  }

  void _onUnitPriceChanged(String value) {
    if (_formattingUnitPrice) {
      return;
    }
    final parsed = _parseMoneyInput(value);
    if (parsed == null) {
      return;
    }
    final formatted = _formatMoneyInput(parsed);
    if (formatted == value) {
      return;
    }
    _formattingUnitPrice = true;
    _unitPriceController.value = _unitPriceController.value.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    _formattingUnitPrice = false;
  }

  String _formatMoneyInput(double value) => _moneyInputFormat.format(value);

  double? _parseMoneyInput(String raw) {
    final clean = raw.replaceAll(',', '').trim();
    if (clean.isEmpty) {
      return null;
    }
    return double.tryParse(clean);
  }
}

class _ConceptSuggestionsBar extends ConsumerWidget {
  const _ConceptSuggestionsBar({
    required this.universeId,
    required this.onSelected,
  });

  final String universeId;
  final void Function(String conceptId) onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestionsAsync = ref.watch(conceptUsageSuggestionsProvider(universeId));

    return suggestionsAsync.when(
      data: (response) {
        if (response.items.isEmpty) return const SizedBox();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '🔥 Sugeridos',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final item in response.items)
                  ActionChip(
                    label: Text(item.name),
                    onPressed: () => onSelected(item.conceptId),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        );
      },
      loading: () => const SizedBox(),
      error: (_, _) => const SizedBox(),
    );
  }
}

class _RecentConceptSuggestionsBar extends ConsumerWidget {
  const _RecentConceptSuggestionsBar({
    required this.templateId,
    required this.selectedItemId,
    required this.onSelectSuggestion,
    required this.onCreateNew,
  });

  final String? templateId;
  final String? selectedItemId;
  final void Function(QuoteItemRecord item) onSelectSuggestion;
  final VoidCallback onCreateNew;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = templateId;
    if (id == null || id.trim().isEmpty) {
      return const SizedBox();
    }

    final recentAsync = ref.watch(recentTemplateItemsProvider(id));
    return recentAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return const SizedBox();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sugerencias recientes',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  label: const Text('Crear nuevo'),
                  selected: selectedItemId == null,
                  onSelected: (_) => onCreateNew(),
                ),
                for (final item in items)
                  ChoiceChip(
                    label: Text(
                      _shortLabel(item.concept),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    selected: selectedItemId == item.id,
                    onSelected: (_) => onSelectSuggestion(item),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        );
      },
      loading: () => const SizedBox(),
      error: (_, _) => const SizedBox(),
    );
  }

  String _shortLabel(String value) {
    final clean = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.length <= 42) {
      return clean;
    }
    return '${clean.substring(0, 42)}...';
  }
}
