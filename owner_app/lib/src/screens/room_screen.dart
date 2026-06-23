import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme/app_theme.dart';
import '../utils/date_utils.dart';
import '../widgets/async_action_button.dart';
import 'tenant_screen.dart' show AddTenantScreen;

// ─── Helpers ─────────────────────────────────────────────────────────────────

String _rupees(dynamic v) => v != null ? '₹$v' : '—';

// ─── Room Screen (facility tree: property → floor → room → bed) ───────────

class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key});

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        title: const Text('Rooms & Beds',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_outlined),
            tooltip: 'Add Room',
            onPressed: _openAddRoom,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE5E7EB)),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          children: [
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                hintText: 'Search properties, rooms…',
                prefixIcon: Icon(Icons.search),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                    return _RoomErrorState(
                        error: snapshot.error, onRetry: () => setState(_load));
                  }
                  final data = snapshot.data ?? {};
                  final rawList = data['items'];
                  final List raw = rawList is List ? rawList : [];
                  final props = raw
                      .cast<Map<String, dynamic>>()
                      .where((p) =>
                          _query.isEmpty ||
                          '${p['facilityName']}'.toLowerCase().contains(_query))
                      .toList();

                  if (props.isEmpty) {
                    return const _RoomEmptyState();
                  }
                  return RefreshIndicator(
                    onRefresh: () async => setState(_load),
                    child: ListView.separated(
                      itemCount: props.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) =>
                          _PropertyNode(property: props[i], query: _query),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openAddRoom() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _AddRoomSheet(),
    );
    if (added == true) setState(_load);
  }
}

// ─── Property Node ────────────────────────────────────────────────────────

class _PropertyNode extends StatefulWidget {
  const _PropertyNode({required this.property, required this.query});

  final Map<String, dynamic> property;
  final String query;

  @override
  State<_PropertyNode> createState() => _PropertyNodeState();
}

class _PropertyNodeState extends State<_PropertyNode> {
  Future<Map<String, dynamic>>? _floorFuture;
  bool _expanded = false;

  void _expand() {
    if (!_expanded) {
      final id = widget.property['facilityId'];
      _floorFuture =
          context.read<AppState>().apiClient.get('/properties/$id/floors');
    }
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final name = '${widget.property['facilityName'] ?? 'Property'}';
    final capacity = widget.property['capacity'];
    final code = '${widget.property['facilityCode'] ?? ''}';

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: PgColors.lavender,
              child: const Icon(Icons.apartment_outlined, color: PgColors.primary),
            ),
            title: Text(name,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text([
              if (code.isNotEmpty) code,
              if (capacity != null) '$capacity beds',
            ].join(' · ')),
            trailing: Icon(
                _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
            onTap: _expand,
          ),
          if (_expanded)
            _FloorsSection(
              floorFuture: _floorFuture!,
              propertyId: widget.property['facilityId'],
              query: widget.query,
            ),
        ],
      ),
    );
  }
}

// ─── Floors Section ───────────────────────────────────────────────────────

class _FloorsSection extends StatelessWidget {
  const _FloorsSection({
    required this.floorFuture,
    required this.propertyId,
    required this.query,
  });

  final Future<Map<String, dynamic>> floorFuture;
  final dynamic propertyId;
  final String query;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: floorFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final data = snapshot.data ?? {};
        final floors = (data['items'] is List ? data['items'] as List : [])
            .cast<Map<String, dynamic>>();

        if (floors.isEmpty) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Text('No floors added yet.',
                style: TextStyle(color: Colors.grey)),
          );
        }
        return Column(
          children: floors
              .map((f) => _FloorNode(floor: f, query: query))
              .toList(),
        );
      },
    );
  }
}

// ─── Floor Node ───────────────────────────────────────────────────────────

class _FloorNode extends StatefulWidget {
  const _FloorNode({required this.floor, required this.query});

  final Map<String, dynamic> floor;
  final String query;

  @override
  State<_FloorNode> createState() => _FloorNodeState();
}

class _FloorNodeState extends State<_FloorNode> {
  Future<Map<String, dynamic>>? _roomFuture;
  bool _expanded = false;

  void _expand() {
    if (!_expanded) {
      _loadRooms();
    }
    setState(() => _expanded = !_expanded);
  }

  void _loadRooms() {
    final id = widget.floor['facilityId'];
    _roomFuture = context.read<AppState>().apiClient.get('/floors/$id/rooms');
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
    final name = '${widget.floor['facilityName'] ?? 'Floor'}';
    return Column(
      children: [
        const Divider(height: 1, indent: 20, endIndent: 20),
        ListTile(
          contentPadding: const EdgeInsets.only(left: 40, right: 16),
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: PgColors.lavender,
            child: const Icon(Icons.layers_outlined, color: PgColors.primary, size: 16),
          ),
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: (widget.floor['facilityCode'] ?? '').toString().isNotEmpty
              ? Text('${widget.floor['facilityCode']}',
                  style: const TextStyle(fontSize: 11, color: PgColors.primary))
              : null,
          trailing: Icon(
              _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              size: 20),
          onTap: _expand,
        ),
        if (_expanded) ...[
          _RoomsSection(
            roomFuture: _roomFuture!,
            floorId: widget.floor['facilityId'],
            query: widget.query,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(52, 0, 16, 10),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Room'),
              style: OutlinedButton.styleFrom(
                foregroundColor: PgColors.primary,
                side: const BorderSide(color: PgColors.primary),
                padding: const EdgeInsets.symmetric(vertical: 6),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              onPressed: () => _addRoom(context),
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Rooms Section ────────────────────────────────────────────────────────

class _RoomsSection extends StatelessWidget {
  const _RoomsSection({
    required this.roomFuture,
    required this.floorId,
    required this.query,
  });

  final Future<Map<String, dynamic>> roomFuture;
  final dynamic floorId;
  final String query;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: roomFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final data = snapshot.data ?? {};
        final rooms = (data['items'] is List ? data['items'] as List : [])
            .cast<Map<String, dynamic>>()
            .where((r) =>
                query.isEmpty ||
                '${r['facilityName']}'.toLowerCase().contains(query))
            .toList();

        if (rooms.isEmpty) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(56, 0, 20, 12),
            child: Text('No rooms in this floor.',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          );
        }
        return Column(
          children: rooms
              .map((r) => _RoomTile(room: r))
              .toList(),
        );
      },
    );
  }
}

// ─── Room Tile ────────────────────────────────────────────────────────────

class _RoomTile extends StatelessWidget {
  const _RoomTile({required this.room});

  final Map<String, dynamic> room;

  @override
  Widget build(BuildContext context) {
    final name = '${room['facilityName'] ?? 'Room'}';
    final number = room['roomNumber'];
    final sharing = room['sharingType'];
    final capacity = room['capacity'];
    final rent = room['monthlyRent'];

    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => RoomDetailScreen(room: room))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(64, 8, 16, 8),
        child: Row(
          children: [
            const Icon(Icons.meeting_room_outlined, color: PgColors.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    [
                      if (number != null) 'No. $number',
                      if (sharing != null) '$sharing-Sharing',
                      if (capacity != null) '$capacity beds',
                    ].join(' · '),
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            ),
            if (rent != null)
              Text(_rupees(rent),
                  style: const TextStyle(
                      color: PgColors.primary, fontWeight: FontWeight.w700)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
          ],
        ),
      ),
    );
  }
}

// ─── Room Detail Screen ───────────────────────────────────────────────────

class RoomDetailScreen extends StatefulWidget {
  const RoomDetailScreen({required this.room, super.key});

  final Map<String, dynamic> room;

  @override
  State<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends State<RoomDetailScreen> {
  late Future<Map<String, dynamic>> _bedFuture;

  @override
  void initState() {
    super.initState();
    _loadBeds();
  }

  void _loadBeds() {
    final id = widget.room['facilityId'];
    _bedFuture = context.read<AppState>().apiClient.get('/rooms/$id/beds');
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.room;
    final name = '${r['facilityName'] ?? 'Room'}';

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            tooltip: 'Assign Tenant',
            onPressed: _openAssign,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Room info header
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 18)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      if (r['roomNumber'] != null)
                        _RoomBadge(label: 'No. ${r['roomNumber']}',
                            icon: Icons.tag),
                      if (r['sharingType'] != null)
                        _RoomBadge(label: '${r['sharingType']}',
                            icon: Icons.people_outline),
                      if (r['capacity'] != null)
                        _RoomBadge(label: '${r['capacity']} beds',
                            icon: Icons.bed_outlined),
                      if (r['monthlyRent'] != null)
                        _RoomBadge(label: _rupees(r['monthlyRent']),
                            icon: Icons.currency_rupee),
                      if (r['securityDeposit'] != null)
                        _RoomBadge(
                            label: 'Dep. ${_rupees(r['securityDeposit'])}',
                            icon: Icons.savings_outlined),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Beds
          const Text('Beds',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 8),
          FutureBuilder<Map<String, dynamic>>(
            future: _bedFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final data = snapshot.data ?? {};
              final beds = (data['items'] is List ? data['items'] as List : [])
                  .cast<Map<String, dynamic>>();
              if (beds.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No beds in this room.',
                        style: TextStyle(color: Colors.grey)),
                  ),
                );
              }
              return Column(
                children: beds
                    .map((bed) => _BedTile(bed: bed, onAssigned: _loadBeds))
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add Bed'),
            onPressed: () => _addBed(context),
          ),
        ],
      ),
    );
  }

  void _addBed(BuildContext context) async {
    final ctrl = TextEditingController();
    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Bed'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Bed Name (e.g. Bed A)'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) return;
              try {
                await context.read<AppState>().apiClient.post('/facilities', {
                  'parentFacilityId': widget.room['facilityId'],
                  'facilityTypeId': 'BED',
                  'facilityName': ctrl.text.trim(),
                });
                if (ctx.mounted) Navigator.pop(ctx, true);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      content:
                          Text(e.toString().replaceFirst('Exception: ', ''))));
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (added == true) setState(_loadBeds);
  }

  void _openAssign() async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AssignTenantSheet(room: widget.room),
    );
    if (done == true) setState(_loadBeds);
  }
}

class _BedTile extends StatelessWidget {
  const _BedTile({required this.bed, required this.onAssigned});

  final Map<String, dynamic> bed;
  final VoidCallback onAssigned;

  Future<void> _confirmCheckout(BuildContext context) async {
    final name = '${bed['facilityName'] ?? 'Bed'}';
    final tenant = '${bed['occupantName'] ?? 'tenant'}';
    final partyId = bed['occupantPartyId'];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Checkout Tenant',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text('Check out $tenant from $name?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: PgColors.primary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PgColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Checkout'),
          ),
        ],
      ),
    );
    if (confirmed != true || partyId == null) return;
    try {
      await context.read<AppState>().apiClient.post('/occupancy/checkout', {
        'partyId': partyId,
      });
      onAssigned();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = '${bed['facilityName'] ?? 'Bed'}';
    final tenant = bed['occupantName'] as String?;
    final isOccupied = tenant != null;
    final statusColor = isOccupied ? PgColors.danger : PgColors.success;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.12),
          child: Icon(Icons.bed_outlined, color: statusColor),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          isOccupied ? tenant : 'Available',
          style: TextStyle(
              color: isOccupied ? Colors.grey[700] : PgColors.success,
              fontWeight: FontWeight.w500),
        ),
        trailing: isOccupied
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: PgColors.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('Occupied',
                        style: TextStyle(
                            color: PgColors.danger, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: PgColors.danger,
                      side: const BorderSide(color: PgColors.danger),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => _confirmCheckout(context),
                    child: const Text('Checkout'),
                  ),
                ],
              )
            : FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: PgColors.primary,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                onPressed: () async {
                  final done = await showModalBottomSheet<bool>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                    builder: (_) => AssignBedSheet(
                      bedId: bed['facilityId'] as int,
                      bedName: name,
                    ),
                  );
                  if (done == true) onAssigned();
                },
                child: const Text('Assign'),
              ),
      ),
    );
  }
}

// ─── Add Room Sheet ───────────────────────────────────────────────────────

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

// ─── Assign Tenant Sheet ──────────────────────────────────────────────────

class _AssignTenantSheet extends StatefulWidget {
  const _AssignTenantSheet({required this.room});

  final Map<String, dynamic> room;

  @override
  State<_AssignTenantSheet> createState() => _AssignTenantSheetState();
}

class _AssignTenantSheetState extends State<_AssignTenantSheet> {
  late Future<Map<String, dynamic>> _tenantFuture;
  late Future<Map<String, dynamic>> _bedFuture;
  Map<String, dynamic>? _selectedTenant;
  Map<String, dynamic>? _selectedBed;
  final _rent = TextEditingController();
  final _deposit = TextEditingController();
  final _fromDate = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tenantFuture = context.read<AppState>().apiClient.get('/tenants');
    final id = widget.room['facilityId'];
    _bedFuture = context.read<AppState>().apiClient.get('/rooms/$id/beds');
    _rent.text = widget.room['monthlyRent']?.toString() ?? '';
    _deposit.text = widget.room['securityDeposit']?.toString() ?? '';
    _fromDate.text = todayDmy();
  }

  @override
  void dispose() {
    _rent.dispose();
    _deposit.dispose();
    _fromDate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, padding + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Text('Assign Tenant',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              const Spacer(),
              IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 8),
            Text('Room: ${widget.room['facilityName']}',
                style: const TextStyle(color: PgColors.primary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),

            // Select Bed
            const Text('Select Bed', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            FutureBuilder<Map<String, dynamic>>(
              future: _bedFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const LinearProgressIndicator();
                }
                final beds = (snapshot.data?['items'] is List
                        ? snapshot.data!['items'] as List
                        : [])
                    .cast<Map<String, dynamic>>()
                    .where((b) => b['occupantName'] == null)
                    .toList();

                if (beds.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('No available beds in this room.',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  );
                }

                return Column(
                  children: beds
                      .map((bed) => RadioListTile<Map<String, dynamic>>(
                            title: Text('${bed['facilityName']}'),
                            value: bed,
                            groupValue: _selectedBed,
                            onChanged: (v) => setState(() => _selectedBed = v),
                            activeColor: PgColors.primary,
                          ))
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 16),

            // Select Tenant
            const Text('Select Tenant', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            FutureBuilder<Map<String, dynamic>>(
              future: _tenantFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const LinearProgressIndicator();
                }
                final tenants = (snapshot.data?['items'] is List
                        ? snapshot.data!['items'] as List
                        : [])
                    .cast<Map<String, dynamic>>()
                    .where((t) => t['hasActiveAdmission'] != true)
                    .toList();

                if (tenants.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('No tenants without active admission.',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  );
                }

                return Column(
                  children: tenants
                      .map((t) => RadioListTile<Map<String, dynamic>>(
                            title: Text('${t['fullName']}'),
                            subtitle: Text('${t['mobileNumber'] ?? ''}'),
                            value: t,
                            groupValue: _selectedTenant,
                            onChanged: (v) => setState(() => _selectedTenant = v),
                            activeColor: PgColors.primary,
                          ))
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _fromDate,
              decoration: const InputDecoration(
                  labelText: 'Move-in Date (DD-MM-YYYY)',
                  prefixIcon: Icon(Icons.calendar_today_outlined)),
              keyboardType: TextInputType.number,
              inputFormatters: [DateDmyFormatter()],
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
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _deposit,
                    decoration: const InputDecoration(labelText: 'Deposit (₹)'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            AsyncActionButton(
              label: 'Assign',
              onPressed: () async {
                if (_selectedTenant == null || _selectedBed == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Select both a bed and a tenant')),
                  );
                  return;
                }
                try {
                  await context.read<AppState>().apiClient.post('/occupancy/assign-bed', {
                    'partyId': _selectedTenant!['tenantId'],
                    'bedFacilityId': _selectedBed!['facilityId'],
                    if (_fromDate.text.isNotEmpty)
                      'fromDate': dmyToIso(_fromDate.text.trim()),
                  });
                  if (mounted) Navigator.pop(context, true);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content:
                            Text(e.toString().replaceFirst('Exception: ', ''))));
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Assign Bed Sheet (public — used from workspace) ─────────────────────

class AssignBedSheet extends StatefulWidget {
  const AssignBedSheet({
    required this.bedId,
    required this.bedName,
    this.propertyId,
    this.sharingType,
    super.key,
  });

  final int bedId;
  final String bedName;
  final int? propertyId;
  final String? sharingType;

  @override
  State<AssignBedSheet> createState() => _AssignBedSheetState();
}

class _AssignBedSheetState extends State<AssignBedSheet> {
  late Future<Map<String, dynamic>> _tenantFuture;
  Map<String, dynamic>? _selectedTenant;
  final _fromDate = TextEditingController();
  final _checkoutDate = TextEditingController();
  final _rent = TextEditingController();
  final _deposit = TextEditingController();
  final _search = TextEditingController();
  String _searchQuery = '';
  double? _standardRent;

  @override
  void initState() {
    super.initState();
    _tenantFuture = context.read<AppState>().apiClient.get('/tenants');
    _fromDate.text = todayDmy();
    _loadStandardPrice();
    _search.addListener(() =>
        setState(() => _searchQuery = _search.text.toLowerCase().trim()));
  }

  void _reloadTenants() {
    setState(() {
      _tenantFuture = context.read<AppState>().apiClient.get('/tenants');
    });
  }

  Future<void> _goToAddTenant() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
          builder: (_) => AddTenantScreen(propertyId: widget.propertyId)),
    );
    if (created == true && mounted) _reloadTenants();
  }

  void _loadStandardPrice() async {
    if (widget.propertyId == null || widget.sharingType == null) return;
    try {
      final result = await context.read<AppState>().apiClient.get(
          '/properties/${widget.propertyId}/sharing-prices/${widget.sharingType}');
      if (!mounted) return;
      final rent = (result['monthlyRent'] as num?)?.toDouble();
      final deposit = (result['securityDeposit'] as num?)?.toDouble();
      setState(() {
        _standardRent = rent;
        if (rent != null && _rent.text.isEmpty) {
          _rent.text = rent.toStringAsFixed(0);
        }
        if (deposit != null && deposit > 0 && _deposit.text.isEmpty) {
          _deposit.text = deposit.toStringAsFixed(0);
        }
      });
    } catch (_) {}
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  void dispose() {
    _fromDate.dispose();
    _checkoutDate.dispose();
    _rent.dispose();
    _deposit.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, padding + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────
            Row(children: [
              const Text('Assign Tenant',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              const Spacer(),
              IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 4),
            Text('Bed: ${widget.bedName}',
                style: const TextStyle(
                    color: PgColors.primary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            // ── Select Tenant label + New Tenant button ──────────────
            Row(
              children: [
                const Text('Select Tenant',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const Spacer(),
                GestureDetector(
                  onTap: _goToAddTenant,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: PgColors.lavender,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person_add_outlined,
                            size: 14, color: PgColors.primary),
                        SizedBox(width: 5),
                        Text('New Tenant',
                            style: TextStyle(
                                fontSize: 12,
                                color: PgColors.primary,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // ── Tenant list section ──────────────────────────────────
            FutureBuilder<Map<String, dynamic>>(
              future: _tenantFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData && !snapshot.hasError) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: LinearProgressIndicator(),
                  );
                }
                if (snapshot.hasError) {
                  return Text('Failed to load tenants: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red, fontSize: 13));
                }

                // All inactive tenants, newest first
                final all = (snapshot.data?['items'] is List
                        ? snapshot.data!['items'] as List
                        : [])
                    .cast<Map<String, dynamic>>()
                    .where((t) => t['hasActiveAdmission'] != true)
                    .toList()
                  ..sort((a, b) {
                    final ai = (a['tenantId'] as num?)?.toInt() ?? 0;
                    final bi = (b['tenantId'] as num?)?.toInt() ?? 0;
                    return bi.compareTo(ai);
                  });

                // Search filter
                final tenants = _searchQuery.isEmpty
                    ? all
                    : all.where((t) {
                        final name =
                            '${t['fullName']}'.toLowerCase();
                        final phone =
                            '${t['mobileNumber'] ?? ''}'.toLowerCase();
                        return name.contains(_searchQuery) ||
                            phone.contains(_searchQuery);
                      }).toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Search bar
                    TextField(
                      controller: _search,
                      decoration: InputDecoration(
                        hintText: 'Search by name or phone…',
                        hintStyle: TextStyle(
                            color: Colors.grey.shade400, fontSize: 13),
                        prefixIcon: Icon(Icons.search,
                            size: 18, color: Colors.grey.shade400),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () => _search.clear(),
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: Colors.grey.shade200),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: Colors.grey.shade200),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: PgColors.primary, width: 1.5),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Tenant cards
                    if (all.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: const Text(
                            'No inactive tenants available.\nUse "New Tenant" to create one.',
                            style: TextStyle(
                                color: Colors.grey, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    else if (tenants.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'No tenants match "$_searchQuery".',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints:
                            const BoxConstraints(maxHeight: 220),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: tenants.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (context, i) {
                            final t = tenants[i];
                            final selected = _selectedTenant != null &&
                                _selectedTenant!['tenantId'] ==
                                    t['tenantId'];
                            final initials =
                                _initials('${t['fullName']}');
                            return GestureDetector(
                              onTap: () =>
                                  setState(() => _selectedTenant = t),
                              child: AnimatedContainer(
                                duration:
                                    const Duration(milliseconds: 160),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? PgColors.lavender
                                      : Colors.white,
                                  borderRadius:
                                      BorderRadius.circular(10),
                                  border: Border.all(
                                    color: selected
                                        ? PgColors.primary
                                        : Colors.grey.shade200,
                                    width: selected ? 1.5 : 1,
                                  ),
                                ),
                                child: Row(children: [
                                  // Avatar
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? PgColors.primary
                                          : const Color(0xFFE5E7EB),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        initials,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: selected
                                              ? Colors.white
                                              : const Color(0xFF374151),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${t['fullName']}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: selected
                                                ? PgColors.primary
                                                : const Color(
                                                    0xFF1A1A2E),
                                          ),
                                        ),
                                        if ((t['mobileNumber'] ?? '')
                                            .toString()
                                            .isNotEmpty)
                                          Text(
                                            '${t['mobileNumber']}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: selected
                                                  ? PgColors.primary
                                                      .withValues(alpha: .7)
                                                  : Colors.grey.shade500,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (selected)
                                    const Icon(Icons.check_circle_rounded,
                                        color: PgColors.primary, size: 20),
                                ]),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _fromDate,
              decoration: const InputDecoration(
                  labelText: 'Move-in Date (DD-MM-YYYY)',
                  prefixIcon: Icon(Icons.calendar_today_outlined)),
              keyboardType: TextInputType.number,
              inputFormatters: [DateDmyFormatter()],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _checkoutDate,
              decoration: const InputDecoration(
                  labelText: 'Expected Checkout Date (DD-MM-YYYY) — Optional',
                  prefixIcon: Icon(Icons.event_available_outlined),
                  helperText: 'Leave blank for open-ended stay'),
              keyboardType: TextInputType.number,
              inputFormatters: [DateDmyFormatter()],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _rent,
                    decoration: InputDecoration(
                      labelText: 'Monthly Rent (₹)',
                      prefixIcon: const Icon(Icons.currency_rupee),
                      helperText: _standardRent != null
                          ? 'Standard: ₹${_standardRent!.toStringAsFixed(0)}/mo'
                          : null,
                      helperStyle: const TextStyle(color: Color(0xFF2563EB), fontSize: 11),
                    ),
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
                    decoration:
                        const InputDecoration(labelText: 'Deposit (₹)'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            AsyncActionButton(
              label: 'Assign',
              onPressed: () async {
                if (_selectedTenant == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please select a tenant')));
                  return;
                }
                try {
                  await context.read<AppState>().apiClient.post('/occupancy/assign-bed', {
                    'partyId': _selectedTenant!['tenantId'],
                    'bedFacilityId': widget.bedId,
                    if (_fromDate.text.isNotEmpty)
                      'fromDate': dmyToIso(_fromDate.text.trim()),
                    if (_checkoutDate.text.isNotEmpty)
                      'expectedCheckoutDate': dmyToIso(_checkoutDate.text.trim()),
                    if (_rent.text.trim().isNotEmpty)
                      'monthlyRent': double.tryParse(_rent.text.trim()),
                    if (_deposit.text.trim().isNotEmpty)
                      'securityDeposit': double.tryParse(_deposit.text.trim()),
                  });
                  if (mounted) Navigator.pop(context, true);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(e.toString().replaceFirst('Exception: ', ''))));
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────────────

class _RoomBadge extends StatelessWidget {
  const _RoomBadge({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: PgColors.lavender, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: PgColors.primary),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(fontSize: 12, color: PgColors.primary)),
      ]),
    );
  }
}

class _RoomErrorState extends StatelessWidget {
  const _RoomErrorState({required this.error, required this.onRetry});
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
          const Text('Could not load rooms',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

class _RoomEmptyState extends StatelessWidget {
  const _RoomEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bed_outlined, size: 56, color: PgColors.primary),
            SizedBox(height: 16),
            Text('No properties found',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            SizedBox(height: 6),
            Text('Add properties and floors first to manage rooms.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
