import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../../../core/config/supabase_bootstrap.dart';
import '../../../core/theme/rema_colors.dart';
import '../../../core/utils/rema_feedback.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/rema_panels.dart';

class NuevoClientePage extends StatefulWidget {
  const NuevoClientePage({super.key});

  @override
  State<NuevoClientePage> createState() => _NuevoClientePageState();
}

class _NuevoClientePageState extends State<NuevoClientePage> {
  final _businessNameController = TextEditingController(text: 'Residencial Las Lomas S.A.');
  final _nameController = TextEditingController(text: 'Arq. Juan Perez');
  final _rfcController = TextEditingController(text: 'JUAP900101AAA');
  final _phoneController = TextEditingController(text: '+52 55 0000 0000');
  final _emailController = TextEditingController(text: 'cliente@ejemplo.com');
  final _addressController = TextEditingController(text: 'Calle, Numero, Colonia');
  final _cityController = TextEditingController(text: 'Ciudad de Mexico, CDMX');

  final List<_ClientDocument> _documents = [];

  @override
  void dispose() {
    _businessNameController.dispose();
    _nameController.dispose();
    _rfcController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    super.dispose();
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
    final client = SupabaseBootstrap.client;
    if (client == null) {
      showRemaMessage(
        context,
        'No hay conexion activa con Supabase. Revisa el .env local.',
      );
      return;
    }

    try {
      final inserted = await client.from('clients').insert({
        'business_name': _businessNameController.text.trim(),
        'rfc': _rfcController.text.trim(),
        'phone': _phoneController.text.trim(),
        'email': _emailController.text.trim(),
        'address_line': _addressController.text.trim(),
        'city': _cityController.text.trim(),
        'notes': 'Contacto principal: ${_nameController.text.trim()}',
      }).select('id').single();

      final clientId = inserted['id'] as String?;
      if (clientId != null && _documents.isNotEmpty) {
        await _uploadDocuments(client, clientId);
      }

      if (!mounted) {
        return;
      }

      showRemaMessage(
        context,
        'Cliente ${_businessNameController.text.trim()} creado correctamente.',
        label: 'Clientes',
        onAction: () => context.go('/clientes'),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      showRemaMessage(
        context,
        'No se pudo guardar el cliente. Revisa permisos RLS o datos requeridos.',
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
            nameController: _nameController,
            rfcController: _rfcController,
            phoneController: _phoneController,
            emailController: _emailController,
            addressController: _addressController,
            cityController: _cityController,
          );
          final docsPanel = _DocumentsPanel(
            documents: _documents,
            onPickDocuments: _pickDocuments,
            onRemoveDocument: _removeDocument,
          );
          final sidebar = _ClientSidebar(
            onSave: () => _saveClient(),
            onCancel: () => context.go('/clientes'),
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
    required this.nameController,
    required this.rfcController,
    required this.phoneController,
    required this.emailController,
    required this.addressController,
    required this.cityController,
  });

  final TextEditingController businessNameController;
  final TextEditingController nameController;
  final TextEditingController rfcController;
  final TextEditingController phoneController;
  final TextEditingController emailController;
  final TextEditingController addressController;
  final TextEditingController cityController;

  @override
  Widget build(BuildContext context) {
    return RemaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RemaSectionHeader(title: 'Datos Generales', icon: Icons.badge_outlined),
          const SizedBox(height: 24),
          _ClientField(label: 'Razon social / Nombre legal', controller: businessNameController),
          const SizedBox(height: 18),
          _ClientField(label: 'Nombre de contacto', controller: nameController),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: _ClientField(label: 'RFC / ID Fiscal', controller: rfcController)),
              const SizedBox(width: 18),
              Expanded(child: _ClientField(label: 'Telefono de contacto', controller: phoneController)),
            ],
          ),
          const SizedBox(height: 18),
          _ClientField(label: 'Correo electronico', controller: emailController),
          const SizedBox(height: 18),
          _ClientField(label: 'Direccion fiscal', controller: addressController),
          const SizedBox(height: 18),
          _ClientField(label: 'Ubicacion / Ciudad', controller: cityController),
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
  const _ClientSidebar({required this.onSave, required this.onCancel});

  final VoidCallback onSave;
  final VoidCallback onCancel;

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
  const _ClientField({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 8),
        TextField(controller: controller),
      ],
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
