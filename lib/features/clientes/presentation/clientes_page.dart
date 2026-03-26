import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/supabase_bootstrap.dart';
import '../../../core/theme/rema_colors.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/rema_panels.dart';
import '../data/client_metadata_repository.dart';
import 'clientes_mock_data.dart';

class ClientesPage extends StatefulWidget {
  const ClientesPage({super.key});

  @override
  State<ClientesPage> createState() => _ClientesPageState();
}

class _ClientesPageState extends State<ClientesPage> {
  final _searchController = TextEditingController();
  final _metadataRepository = ClientMetadataRepository();

  List<ClientRecord> _clients = const <ClientRecord>[];
  List<String> _sectorLabels = const <String>['TODOS'];
  bool _isLoading = true;
  bool _showHidden = false;
  String _selectedSector = 'TODOS';

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadClients() async {
    setState(() => _isLoading = true);
    final nextClients = await _fetchClients();
    final catalog = await _metadataRepository.fetchSectorLabels();
    if (!mounted) {
      return;
    }

    final sectors = <String>{...catalog};
    for (final client in nextClients) {
      final normalized = _metadataRepository.normalizeSectorLabel(client.sector);
      if (normalized.isNotEmpty && normalized != 'SIN SECTOR') {
        sectors.add(normalized);
      }
    }

    setState(() {
      _clients = nextClients;
      _sectorLabels = ['TODOS', ...(sectors.toList()..sort())];
      if (!_sectorLabels.contains(_selectedSector)) {
        _selectedSector = 'TODOS';
      }
      _isLoading = false;
    });
  }

  Future<List<ClientRecord>> _fetchClients() async {
    final base = List<ClientRecord>.from(mockClients);
    final client = SupabaseBootstrap.client;
    if (client == null) {
      return base;
    }

    try {
      List<dynamic> rows;
      try {
        rows = await client
            .from('clients')
            .select('id, business_name, email, phone, address_line, city, created_at, sector_label, logo_path, is_hidden')
            .order('created_at', ascending: false);
      } catch (_) {
        rows = await client
            .from('clients')
            .select('id, business_name, email, phone, address_line, city, created_at')
            .order('created_at', ascending: false);
      }

      final knownNames = base.map((item) => item.name.trim().toLowerCase()).toSet();
      final remoteClients = await Future.wait(
        rows.map((row) async {
          final name = (row['business_name'] as String? ?? '').trim();
          if (name.isEmpty || knownNames.contains(name.toLowerCase())) {
            return null;
          }

          final addressLine = (row['address_line'] as String? ?? '').trim();
          final city = (row['city'] as String? ?? '').trim();
          final fullAddress = [
            if (addressLine.isNotEmpty) addressLine,
            if (city.isNotEmpty) city,
          ].join(', ');
          final rawSector = (row['sector_label'] as String? ?? '').trim();
          final logoPath = (row['logo_path'] as String? ?? '').trim();
          final logoBytes = await _metadataRepository.downloadLogo(logoPath);

          return ClientRecord(
            id: row['id'] as String? ?? name.toLowerCase().replaceAll(' ', '-'),
            name: name,
            sector: rawSector.isEmpty ? 'SIN SECTOR' : _metadataRepository.normalizeSectorLabel(rawSector),
            badge: 'Activo',
            activeProjects: '00',
            months: '--',
            icon: Icons.apartment,
            contactEmail: (row['email'] as String? ?? 'sin-correo@cliente.com').trim(),
            phone: (row['phone'] as String? ?? 'Sin telefono').trim(),
            address: fullAddress.isEmpty ? 'Sin direccion registrada' : fullAddress,
            responsibles: const [],
            logoPath: logoPath.isEmpty ? null : logoPath,
            logoBytes: logoBytes,
            isHidden: row['is_hidden'] as bool? ?? false,
          );
        }),
      );

      base.addAll(remoteClients.whereType<ClientRecord>());
    } catch (_) {
      return base;
    }

    return base;
  }

  Future<void> _toggleHidden(ClientRecord client) async {
    final nextHidden = !client.isHidden;
    try {
      if (SupabaseBootstrap.client != null && _isUuid(client.id)) {
        await _metadataRepository.updateClientVisibility(
          clientId: client.id,
          isHidden: nextHidden,
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _clients = [
          for (final item in _clients)
            if (item.id == client.id) item.copyWith(isHidden: nextHidden) else item,
        ];
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(nextHidden ? 'Cliente ocultado.' : 'Cliente restaurado.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('No fue posible actualizar la visibilidad del cliente.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  bool _isUuid(String value) {
    final uuidPattern = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    );
    return uuidPattern.hasMatch(value);
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = _clients.where((client) {
      final matchesVisibility = client.isHidden == _showHidden;
      final normalizedSector = _metadataRepository.normalizeSectorLabel(client.sector);
      final matchesSector = _selectedSector == 'TODOS' || normalizedSector == _selectedSector;
      final matchesSearch = query.isEmpty ||
          client.name.toLowerCase().contains(query) ||
          client.sector.toLowerCase().contains(query) ||
          client.contactEmail.toLowerCase().contains(query);
      return matchesVisibility && matchesSector && matchesSearch;
    }).toList();

    final totalActiveProjects = filtered
        .map((item) => int.tryParse(item.activeProjects) ?? 0)
        .fold<int>(0, (sum, value) => sum + value);

    return PageFrame(
      title: 'Clientes',
      subtitle: 'Administra la base de datos de socios comerciales y proyectos arquitectonicos activos.',
      trailing: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _isLoading ? null : _loadClients,
            icon: const Icon(Icons.refresh),
            label: const Text('Actualizar'),
          ),
          FilledButton.icon(
            onPressed: () => context.go('/nuevo-cliente'),
            icon: const Icon(Icons.add),
            label: const Text('Anadir Cliente'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: _showHidden ? 'Buscar cliente oculto...' : 'Buscar cliente...',
              prefixIcon: const Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                label: const Text('Visibles'),
                selected: !_showHidden,
                onSelected: (_) => setState(() => _showHidden = false),
              ),
              ChoiceChip(
                label: const Text('Ocultos'),
                selected: _showHidden,
                onSelected: (_) => setState(() => _showHidden = true),
              ),
              SizedBox(
                width: 260,
                child: DropdownButtonFormField<String>(
                  value: _selectedSector,
                  decoration: const InputDecoration(labelText: 'Filtrar por sector'),
                  items: [
                    for (final sector in _sectorLabels)
                      DropdownMenuItem<String>(
                        value: sector,
                        child: Text(sector),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedSector = value);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 920;
              final totalLabel = _showHidden ? 'Clientes ocultos' : 'Clientes visibles';
              final metrics = <Widget>[
                Expanded(
                  child: RemaMetricTile(
                    label: 'Total Carteras',
                    value: filtered.length.toString().padLeft(2, '0'),
                    caption: totalLabel,
                  ),
                ),
                const SizedBox(width: 16, height: 16),
                Expanded(
                  child: RemaMetricTile(
                    label: 'Proyectos en Curso',
                    value: totalActiveProjects.toString().padLeft(2, '0'),
                    caption: 'Suma de activos',
                    backgroundColor: RemaColors.primaryDark,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 16, height: 16),
                Expanded(
                  child: RemaMetricTile(
                    label: 'Fuente de Datos',
                    value: SupabaseBootstrap.client == null ? 'LOCAL' : 'LOCAL+DB',
                    caption: 'Clientes + Supabase',
                    backgroundColor: RemaColors.surfaceHighest,
                  ),
                ),
              ];
              if (isWide) {
                return Row(children: metrics);
              }
              return Column(
                children: [
                  metrics[0],
                  const SizedBox(height: 16),
                  metrics[2],
                  const SizedBox(height: 16),
                  metrics[4],
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (filtered.isEmpty)
            RemaPanel(
              child: Text(
                _showHidden
                    ? 'No hay clientes ocultos para mostrar con el filtro actual.'
                    : 'No hay clientes para mostrar con el filtro actual.',
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1100
                    ? 3
                    : constraints.maxWidth >= 760
                        ? 2
                        : 1;
                final itemWidth = columns == 1
                    ? constraints.maxWidth
                    : (constraints.maxWidth - (16 * (columns - 1))) / columns;
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final client in filtered)
                      SizedBox(
                        width: itemWidth,
                        child: _ClientCard(
                          client: client,
                          onToggleHidden: () => _toggleHidden(client),
                        ),
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

class _ClientCard extends StatelessWidget {
  const _ClientCard({required this.client, required this.onToggleHidden});

  final ClientRecord client;
  final VoidCallback onToggleHidden;

  @override
  Widget build(BuildContext context) {
    return RemaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64,
                height: 64,
                color: RemaColors.surfaceLow,
                alignment: Alignment.center,
                child: client.logoBytes != null && client.logoBytes!.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.memory(
                          client.logoBytes!,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                        ),
                      )
                    : Icon(client.icon, color: RemaColors.onSurfaceVariant, size: 28),
              ),
              const Spacer(),
              IconButton(
                onPressed: onToggleHidden,
                tooltip: client.isHidden ? 'Restaurar cliente' : 'Ocultar cliente',
                icon: Icon(client.isHidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                color: client.badge == 'Premium' ? const Color(0xFFFFDEA0) : RemaColors.surfaceHighest,
                child: Text(
                  client.badge.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            client.name,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(client.sector.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 22),
          Row(
            children: [
              _ClientMetric(value: client.activeProjects, label: 'Proyectos activos'),
              Container(width: 1, height: 32, color: RemaColors.outlineVariant.withValues(alpha: 0.3)),
              const SizedBox(width: 18),
              _ClientMetric(value: client.months, label: 'Meses relacion'),
            ],
          ),
          const SizedBox(height: 22),
          TextButton.icon(
            onPressed: () => context.go('/clientes/${client.id}'),
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Ver detalles'),
          ),
        ],
      ),
    );
  }
}

class _ClientMetric extends StatelessWidget {
  const _ClientMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
