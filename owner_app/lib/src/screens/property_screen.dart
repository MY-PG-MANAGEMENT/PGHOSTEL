import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_shell.dart';
import '../widgets/async_action_button.dart';

// ─── Helpers ────────────────────────────────────────────────────────────────

String _rupees(dynamic v) => v != null ? '₹$v' : '—';

Color _statusColor(String? s) {
  switch (s?.toUpperCase()) {
    case 'ACTIVE':
      return PgColors.success;
    case 'INACTIVE':
      return PgColors.danger;
    default:
      return Colors.grey;
  }
}

Widget _avatar(String name, {double radius = 22}) {
  final initials = name.trim().split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
  final palette = [PgColors.primary, const Color(0xFF2563EB), PgColors.success, PgColors.warning];
  final color = palette[name.codeUnitAt(0) % palette.length];
  return CircleAvatar(
    radius: radius,
    backgroundColor: color,
    child: Text(initials,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: radius * 0.7)),
  );
}

// ─── Main Screen ─────────────────────────────────────────────────────────────

class PropertyScreen extends StatefulWidget {
  const PropertyScreen({super.key});

  @override
  State<PropertyScreen> createState() => _PropertyScreenState();
}

class _PropertyScreenState extends State<PropertyScreen> {
  late Future<Map<String, dynamic>> _future;
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() => setState(() => _query = _search.text.toLowerCase()));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _load() {
    _future = context.read<AppState>().apiClient.get('/owner/properties');
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Properties',
      actions: [
        IconButton(
          icon: const Icon(Icons.add_business_outlined),
          tooltip: 'Add Property',
          onPressed: _openAdd,
        ),
      ],
      child: Column(
        children: [
          TextField(
            controller: _search,
            decoration: const InputDecoration(
              hintText: 'Search properties…',
              prefixIcon: Icon(Icons.search),
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _ErrorState(error: snapshot.error, onRetry: () => setState(_load));
                }
                final data = snapshot.data ?? {};
                final rawList = data['items'];
                final List items = rawList is List ? rawList : [];
                final props = _filterProps(items.cast<Map<String, dynamic>>());

                if (props.isEmpty) {
                  return _EmptyState(
                    icon: Icons.apartment_outlined,
                    title: _query.isEmpty ? 'No properties yet' : 'No results',
                    message: _query.isEmpty ? 'Tap + to add your first property.' : 'Try a different search term.',
                    onAction: _query.isEmpty ? _openAdd : null,
                    actionLabel: 'Add Property',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => setState(_load),
                  child: ListView.separated(
                    itemCount: props.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => _PropertyCard(
                      data: props[index],
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(
                            builder: (_) => PropertyDetailScreen(property: props[index]),
                          ))
                          .then((_) => setState(_load)),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _filterProps(List<Map<String, dynamic>> items) {
    if (_query.isEmpty) return items;
    return items
        .where((p) =>
            '${p['facilityName']}'.toLowerCase().contains(_query) ||
            '${p['description']}'.toLowerCase().contains(_query))
        .toList();
  }

  void _openAdd() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _AddPropertySheet(),
    );
    if (added == true) setState(_load);
  }
}

// ─── Property Card ─────────────────────────────────────────────────────────

class _PropertyCard extends StatelessWidget {
  const _PropertyCard({required this.data, required this.onTap});

  final Map<String, dynamic> data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = '${data['facilityName'] ?? 'Property'}';
    final desc = '${data['description'] ?? ''}';
    final status = '${data['status'] ?? 'ACTIVE'}';
    final code = '${data['facilityCode'] ?? ''}';
    final capacity = data['capacity'];

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _avatar(name, radius: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(name,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        ),
                        _StatusChip(status),
                      ],
                    ),
                    if (desc.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(desc,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (code.isNotEmpty)
                          _InfoChip(label: code, icon: Icons.qr_code_2_outlined),
                        if (capacity != null)
                          _InfoChip(label: '$capacity beds', icon: Icons.bed_outlined),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Property Detail Screen ───────────────────────────────────────────────

class PropertyDetailScreen extends StatefulWidget {
  const PropertyDetailScreen({required this.property, super.key});

  final Map<String, dynamic> property;

  @override
  State<PropertyDetailScreen> createState() => _PropertyDetailScreenState();
}

class _PropertyDetailScreenState extends State<PropertyDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late Future<Map<String, dynamic>> _floorFuture;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadFloors();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _loadFloors() {
    final id = widget.property['facilityId'];
    _floorFuture = context.read<AppState>().apiClient.get('/properties/$id/floors');
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.property;
    final name = '${p['facilityName'] ?? 'Property'}';
    final desc = '${p['description'] ?? ''}';
    final status = '${p['status'] ?? 'ACTIVE'}';

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: _openEdit,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: 'Floors & Rooms'), Tab(text: 'Amenities')],
        ),
      ),
      body: Column(
        children: [
          // Header
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _avatar(name, radius: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                          if (desc.isNotEmpty)
                            Text(desc,
                                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                        ],
                      ),
                    ),
                    _StatusChip(status),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    if ((p['facilityCode'] ?? '').toString().isNotEmpty)
                      _StatBadge(label: 'Code', value: '${p['facilityCode']}'),
                    _StatBadge(label: 'Capacity', value: '${p['capacity'] ?? '—'} beds'),
                  ],
                ),
                _RoomSummarySection(propertyId: p['facilityId']),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _FloorsTab(
                  propertyId: p['facilityId'],
                  floorFuture: _floorFuture,
                  onRefresh: () => setState(_loadFloors),
                ),
                const _AmenitiesTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openEdit() async {
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _EditPropertySheet(property: widget.property),
    );
    if (updated == true && mounted) Navigator.of(context).pop();
  }
}

// ─── Room Summary Section ─────────────────────────────────────────────────

class _RoomSummarySection extends StatefulWidget {
  const _RoomSummarySection({required this.propertyId});
  final dynamic propertyId;

  @override
  State<_RoomSummarySection> createState() => _RoomSummarySectionState();
}

class _RoomSummarySectionState extends State<_RoomSummarySection> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().apiClient
        .get('/properties/${widget.propertyId}/room-summary');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final items = snapshot.data?['items'];
        if (items is! List || items.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: items.cast<Map<String, dynamic>>().map((s) {
              final sharing = s['sharingType']?.toString() ?? '?';
              final rooms = s['roomCount'] ?? 0;
              final beds = s['bedCount'] ?? 0;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: PgColors.lavender,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: PgColors.primary.withValues(alpha: 0.2)),
                ),
                child: Text(
                  '$sharing-Sharing · $rooms room${rooms == 1 ? '' : 's'} · $beds bed${beds == 1 ? '' : 's'}',
                  style: const TextStyle(
                      fontSize: 12, color: PgColors.primary, fontWeight: FontWeight.w600),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

// ─── Floors Tab ───────────────────────────────────────────────────────────

class _FloorsTab extends StatefulWidget {
  const _FloorsTab({
    required this.propertyId,
    required this.floorFuture,
    required this.onRefresh,
  });

  final dynamic propertyId;
  final Future<Map<String, dynamic>> floorFuture;
  final VoidCallback onRefresh;

  @override
  State<_FloorsTab> createState() => _FloorsTabState();
}

class _FloorsTabState extends State<_FloorsTab> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: widget.floorFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ErrorState(error: snapshot.error, onRetry: widget.onRefresh);
        }
        final data = snapshot.data ?? {};
        final floors = (data['items'] is List ? data['items'] as List : [])
            .cast<Map<String, dynamic>>();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ...floors.map((floor) => _FloorTile(floor: floor)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add Floor'),
              onPressed: () => _addFloor(context),
            ),
          ],
        );
      },
    );
  }

  void _addFloor(BuildContext context) async {
    final ctrl = TextEditingController();
    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Floor'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Floor Name (e.g. Ground Floor)'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) return;
              try {
                await context.read<AppState>().apiClient.post('/facilities', {
                  'parentFacilityId': widget.propertyId,
                  'facilityTypeId': 'FLOOR',
                  'facilityName': ctrl.text.trim(),
                });
                if (ctx.mounted) Navigator.pop(ctx, true);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (added == true) widget.onRefresh();
  }
}

// ─── Floor Tile (StatefulWidget — manages its own room list + Add Room) ───

class _FloorTile extends StatefulWidget {
  const _FloorTile({required this.floor});

  final Map<String, dynamic> floor;

  @override
  State<_FloorTile> createState() => _FloorTileState();
}

class _FloorTileState extends State<_FloorTile> {
  late Future<Map<String, dynamic>> _roomsFuture;

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  void _loadRooms() {
    final id = widget.floor['facilityId'];
    _roomsFuture = context.read<AppState>().apiClient.get('/floors/$id/rooms');
  }

  void _addRoom(BuildContext context) async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddRoomSheet(floorId: widget.floor['facilityId']),
    );
    if (added == true) setState(_loadRooms);
  }

  @override
  Widget build(BuildContext context) {
    final floor = widget.floor;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: PgColors.lavender,
          foregroundColor: PgColors.primary,
          child: const Icon(Icons.layers_outlined),
        ),
        title: Text('${floor['facilityName'] ?? 'Floor'}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Row(
          children: [
            if (floor['floorNumber'] != null)
              Text('Floor ${floor['floorNumber']}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            if ((floor['facilityCode'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: PgColors.lavender,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('${floor['facilityCode']}',
                    style: const TextStyle(
                        fontSize: 10, color: PgColors.primary, fontWeight: FontWeight.w700)),
              ),
            ],
          ],
        ),
        children: [
          FutureBuilder<Map<String, dynamic>>(
            future: _roomsFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final rooms = (snapshot.data?['items'] is List
                      ? snapshot.data!['items'] as List
                      : [])
                  .cast<Map<String, dynamic>>();
              if (rooms.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: Text('No rooms yet. Tap Add Room below.',
                      style: TextStyle(color: Colors.grey)),
                );
              }
              return Column(
                children: rooms.map((r) => _RoomListTile(room: r)).toList(),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Room'),
              style: OutlinedButton.styleFrom(
                foregroundColor: PgColors.primary,
                side: const BorderSide(color: PgColors.primary),
                padding: const EdgeInsets.symmetric(vertical: 8),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              onPressed: () => _addRoom(context),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Add Room Sheet (used from FloorTile; also imported by room_screen) ──

class _AddRoomSheet extends StatefulWidget {
  const _AddRoomSheet({this.floorId});

  final dynamic floorId;

  @override
  State<_AddRoomSheet> createState() => _AddRoomSheetState();
}

class _AddRoomSheetState extends State<_AddRoomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _roomNumber = TextEditingController();
  final _rent = TextEditingController();
  final _deposit = TextEditingController();
  final _capacity = TextEditingController();
  String _sharing = '2';
  dynamic _selectedFloorId;
  Future<Map<String, dynamic>>? _propFuture;
  Future<Map<String, dynamic>>? _floorDropFuture;
  Map<String, dynamic>? _selectedProp;

  @override
  void initState() {
    super.initState();
    _selectedFloorId = widget.floorId;
    if (widget.floorId == null) {
      _propFuture = context.read<AppState>().apiClient.get('/owner/properties');
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _roomNumber.dispose();
    _rent.dispose();
    _deposit.dispose();
    _capacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, padding + 20),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Text('Add Room',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context)),
              ]),
              const SizedBox(height: 16),

              // Cascading Property → Floor when opened without a pre-set floorId
              if (widget.floorId == null) ...[
                FutureBuilder<Map<String, dynamic>>(
                  future: _propFuture,
                  builder: (context, snap) {
                    if (!snap.hasData) return const LinearProgressIndicator();
                    final props = (snap.data?['items'] is List
                            ? snap.data!['items'] as List
                            : [])
                        .cast<Map<String, dynamic>>();
                    return DropdownButtonFormField<Map<String, dynamic>>(
                      value: _selectedProp,
                      decoration: const InputDecoration(
                          labelText: 'Property *',
                          prefixIcon: Icon(Icons.apartment_outlined)),
                      items: props
                          .map((p) => DropdownMenuItem(
                                value: p,
                                child: Text('${p['facilityName']}'),
                              ))
                          .toList(),
                      onChanged: (p) {
                        setState(() {
                          _selectedProp = p;
                          _selectedFloorId = null;
                          if (p != null) {
                            _floorDropFuture = context
                                .read<AppState>()
                                .apiClient
                                .get('/properties/${p['facilityId']}/floors');
                          }
                        });
                      },
                      validator: (v) => v == null ? 'Select a property' : null,
                    );
                  },
                ),
                const SizedBox(height: 12),
                if (_selectedProp != null && _floorDropFuture != null)
                  FutureBuilder<Map<String, dynamic>>(
                    future: _floorDropFuture,
                    builder: (context, snap) {
                      if (!snap.hasData) return const LinearProgressIndicator();
                      final floors = (snap.data?['items'] is List
                              ? snap.data!['items'] as List
                              : [])
                          .cast<Map<String, dynamic>>();
                      return DropdownButtonFormField<dynamic>(
                        value: _selectedFloorId,
                        decoration: const InputDecoration(
                            labelText: 'Floor *',
                            prefixIcon: Icon(Icons.layers_outlined)),
                        items: floors
                            .map((f) => DropdownMenuItem(
                                  value: f['facilityId'],
                                  child: Text('${f['facilityName']}'),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedFloorId = v),
                        validator: (v) => v == null ? 'Select a floor' : null,
                      );
                    },
                  ),
                const SizedBox(height: 12),
              ],

              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                    labelText: 'Room Name *',
                    prefixIcon: Icon(Icons.meeting_room_outlined)),
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _roomNumber,
                decoration: const InputDecoration(
                    labelText: 'Room Number', prefixIcon: Icon(Icons.tag)),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _sharing,
                decoration: const InputDecoration(
                    labelText: 'Sharing Type',
                    prefixIcon: Icon(Icons.people_outline)),
                items: const [
                  DropdownMenuItem(value: '1', child: Text('1-Sharing (Single)')),
                  DropdownMenuItem(value: '2', child: Text('2-Sharing (Double)')),
                  DropdownMenuItem(value: '3', child: Text('3-Sharing (Triple)')),
                  DropdownMenuItem(value: '4', child: Text('4-Sharing (Quad)')),
                  DropdownMenuItem(value: '5', child: Text('5-Sharing')),
                  DropdownMenuItem(value: '6', child: Text('6-Sharing')),
                ],
                onChanged: (v) => setState(() => _sharing = v ?? _sharing),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _rent,
                      decoration: const InputDecoration(
                          labelText: 'Monthly Rent (₹)',
                          prefixIcon: Icon(Icons.currency_rupee)),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _deposit,
                      decoration: const InputDecoration(labelText: 'Deposit (₹)'),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _capacity,
                decoration: const InputDecoration(
                    labelText: 'Capacity (beds)',
                    prefixIcon: Icon(Icons.bed_outlined)),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  return n == null || n < 1 ? 'Enter ≥ 1' : null;
                },
              ),
              const SizedBox(height: 20),
              AsyncActionButton(
                label: 'Add Room',
                onPressed: () async {
                  if (!_formKey.currentState!.validate()) return;
                  if (_selectedFloorId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Select a floor first')));
                    return;
                  }
                  try {
                    await context.read<AppState>().apiClient.post('/facilities', {
                      'parentFacilityId': _selectedFloorId,
                      'facilityTypeId': 'ROOM',
                      'facilityName': _name.text.trim(),
                      if (_roomNumber.text.isNotEmpty)
                        'roomNumber': _roomNumber.text.trim(),
                      'sharingType': _sharing,
                      if (_rent.text.isNotEmpty)
                        'monthlyRent': double.parse(_rent.text),
                      if (_deposit.text.isNotEmpty)
                        'securityDeposit': double.parse(_deposit.text),
                      if (_capacity.text.isNotEmpty)
                        'capacity': int.parse(_capacity.text),
                    });
                    if (mounted) Navigator.pop(context, true);
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(
                              e.toString().replaceFirst('Exception: ', ''))));
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomListTile extends StatelessWidget {
  const _RoomListTile({required this.room});

  final Map<String, dynamic> room;

  @override
  Widget build(BuildContext context) {
    final name = '${room['facilityName'] ?? 'Room'}';
    final number = room['roomNumber'];
    final sharing = room['sharingType'];
    final capacity = room['capacity'];
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: const Icon(Icons.meeting_room_outlined, color: PgColors.primary),
      title: Text(name),
      subtitle: Text([
        if (number != null) 'No. $number',
        if (sharing != null) '$sharing-Sharing',
        if (capacity != null) '$capacity bed${capacity == 1 ? '' : 's'}',
      ].join(' • ')),
      trailing: room['monthlyRent'] != null
          ? Text(_rupees(room['monthlyRent']),
              style: const TextStyle(fontWeight: FontWeight.w700, color: PgColors.primary))
          : null,
    );
  }
}

// ─── Amenities Tab ───────────────────────────────────────────────────────

class _AmenitiesTab extends StatelessWidget {
  const _AmenitiesTab();

  static const _amenities = [
    ('WiFi', Icons.wifi, 'High-speed internet'),
    ('Power Backup', Icons.bolt, 'Generator / inverter'),
    ('CCTV', Icons.videocam_outlined, '24-hour surveillance'),
    ('RO Water', Icons.water_drop_outlined, 'Purified drinking water'),
    ('Parking', Icons.local_parking, 'Two-wheeler & car parking'),
    ('Cleaning', Icons.cleaning_services_outlined, 'Daily room cleaning'),
    ('Food', Icons.restaurant_outlined, 'Breakfast & dinner'),
    ('Laundry', Icons.local_laundry_service_outlined, 'Washing machine access'),
    ('Air Conditioning', Icons.ac_unit, 'Room AC / cooler'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Available Amenities',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 4),
        const Text('Contact support to configure facility-level amenities.',
            style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _amenities
              .map((a) => SizedBox(
                    width: 160,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(children: [
                          CircleAvatar(
                              radius: 18,
                              backgroundColor: PgColors.lavender,
                              child: Icon(a.$2, color: PgColors.primary, size: 18)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(a.$1,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700, fontSize: 13)),
                                Text(a.$3,
                                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }
}

// ─── Add Property Sheet ──────────────────────────────────────────────────

class _AddPropertySheet extends StatefulWidget {
  const _AddPropertySheet();

  @override
  State<_AddPropertySheet> createState() => _AddPropertySheetState();
}

class _AddPropertySheetState extends State<_AddPropertySheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _capacity = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _capacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, padding + 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text('Add Property',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                    const Spacer(),
                    IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context)),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                      labelText: 'Property Name *',
                      prefixIcon: Icon(Icons.apartment_outlined)),
                  textInputAction: TextInputAction.next,
                  validator: (v) =>
                      v == null || v.trim().length < 2 ? 'Min 2 characters' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _desc,
                  decoration: const InputDecoration(
                      labelText: 'Address / Description',
                      prefixIcon: Icon(Icons.location_on_outlined)),
                  maxLines: 2,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _capacity,
                  decoration: const InputDecoration(
                      labelText: 'Estimated Total Bed Capacity',
                      prefixIcon: Icon(Icons.bed_outlined)),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textInputAction: TextInputAction.done,
                ),
                const SizedBox(height: 20),
                AsyncActionButton(
                  label: 'Add Property',
                  onPressed: () async {
                    if (!_formKey.currentState!.validate()) return;
                    final orgId = await context.read<AppState>().storage.read(key: 'organizationId');
                    try {
                      await context.read<AppState>().apiClient.post('/facilities', {
                        'parentFacilityId': int.parse(orgId ?? '0'),
                        'facilityTypeId': 'PROPERTY',
                        'facilityName': _name.text.trim(),
                        if (_desc.text.isNotEmpty) 'description': _desc.text.trim(),
                        if (_capacity.text.isNotEmpty) 'capacity': int.parse(_capacity.text),
                      });
                      if (mounted) Navigator.pop(context, true);
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Edit Property Sheet ─────────────────────────────────────────────────

class _EditPropertySheet extends StatefulWidget {
  const _EditPropertySheet({required this.property});

  final Map<String, dynamic> property;

  @override
  State<_EditPropertySheet> createState() => _EditPropertySheetState();
}

class _EditPropertySheetState extends State<_EditPropertySheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: '${widget.property['facilityName'] ?? ''}');
  late final _desc = TextEditingController(text: '${widget.property['description'] ?? ''}');
  late final _capacity =
      TextEditingController(text: widget.property['capacity']?.toString() ?? '');
  late String _status = '${widget.property['status'] ?? 'ACTIVE'}';

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _capacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, padding + 20),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text('Edit Property',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  const Spacer(),
                  IconButton(
                      icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                    labelText: 'Property Name *',
                    prefixIcon: Icon(Icons.apartment_outlined)),
                validator: (v) =>
                    v == null || v.trim().length < 2 ? 'Min 2 characters' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _desc,
                decoration: const InputDecoration(
                    labelText: 'Address / Description',
                    prefixIcon: Icon(Icons.location_on_outlined)),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _status,
                decoration:
                    const InputDecoration(labelText: 'Status', prefixIcon: Icon(Icons.info_outline)),
                items: const [
                  DropdownMenuItem(value: 'ACTIVE', child: Text('Active')),
                  DropdownMenuItem(value: 'INACTIVE', child: Text('Inactive')),
                  DropdownMenuItem(value: 'UNDER_MAINTENANCE', child: Text('Under Maintenance')),
                ],
                onChanged: (v) => setState(() => _status = v ?? _status),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _capacity,
                decoration: const InputDecoration(
                    labelText: 'Estimated Total Bed Capacity',
                    prefixIcon: Icon(Icons.bed_outlined)),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              const SizedBox(height: 20),
              AsyncActionButton(
                label: 'Save Changes',
                onPressed: () async {
                  if (!_formKey.currentState!.validate()) return;
                  final id = widget.property['facilityId'];
                  try {
                    await context.read<AppState>().apiClient.put('/facilities/$id', {
                      'facilityName': _name.text.trim(),
                      if (_desc.text.isNotEmpty) 'description': _desc.text.trim(),
                      'status': _status,
                      if (_capacity.text.isNotEmpty) 'capacity': int.parse(_capacity.text),
                    });
                    if (mounted) Navigator.pop(context, true);
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Shared Widgets ──────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status[0] + status.substring(1).toLowerCase().replaceAll('_', ' '),
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: PgColors.lavender,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: PgColors.primary),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: PgColors.primary)),
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: PgColors.lavender,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(fontWeight: FontWeight.w800, color: PgColors.primary)),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 48, color: PgColors.danger),
          const SizedBox(height: 12),
          const Text('Could not load data', style: TextStyle(fontWeight: FontWeight.w700)),
          Text('$error', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.onAction,
    this.actionLabel,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onAction;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: PgColors.primary),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
            if (onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: Text(actionLabel ?? 'Add'),
                onPressed: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
