import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../../../core/config/env.dart';
import '../../../core/config/supabase_bootstrap.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/utils/client_input_rules.dart';
import '../../../core/theme/rema_colors.dart';
import '../../../core/utils/rema_feedback.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/rema_panels.dart';
import '../../clientes/data/client_metadata_repository.dart';

class NuevoClientePage extends StatefulWidget {
  const NuevoClientePage({super.key, this.returnTo});

  final String? returnTo;

  @override
  State<NuevoClientePage> createState() => _NuevoClientePageState();
}

class _NuevoClientePageState extends State<NuevoClientePage> {
  String? _businessNameError;
  String? _contactNameError;
  String? _rfcError;
  String? _phoneError;
  String? _emailError;
  String? _addressError;
  final _metadataRepository = ClientMetadataRepository();
  final _businessNameController = TextEditingController();
  final _nameController = TextEditingController();
  final _rfcController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _stateController = TextEditingController();
  final _cityController = TextEditingController();

  final List<_ClientDocument> _documents = [];
  _CountryDialCode _selectedCountry = _countryDialCodes.first;
  List<String> _sectorLabels = ClientMetadataRepository.defaultSectorLabels;
  String? _selectedSector;
  Uint8List? _logoBytes;
  String? _logoName;

  @override
  void initState() {
    super.initState();
    _loadSectorLabels();
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _nameController.dispose();
    _rfcController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _stateController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  List<String> get _availableCities {
    final selectedState = _stateController.text.trim();
    if (selectedState.isEmpty) {
      return const <String>[];
    }
    return _mexicoStatesAndCities[selectedState] ?? const <String>[];
  }

  Future<void> _loadSectorLabels() async {
    final labels = await _metadataRepository.fetchSectorLabels();
    if (!mounted) {
      return;
    }
    setState(() {
      _sectorLabels = labels;
      _selectedSector ??= labels.isNotEmpty ? labels.first : null;
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
          decoration: const InputDecoration(
            hintText: 'Ejemplo: INDUSTRIAL',
          ),
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

    final normalized = _metadataRepository.normalizeSectorLabel(created ?? '');
    if (normalized.isEmpty) {
      return;
    }

    await _metadataRepository.ensureSectorLabel(normalized);
    if (!mounted) {
      return;
    }
    setState(() {
      if (!_sectorLabels.contains(normalized)) {
        _sectorLabels = [..._sectorLabels, normalized]..sort();
      }
      _selectedSector = normalized;
    });
  }

  String _composedLocation() {
    final state = _stateController.text.trim();
    final city = _cityController.text.trim();
    if (state.isEmpty && city.isEmpty) {
      return '';
    }
    if (state.isEmpty) {
      return city;
    }
    if (city.isEmpty) {
      return state;
    }
    return '$state, $city';
  }

  bool _validateClientInput() {
    final businessName = _businessNameController.text.trim();
    final contactName = _nameController.text.trim();
    final rfc = _rfcController.text.trim().toUpperCase();
    final phoneDigits = _phoneController.text.trim();
    final email = ClientInputRules.normalizeEmail(_emailController.text);
    final address = _addressController.text.trim();

    String? businessNameError;
    String? contactNameError;
    String? rfcError;
    String? phoneError;
    String? emailError;
    String? addressError;

    if (businessName.length < ClientInputRules.minTextLength) {
      businessNameError = 'La razon social debe tener al menos ${ClientInputRules.minTextLength} caracteres.';
    } else if (businessName.length > ClientInputRules.maxTextLength) {
      businessNameError = 'La razon social no puede superar ${ClientInputRules.maxTextLength} caracteres.';
    }

    if (contactName.isNotEmpty && !ClientInputRules.isValidTextOnly(contactName)) {
      contactNameError = ClientInputRules.textOnlyErrorMessage(fieldLabel: 'nombre de contacto');
    }

    if (!ClientInputRules.isValidRfc(rfc)) {
      rfcError = ClientInputRules.rfcErrorMessage();
    }

    if (phoneDigits.isEmpty) {
      phoneError = ClientInputRules.phoneRequiredMessage(fieldLabel: 'telefono de contacto');
    } else if (_selectedCountry.dialCode == '+52' && phoneDigits.length != 10) {
      phoneError = ClientInputRules.mexicoPhoneExactErrorMessage();
    } else if (phoneDigits.length > _selectedCountry.maxDigits) {
      phoneError = ClientInputRules.phoneMaxDigitsErrorMessage(
        countryName: _selectedCountry.name,
        maxDigits: _selectedCountry.maxDigits,
      );
    }

    if (!ClientInputRules.isValidEmail(email)) {
      emailError = ClientInputRules.emailErrorMessage();
    }

    if (address.isNotEmpty && !ClientInputRules.isValidAddress(address)) {
      addressError = ClientInputRules.addressErrorMessage();
    }

    setState(() {
      _businessNameError = businessNameError;
      _contactNameError = contactNameError;
      _rfcError = rfcError;
      _phoneError = phoneError;
      _emailError = emailError;
      _addressError = addressError;
    });

    return businessNameError == null &&
        contactNameError == null &&
        rfcError == null &&
        phoneError == null &&
        emailError == null &&
        addressError == null;
  }

  Future<void> _pickDocuments() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
    );

    if (!mounted || result == null || result.files.isEmpty) {
      return;
    }

    setState(() {
      _documents.addAll(
        result.files.map(
          (file) => _ClientDocument(
            name: file.name,
            size: file.size,
            bytes: file.bytes,
          ),
        ),
      );
    });

    showRemaMessage(context, 'Se agregaron ${result.files.length} documentos al expediente.');
  }

  void _removeDocument(_ClientDocument document) {
    setState(() => _documents.remove(document));
    showRemaMessage(context, 'Se elimino ${document.name}.');
  }

  Future<void> _saveClient() async {
    if (!_validateClientInput()) {
      return;
    }

    final normalizedSector = _metadataRepository.normalizeSectorLabel(_selectedSector ?? '');
    if (normalizedSector.isEmpty) {
      showRemaMessage(context, 'Selecciona un sector para el cliente.');
      return;
    }

    final client = SupabaseBootstrap.client;
    if (client == null) {
      showRemaMessage(
        context,
        'No hay conexion activa con Supabase. Revisa el .env local.',
      );
      return;
    }

    try {
      final businessName = _businessNameController.text.trim().toUpperCase();
      final contactName = ClientInputRules.sanitizeTextOnly(_nameController.text);
      final rfc = _rfcController.text.trim().toUpperCase();
      final phoneDigits = _phoneController.text.trim();
      final email = ClientInputRules.normalizeEmail(_emailController.text);
      final phone = ClientInputRules.toE164Mx(
            '${_selectedCountry.dialCode}$phoneDigits',
          ) ??
          '${_selectedCountry.dialCode}$phoneDigits';

      await _metadataRepository.ensureSectorLabel(normalizedSector);

      final basePayload = <String, Object?>{
        'business_name': businessName,
        'contact_name': contactName,
        'rfc': rfc,
        'phone': phone,
        'email': email,
        'address_line': _addressController.text.trim(),
        'city': _composedLocation(),
        'sector_label': normalizedSector,
      };
      AppLogger.info('client_create_started', data: {
        'supabase_url': Env.supabaseUrl,
        'business_name': businessName,
        'has_contact_name': contactName.isNotEmpty,
        'has_sector_label': normalizedSector.isNotEmpty,
      });
      final inserted = Map<String, dynamic>.from(
        await client.from('clients').insert(basePayload).select('id').single() as Map,
      );

      final clientId = inserted['id'] as String?;
      AppLogger.info('client_create_succeeded', data: {
        'supabase_url': Env.supabaseUrl,
        'client_id': clientId,
        'business_name': businessName,
      });
      if (clientId != null && _logoBytes != null && _logoName != null) {
        final logoPath = await _metadataRepository.uploadLogo(
          clientId: clientId,
          bytes: _logoBytes!,
          fileName: _logoName!,
        );
        if (logoPath != null) {
          await client.from('clients').update({
            'logo_path': logoPath,
            'logo_mime_type': _mimeFromName(_logoName!),
          }).eq('id', clientId);
        }
      }
      if (clientId != null && _documents.isNotEmpty) {
        await _uploadDocuments(client, clientId);
      }

      if (!mounted) {
        return;
      }
      if (clientId != null && clientId.isNotEmpty) {
        final returnTo = widget.returnTo?.trim();
        if (returnTo == 'pop') {
          context.pop(clientId);
          return;
        }
        if (returnTo != null && returnTo.isNotEmpty) {
          context.go('$returnTo?clientId=$clientId');
          return;
        }
        context.go('/clientes/$clientId');
        return;
      }
      showRemaMessage(context, 'Cliente creado correctamente.');
    } catch (error) {
      AppLogger.error('client_create_failed', data: {
        'supabase_url': Env.supabaseUrl,
        'error': error.toString(),
      });
      if (!mounted) {
        return;
      }
      final dbMsg = ClientInputRules.mapDbError(error.toString());
      showRemaMessage(
        context,
        dbMsg ?? 'No se pudo guardar el cliente. Revisa los datos e intenta de nuevo.',
      );
    }
  }


  Future<void> _uploadDocuments(dynamic supabase, String clientId) async {
    for (final doc in _documents) {
      final bytes = doc.bytes;
      if (bytes == null || bytes.isEmpty) {
        continue;
      }
      try {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final safeName = doc.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final objectPath = '$clientId/${timestamp}_$safeName';
        final mime = _mimeFromName(doc.name);

        await supabase.storage.from('client-documents').uploadBinary(
          objectPath,
          bytes,
          fileOptions: FileOptions(contentType: mime, upsert: false),
        );

        await supabase.from('documents').insert({
          'client_id': clientId,
          'bucket_name': 'client-documents',
          'object_path': objectPath,
          'mime_type': mime,
          'file_size_bytes': doc.size,
          'original_name': doc.name,
        });
      } catch (_) {
        // Continue uploading remaining documents even if one fails
      }
    }
  }

  String _mimeFromName(String name) {
    final ext = name.toLowerCase().split('.').last;
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      default:
        return 'application/octet-stream';
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'Nuevo Cliente',
      subtitle: 'Registro de expediente comercial y documental.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 1080;
          final formPanel = _ClientFormPanel(
            businessNameController: _businessNameController,
            businessNameError: _businessNameError,
            onBusinessNameChanged: (_) {
              if (_businessNameError != null) {
                setState(() => _businessNameError = null);
              }
            },
            nameController: _nameController,
            contactNameError: _contactNameError,
            onContactNameChanged: (_) {
              if (_contactNameError != null) {
                setState(() => _contactNameError = null);
              }
            },
            rfcController: _rfcController,
            rfcError: _rfcError,
            onRfcChanged: (_) {
              if (_rfcError != null) {
                setState(() => _rfcError = null);
              }
            },
            phoneController: _phoneController,
            phoneError: _phoneError,
            onPhoneChanged: (_) {
              if (_phoneError != null) {
                setState(() => _phoneError = null);
              }
            },
            emailController: _emailController,
            emailError: _emailError,
            onEmailChanged: (_) {
              if (_emailError != null) {
                setState(() => _emailError = null);
              }
            },
            addressController: _addressController,
            addressError: _addressError,
            onAddressChanged: (_) {
              if (_addressError != null) {
                setState(() => _addressError = null);
              }
            },
            stateController: _stateController,
            cityController: _cityController,
            selectedCountry: _selectedCountry,
            countries: _countryDialCodes,
            onCountryChanged: (country) {
              setState(() {
                _selectedCountry = country;
                if (_phoneController.text.length > country.maxDigits) {
                  _phoneController.text = _phoneController.text.substring(0, country.maxDigits);
                }
              });
            },
            availableCities: _availableCities,
            onStateChanged: (state) {
              final catalogCities = _mexicoStatesAndCities[state] ?? const <String>[];
              if (!catalogCities.contains(_cityController.text.trim())) {
                _cityController.clear();
              }
            },
            sectorLabels: _sectorLabels,
            selectedSector: _selectedSector,
            onSectorChanged: (value) => setState(() => _selectedSector = value),
            onAddSector: _addSector,
          );
          final docsPanel = _DocumentsPanel(
            documents: _documents,
            onPickDocuments: _pickDocuments,
            onRemoveDocument: _removeDocument,
          );
          final sidebar = _ClientSidebar(
            onSave: () => _saveClient(),
            onCancel: () => context.go('/clientes'),
            logoBytes: _logoBytes,
            logoName: _logoName,
            onPickLogo: _pickLogo,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 7,
                      child: Column(
                        children: [
                          formPanel,
                          const SizedBox(height: 24),
                          docsPanel,
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(flex: 5, child: sidebar),
                  ],
                )
              else ...[
                formPanel,
                const SizedBox(height: 20),
                docsPanel,
                const SizedBox(height: 20),
                sidebar,
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ClientFormPanel extends StatelessWidget {
  const _ClientFormPanel({
    required this.businessNameController,
    required this.businessNameError,
    required this.onBusinessNameChanged,
    required this.nameController,
    required this.contactNameError,
    required this.onContactNameChanged,
    required this.rfcController,
    required this.rfcError,
    required this.onRfcChanged,
    required this.phoneController,
    required this.phoneError,
    required this.onPhoneChanged,
    required this.emailController,
    required this.emailError,
    required this.onEmailChanged,
    required this.addressController,
    required this.addressError,
    required this.onAddressChanged,
    required this.stateController,
    required this.cityController,
    required this.selectedCountry,
    required this.countries,
    required this.onCountryChanged,
    required this.availableCities,
    required this.onStateChanged,
    required this.sectorLabels,
    required this.selectedSector,
    required this.onSectorChanged,
    required this.onAddSector,
  });

  final TextEditingController businessNameController;
  final String? businessNameError;
  final ValueChanged<String> onBusinessNameChanged;
  final TextEditingController nameController;
  final String? contactNameError;
  final ValueChanged<String> onContactNameChanged;
  final TextEditingController rfcController;
  final String? rfcError;
  final ValueChanged<String> onRfcChanged;
  final TextEditingController phoneController;
  final String? phoneError;
  final ValueChanged<String> onPhoneChanged;
  final TextEditingController emailController;
  final String? emailError;
  final ValueChanged<String> onEmailChanged;
  final TextEditingController addressController;
  final String? addressError;
  final ValueChanged<String> onAddressChanged;
  final TextEditingController stateController;
  final TextEditingController cityController;
  final _CountryDialCode selectedCountry;
  final List<_CountryDialCode> countries;
  final ValueChanged<_CountryDialCode> onCountryChanged;
  final List<String> availableCities;
  final ValueChanged<String> onStateChanged;
  final List<String> sectorLabels;
  final String? selectedSector;
  final ValueChanged<String?> onSectorChanged;
  final VoidCallback onAddSector;

  @override
  Widget build(BuildContext context) {
    return RemaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RemaSectionHeader(title: 'Datos Generales', icon: Icons.badge_outlined),
          const SizedBox(height: 24),
          _ClientField(
            label: 'Razon social / Nombre legal',
            controller: businessNameController,
            errorText: businessNameError,
            onChanged: onBusinessNameChanged,
            inputFormatters: const [_UpperCaseTextFormatter()],
          ),
          const SizedBox(height: 18),
          _ClientField(
            label: 'Nombre de contacto',
            controller: nameController,
            errorText: contactNameError,
            onChanged: onContactNameChanged,
            inputFormatters: const [_UpperCaseTextFormatter()],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _ClientField(
                  label: 'RFC / ID Fiscal',
                  controller: rfcController,
                  errorText: rfcError,
                  onChanged: onRfcChanged,
                  inputFormatters: const [_UpperCaseTextFormatter()],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TELEFONO DE CONTACTO', style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox(
                          width: 170,
                          child: DropdownButtonFormField<_CountryDialCode>(
                            value: selectedCountry,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                            ),
                            items: [
                              for (final country in countries)
                                DropdownMenuItem<_CountryDialCode>(
                                  value: country,
                                  child: Text('${country.flag} ${country.dialCode}'),
                                ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                onCountryChanged(value);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: phoneController,
                            onChanged: onPhoneChanged,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(selectedCountry.maxDigits),
                            ],
                            decoration: InputDecoration(
                              hintText: 'Maximo ${selectedCountry.maxDigits} digitos',
                              errorText: phoneError,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _ClientField(
            label: 'Correo electronico',
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            errorText: emailError,
            onChanged: onEmailChanged,
          ),
          const SizedBox(height: 18),
          _ClientField(
            label: 'Direccion fiscal',
            controller: addressController,
            errorText: addressError,
            onChanged: onAddressChanged,
            inputFormatters: const [_TitleCaseTextFormatter()],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _AutocompleteClientField(
                  label: 'Estado',
                  controller: stateController,
                  options: _mexicoStatesAndCities.keys.toList(),
                  onChanged: onStateChanged,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: _AutocompleteClientField(
                  key: ValueKey('city-${stateController.text.trim()}'),
                  label: 'Ciudad',
                  controller: cityController,
                  options: availableCities,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 680;
              final sectorField = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SECTOR', style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedSector,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      hintText: 'Selecciona un sector',
                    ),
                    items: [
                      for (final sector in sectorLabels)
                        DropdownMenuItem<String>(
                          value: sector,
                          child: Text(
                            sector,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: onSectorChanged,
                  ),
                ],
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    sectorField,
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: onAddSector,
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
                    onPressed: onAddSector,
                    icon: const Icon(Icons.add),
                    label: const Text('Nuevo sector'),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DocumentsPanel extends StatelessWidget {
  const _DocumentsPanel({
    required this.documents,
    required this.onPickDocuments,
    required this.onRemoveDocument,
  });

  final List<_ClientDocument> documents;
  final VoidCallback onPickDocuments;
  final ValueChanged<_ClientDocument> onRemoveDocument;

  @override
  Widget build(BuildContext context) {
    return RemaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RemaSectionHeader(title: 'Documentos del Cliente', icon: Icons.folder_shared_outlined),
          const SizedBox(height: 24),
          InkWell(
            onTap: onPickDocuments,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: RemaColors.surfaceLow,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: RemaColors.outlineVariant),
              ),
              child: const Column(
                children: [
                  Icon(Icons.cloud_upload_outlined, size: 42, color: RemaColors.onSurfaceVariant),
                  SizedBox(height: 12),
                  Text('Arrastra archivos aqui o haz clic para subir'),
                  SizedBox(height: 6),
                  Text('Soportado: PDF, JPG, PNG'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (documents.isEmpty)
            const Text('Aun no hay documentos cargados.')
          else
            for (final document in documents) ...[
              _DocumentRow(
                document: document,
                onRemove: () => onRemoveDocument(document),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _ClientSidebar extends StatelessWidget {
  const _ClientSidebar({
    required this.onSave,
    required this.onCancel,
    required this.logoBytes,
    required this.logoName,
    required this.onPickLogo,
  });

  final VoidCallback onSave;
  final VoidCallback onCancel;
  final Uint8List? logoBytes;
  final String? logoName;
  final VoidCallback onPickLogo;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: RemaColors.primaryDark,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Seguridad en el Registro',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 14),
              Text(
                'Todos los datos proporcionados se resguardan para la generacion de contratos y levantamientos oficiales de REMA.',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        RemaPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const RemaSectionHeader(title: 'Logo del cliente', icon: Icons.image_outlined),
              const SizedBox(height: 16),
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
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.cloud_upload_outlined, size: 40),
                            SizedBox(height: 10),
                            Text('Haz clic para subir logo'),
                            SizedBox(height: 6),
                            Text('PNG, JPG o WEBP'),
                          ],
                        ),
                ),
              ),
              if (logoName != null) ...[
                const SizedBox(height: 10),
                Text(logoName!, style: Theme.of(context).textTheme.labelMedium),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        RemaPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: onSave,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Guardar Cliente'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancelar'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ClientField extends StatelessWidget {
  const _ClientField({
    required this.label,
    required this.controller,
    this.inputFormatters,
    this.keyboardType,
    this.errorText,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputType? keyboardType;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          onChanged: onChanged,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          decoration: InputDecoration(
            hintText: 'Ingresa $label',
            errorText: errorText,
          ),
        ),
      ],
    );
  }
}

class _AutocompleteClientField extends StatelessWidget {
  const _AutocompleteClientField({
    super.key,
    required this.label,
    required this.controller,
    required this.options,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final List<String> options;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 8),
        Autocomplete<String>(
          initialValue: TextEditingValue(text: controller.text),
          optionsBuilder: (textEditingValue) {
            final query = textEditingValue.text.trim().toLowerCase();
            if (query.isEmpty) {
              return options;
            }
            return options.where((item) => item.toLowerCase().contains(query));
          },
          onSelected: (value) {
            controller.text = value;
            onChanged?.call(value);
          },
          fieldViewBuilder: (context, textController, focusNode, _) {
            return TextField(
              controller: textController,
              focusNode: focusNode,
              decoration: InputDecoration(hintText: 'Selecciona o escribe $label'),
              onChanged: (value) {
                controller.text = value;
                onChanged?.call(value);
              },
            );
          },
        ),
      ],
    );
  }
}

class _UpperCaseTextFormatter extends TextInputFormatter {
  const _UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      composing: TextRange.empty,
    );
  }
}

class _TitleCaseTextFormatter extends TextInputFormatter {
  const _TitleCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final words = newValue.text.split(RegExp(r'\s+'));
    final buffer = StringBuffer();
    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      if (word.isEmpty) {
        continue;
      }
      final normalized = word.length == 1
          ? word.toUpperCase()
          : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
      if (buffer.isNotEmpty) {
        buffer.write(' ');
      }
      buffer.write(normalized);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({required this.document, required this.onRemove});

  final _ClientDocument document;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final extension = document.name.split('.').last.toLowerCase();
    final isPdf = extension == 'pdf';
    return Container(
      padding: const EdgeInsets.all(16),
      color: RemaColors.surface,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            color: isPdf ? const Color(0xFFFBE4E2) : const Color(0xFFE3F0FF),
            alignment: Alignment.center,
            child: Icon(isPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(document.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(_formatSize(document.size), style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
          IconButton(onPressed: onRemove, icon: const Icon(Icons.delete_outline)),
        ],
      ),
    );
  }
}

class _ClientDocument {
  const _ClientDocument({required this.name, required this.size, this.bytes});

  final String name;
  final int size;
  final Uint8List? bytes;
}

class _CountryDialCode {
  const _CountryDialCode({
    required this.name,
    required this.flag,
    required this.dialCode,
    required this.maxDigits,
  });

  final String name;
  final String flag;
  final String dialCode;
  final int maxDigits;
}

const List<_CountryDialCode> _countryDialCodes = <_CountryDialCode>[
  _CountryDialCode(name: 'Mexico', flag: '🇲🇽', dialCode: '+52', maxDigits: 10),
  _CountryDialCode(name: 'Estados Unidos', flag: '🇺🇸', dialCode: '+1', maxDigits: 10),
  _CountryDialCode(name: 'Canada', flag: '🇨🇦', dialCode: '+1', maxDigits: 10),
  _CountryDialCode(name: 'Guatemala', flag: '🇬🇹', dialCode: '+502', maxDigits: 8),
  _CountryDialCode(name: 'Colombia', flag: '🇨🇴', dialCode: '+57', maxDigits: 10),
  _CountryDialCode(name: 'Argentina', flag: '🇦🇷', dialCode: '+54', maxDigits: 10),
];

const Map<String, List<String>> _mexicoStatesAndCities = <String, List<String>>{
  'Aguascalientes': ['Aguascalientes', 'Jesus Maria', 'Calvillo'],
  'Baja California': ['Mexicali', 'Tijuana', 'Ensenada', 'Tecate', 'Rosarito'],
  'Baja California Sur': ['La Paz', 'Los Cabos', 'Comondu', 'Loreto'],
  'Campeche': ['Campeche', 'Carmen', 'Champoton'],
  'Chiapas': ['Tuxtla Gutierrez', 'Tapachula', 'San Cristobal de las Casas', 'Comitan'],
  'Chihuahua': ['Chihuahua', 'Juarez', 'Delicias', 'Cuauhtemoc'],
  'Ciudad de Mexico': ['Alvaro Obregon', 'Benito Juarez', 'Coyoacan', 'Cuauhtemoc', 'Iztapalapa'],
  'Coahuila': ['Saltillo', 'Torreon', 'Monclova', 'Piedras Negras'],
  'Colima': ['Colima', 'Manzanillo', 'Tecoman'],
  'Durango': ['Durango', 'Gomez Palacio', 'Lerdo'],
  'Estado de Mexico': ['Toluca', 'Naucalpan', 'Ecatepec', 'Nezahualcoyotl', 'Tlalnepantla'],
  'Guanajuato': ['Leon', 'Irapuato', 'Celaya', 'Guanajuato', 'Salamanca'],
  'Guerrero': ['Chilpancingo', 'Acapulco', 'Iguala', 'Taxco'],
  'Hidalgo': ['Pachuca', 'Tulancingo', 'Tula', 'Actopan'],
  'Jalisco': ['Guadalajara', 'Zapopan', 'Tlaquepaque', 'Puerto Vallarta', 'Tonalá'],
  'Michoacan': ['Morelia', 'Uruapan', 'Zamora', 'Lazaro Cardenas'],
  'Morelos': ['Cuernavaca', 'Jiutepec', 'Temixco', 'Cuautla'],
  'Nayarit': ['Tepic', 'Bahia de Banderas', 'Santiago Ixcuintla'],
  'Nuevo Leon': ['Monterrey', 'Guadalupe', 'San Nicolas', 'Apodaca', 'San Pedro Garza Garcia'],
  'Oaxaca': ['Oaxaca de Juarez', 'Salina Cruz', 'Juchitan', 'Tuxtepec'],
  'Puebla': ['Puebla', 'Tehuacan', 'Atlixco', 'San Martin Texmelucan'],
  'Queretaro': ['Queretaro', 'San Juan del Rio', 'El Marques', 'Corregidora'],
  'Quintana Roo': ['Cancun', 'Playa del Carmen', 'Chetumal', 'Cozumel', 'Tulum'],
  'San Luis Potosi': ['San Luis Potosi', 'Soledad de Graciano Sanchez', 'Ciudad Valles'],
  'Sinaloa': ['Culiacan', 'Mazatlan', 'Los Mochis', 'Guasave'],
  'Sonora': ['Hermosillo', 'Ciudad Obregon', 'Nogales', 'San Luis Rio Colorado'],
  'Tabasco': ['Villahermosa', 'Comalcalco', 'Paraiso', 'Cardenas'],
  'Tamaulipas': ['Ciudad Victoria', 'Reynosa', 'Matamoros', 'Nuevo Laredo', 'Tampico'],
  'Tlaxcala': ['Tlaxcala', 'Apizaco', 'Huamantla'],
  'Veracruz': ['Xalapa', 'Veracruz', 'Coatzacoalcos', 'Poza Rica', 'Cordoba'],
  'Yucatan': ['Merida', 'Valladolid', 'Progreso', 'Tizimin'],
  'Zacatecas': ['Zacatecas', 'Guadalupe', 'Fresnillo', 'Jerez'],
};

String _formatSize(int size) {
  if (size < 1024) {
    return '$size B';
  }
  final kb = size / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(1)} KB';
  }
  return '${(kb / 1024).toStringAsFixed(1)} MB';
}
