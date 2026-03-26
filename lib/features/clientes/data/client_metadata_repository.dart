import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../../../core/config/supabase_bootstrap.dart';

class ClientMetadataRepository {
  static const List<String> defaultSectorLabels = <String>[
    'HOTELERO',
    'COMERCIAL',
    'CONSTRUCTORA',
    'RESIDENCIAL',
  ];

  String normalizeSectorLabel(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
  }

  String logoMimeTypeFromFileName(String fileName) {
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : 'png';
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      _ => 'image/png',
    };
  }

  Future<List<String>> fetchSectorLabels() async {
    final base = {...defaultSectorLabels};
    final client = SupabaseBootstrap.client;
    if (client == null) {
      final result = base.toList()..sort();
      return result;
    }

    try {
      final rows = await client
          .from('client_sector_tags')
          .select('name')
          .order('name', ascending: true);
      for (final row in rows) {
        final value = normalizeSectorLabel(row['name'] as String? ?? '');
        if (value.isNotEmpty) {
          base.add(value);
        }
      }
    } catch (_) {
      // Fallback a defaults si el catalogo no esta disponible.
    }

    final result = base.toList()..sort();
    return result;
  }

  Future<void> ensureSectorLabel(String label) async {
    final normalized = normalizeSectorLabel(label);
    if (normalized.isEmpty) {
      return;
    }
    final client = SupabaseBootstrap.client;
    if (client == null) {
      return;
    }
    try {
      await client.from('client_sector_tags').upsert({'name': normalized});
    } catch (_) {
      // No bloquear guardado de cliente por fallo del catalogo.
    }
  }

  Future<String?> uploadLogo({
    required String clientId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final client = SupabaseBootstrap.client;
    if (client == null || bytes.isEmpty) {
      return null;
    }

    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : 'png';
    final safeExt = ext.isEmpty ? 'png' : ext;
    final objectPath = '$clientId/logo_${DateTime.now().millisecondsSinceEpoch}.$safeExt';
    final mime = logoMimeTypeFromFileName(fileName);

    await client.storage.from('client-logos').uploadBinary(
          objectPath,
          bytes,
          fileOptions: FileOptions(contentType: mime, upsert: true),
        );

    return objectPath;
  }

  Future<Uint8List?> downloadLogo(String? objectPath) async {
    final client = SupabaseBootstrap.client;
    if (client == null || objectPath == null || objectPath.trim().isEmpty) {
      return null;
    }
    try {
      final bytes = await client.storage.from('client-logos').download(objectPath);
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> updateClientVisibility({
    required String clientId,
    required bool isHidden,
  }) async {
    final client = SupabaseBootstrap.client;
    if (client == null) {
      return;
    }
    await client.from('clients').update({
      'is_hidden': isHidden,
      'hidden_at': isHidden ? DateTime.now().toIso8601String() : null,
    }).eq('id', clientId);
  }

  Future<void> updateClientMetadata({
    required String clientId,
    required String businessName,
    required String email,
    required String phone,
    required String address,
    required String sectorLabel,
    String? rfc,
    String? logoPath,
    String? logoMimeType,
  }) async {
    final client = SupabaseBootstrap.client;
    if (client == null) {
      return;
    }

    final payload = <String, Object?>{
      'business_name': businessName.trim().toUpperCase(),
      'rfc': (rfc == null || rfc.trim().isEmpty) ? null : rfc.trim().toUpperCase(),
      'email': email.trim().toLowerCase(),
      'phone': phone.trim(),
      'address_line': address.trim(),
      'sector_label': normalizeSectorLabel(sectorLabel),
    };
    if (logoPath != null) {
      payload['logo_path'] = logoPath;
      payload['logo_mime_type'] = logoMimeType;
    }

    await client.from('clients').update(payload).eq('id', clientId);
  }
}
