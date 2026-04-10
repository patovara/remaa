import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../../../core/config/supabase_bootstrap.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/utils/client_input_rules.dart';

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

  String normalizeContactName(String value) {
    return ClientInputRules.sanitizeTextOnly(value);
  }

  String? extractLegacyContactName(String? notes) {
    final source = (notes ?? '').trim();
    if (source.isEmpty) {
      return null;
    }
    final match = RegExp(r'contacto principal\s*:\s*(.+)$', caseSensitive: false)
        .firstMatch(source);
    if (match == null) {
      return null;
    }
    final extracted = normalizeContactName(match.group(1) ?? '');
    return extracted.isEmpty ? null : extracted;
  }

  String? resolveContactName({String? contactName, String? notes}) {
    final direct = normalizeContactName(contactName ?? '');
    if (direct.isNotEmpty) {
      return direct;
    }
    return extractLegacyContactName(notes);
  }

  String logoMimeTypeFromFileName(String fileName) {
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : 'jpg';
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
    } catch (error) {
      final message = error.toString().toLowerCase();
      if (message.contains('23505') || message.contains('duplicate key value')) {
        return;
      }
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

    final objectPath = '$clientId/logo_${DateTime.now().millisecondsSinceEpoch}.jpg';
    const mime = 'image/jpeg';

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
    String? contactName,
    required String email,
    required String phone,
    required String address,
    String? city,
    String? state,
    required String sectorLabel,
    String? rfc,
    String? logoPath,
    String? logoMimeType,
  }) async {
    final client = SupabaseBootstrap.client;
    if (client == null) {
      return;
    }

    final rawPhone = phone.trim();
    final phoneE164 = ClientInputRules.toE164Mx(rawPhone) ?? rawPhone;

    final payload = <String, Object?>{
      'business_name': businessName.trim().toUpperCase(),
      'contact_name': (contactName == null || contactName.trim().isEmpty)
          ? null
          : normalizeContactName(contactName),
      'rfc': (rfc == null || rfc.trim().isEmpty) ? null : rfc.trim().toUpperCase(),
      'email': email.trim().toLowerCase(),
      'phone': phoneE164.isEmpty ? null : phoneE164,
      'address_line': address.trim().isEmpty ? null : address.trim(),
      'city': (city == null || city.trim().isEmpty) ? null : city.trim(),
      'state': (state == null || state.trim().isEmpty) ? null : state.trim(),
      'sector_label': normalizeSectorLabel(sectorLabel),
    };
    if (logoPath != null) {
      payload['logo_path'] = logoPath;
      if (logoMimeType != null && logoMimeType.trim().isNotEmpty) {
        payload['logo_mime_type'] = logoMimeType;
      }
    }

    try {
      await client.from('clients').update(payload).eq('id', clientId);
      AppLogger.info('client_update_succeeded', data: {
        'client_id': clientId,
        'payload_keys': payload.keys.join(','),
      });
    } catch (error) {
      AppLogger.error('client_update_failed', data: {
        'client_id': clientId,
        'payload_keys': payload.keys.join(','),
        'error': error.toString(),
      });
      rethrow;
    }
  }
}
