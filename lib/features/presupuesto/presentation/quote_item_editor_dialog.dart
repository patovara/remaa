import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../cotizaciones/domain/concept_generation.dart';
import '../../cotizaciones/domain/quote_models.dart';

class QuoteItemEditorResult {
  const QuoteItemEditorResult({required this.item});

  final QuoteItemRecord item;
}

class QuoteItemEditorDialog extends StatefulWidget {
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
  State<QuoteItemEditorDialog> createState() => _QuoteItemEditorDialogState();
}

class _QuoteItemEditorDialogState extends State<QuoteItemEditorDialog> {
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

  List<ConceptTemplateCatalogItem> get _templates =>
      widget.catalog.templatesForUniverseAndProjectType(
        widget.quote.universeId,
        widget.quote.projectTypeId,
      );

  @override
  void initState() {
    super.initState();
    if (_templates.isNotEmpty) {
      _selectedTemplate = _templates.firstWhere(
        (item) => item.id == widget.initialValue?.templateId,
        orElse: () => _templates.first,
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
      content: SizedBox(
        width: 760,
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
                    child: const Text(
                      'No hay conceptos disponibles para este universo y tipo de proyecto. Agrega templates al catálogo.',
                      style: TextStyle(color: Colors.red),
                    ),
                  )
                else
                  DropdownButtonFormField<ConceptTemplateCatalogItem>(
                    initialValue: template,
                    decoration: const InputDecoration(labelText: 'Concepto base'),
                    items: [
                      for (final item in _templates)
                        DropdownMenuItem(
                          value: item,
                          child: Text(item.name),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      _manualDescriptionEdit = false;
                      _selectedTemplate = value;
                      _attributeSelection.clear();
                      _hydrateFromTemplate();
                    },
                    validator: (value) => value == null ? 'Selecciona un concepto base.' : null,
                  ),
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
