import 'dart:typed_data';

import 'package:flutter/material.dart';

enum ResponsibleRole { supervisor, gerente }

ResponsibleRole responsibleRoleFromCode(String code) {
  switch (code) {
    case 'gerente':
      return ResponsibleRole.gerente;
    case 'supervisor':
    default:
      return ResponsibleRole.supervisor;
  }
}

extension ResponsibleRoleX on ResponsibleRole {
  String get code => switch (this) {
        ResponsibleRole.supervisor => 'supervisor',
        ResponsibleRole.gerente => 'gerente',
      };

  String get label => switch (this) {
        ResponsibleRole.supervisor => 'Supervisor',
        ResponsibleRole.gerente => 'Gerente',
      };
}

class ClientResponsibleRecord {
  const ClientResponsibleRecord({
    required this.id,
    required this.role,
    required this.title,
    required this.position,
    required this.fullName,
    required this.phone,
    required this.email,
    required this.contactNotes,
  });

  final String id;
  final ResponsibleRole role;
  final String title;
  final String position;
  final String fullName;
  final String phone;
  final String email;
  final String contactNotes;

  ClientResponsibleRecord copyWith({
    String? id,
    ResponsibleRole? role,
    String? title,
    String? position,
    String? fullName,
    String? phone,
    String? email,
    String? contactNotes,
  }) {
    return ClientResponsibleRecord(
      id: id ?? this.id,
      role: role ?? this.role,
      title: title ?? this.title,
      position: position ?? this.position,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      contactNotes: contactNotes ?? this.contactNotes,
    );
  }
}

class ClientRecord {
  const ClientRecord({
    required this.id,
    required this.name,
    this.contactName,
    this.rfc,
    required this.sector,
    required this.badge,
    required this.activeProjects,
    required this.months,
    required this.icon,
    required this.contactEmail,
    required this.phone,
    required this.address,
    required this.responsibles,
    this.logoPath,
    this.logoBytes,
    this.isHidden = false,
  });

  final String id;
  final String name;
  final String? contactName;
  final String? rfc;
  final String sector;
  final String badge;
  final String activeProjects;
  final String months;
  final IconData icon;
  final String contactEmail;
  final String phone;
  final String address;
  final List<ClientResponsibleRecord> responsibles;
  final String? logoPath;
  final Uint8List? logoBytes;
  final bool isHidden;

  String get displayContactName => (contactName ?? '').trim();

  bool matchesSearchQuery(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }
    return name.toLowerCase().contains(normalized) ||
        displayContactName.toLowerCase().contains(normalized) ||
        sector.toLowerCase().contains(normalized) ||
        contactEmail.toLowerCase().contains(normalized);
  }

  ClientRecord copyWith({
    String? id,
    String? name,
    String? contactName,
    String? rfc,
    String? sector,
    String? badge,
    String? activeProjects,
    String? months,
    IconData? icon,
    String? contactEmail,
    String? phone,
    String? address,
    List<ClientResponsibleRecord>? responsibles,
    String? logoPath,
    Uint8List? logoBytes,
    bool? isHidden,
  }) {
    return ClientRecord(
      id: id ?? this.id,
      name: name ?? this.name,
      contactName: contactName ?? this.contactName,
      rfc: rfc ?? this.rfc,
      sector: sector ?? this.sector,
      badge: badge ?? this.badge,
      activeProjects: activeProjects ?? this.activeProjects,
      months: months ?? this.months,
      icon: icon ?? this.icon,
      contactEmail: contactEmail ?? this.contactEmail,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      responsibles: responsibles ?? this.responsibles,
      logoPath: logoPath ?? this.logoPath,
      logoBytes: logoBytes ?? this.logoBytes,
      isHidden: isHidden ?? this.isHidden,
    );
  }
}

ClientRecord? findClientById(String clientId) {
  for (final client in mockClients) {
    if (client.id == clientId) {
      return client;
    }
  }
  return null;
}

const mockClients = <ClientRecord>[];