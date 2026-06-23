import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme/app_theme.dart';
import 'tenant_screen.dart';
import 'billing_screen.dart';
import 'room_screen.dart' show AssignBedSheet;

class PropertyWorkspaceScreen extends StatefulWidget {
  final Map<String, dynamic> property;
  const PropertyWorkspaceScreen({required this.property, super.key});

  @override
  State<PropertyWorkspaceScreen> createState() => _PropertyWorkspaceScreenState();
}

class _PropertyWorkspaceScreenState extends State<PropertyWorkspaceScreen> {
  int _tab = 0;

  int get _propertyId => (widget.property['facilityId'] as num).toInt();
  String get _propertyName => '${widget.property['facilityName'] ?? 'Property'}';
  String get _propertyDesc => '${widget.property['description'] ?? ''}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _propertyName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A2E),
                letterSpacing: 0.1,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            if (_propertyDesc.isNotEmpty)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.location_on_outlined,
                      size: 11, color: Color(0xFF9CA3AF)),
                  const SizedBox(width: 2),
                  Text(
                    _propertyDesc,
                    style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9CA3AF),
                        fontWeight: FontWeight.w400),
                  ),
                ],
              ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.more_horiz_rounded,
                  size: 20, color: Color(0xFF374151)),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 8,
            shadowColor: Colors.black.withValues(alpha: .12),
            color: Colors.white,
            offset: const Offset(0, 8),
            onSelected: (v) {
              if (v == 'floors') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FloorsRoomsScreen(propertyId: _propertyId),
                  ),
                );
              } else if (v == 'edit') {
                showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(20))),
                  builder: (_) => _EditPropertySheet(
                    property: widget.property,
                    onSaved: (name, desc) => setState(() {
                      widget.property['facilityName'] = name;
                      widget.property['description'] = desc;
                    }),
                  ),
                );
              }
            },
            itemBuilder: (_) => [
              if (_tab == 0)
                PopupMenuItem<String>(
                  value: 'edit',
                  child: Row(children: [
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEBF3FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.edit_outlined,
                          size: 16, color: Color(0xFF2563EB)),
                    ),
                    const SizedBox(width: 12),
                    const Text('Edit Property',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A1A2E))),
                  ]),
                ),
              PopupMenuItem<String>(
                value: 'floors',
                child: Row(children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: PgColors.lavender,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.domain_outlined,
                        size: 16, color: PgColors.primary),
                  ),
                  const SizedBox(width: 12),
                  const Text('Floors & Rooms',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A2E))),
                ]),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE5E7EB)),
        ),
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          _PropertyDashboardTab(
            propertyId: _propertyId,
            property: widget.property,
            onNavigateToTenants: () => setState(() => _tab = 1),
          ),
          _PropertyTenantsTab(propertyId: _propertyId),
          _PropertyPaymentsTab(propertyId: _propertyId),
          const _PropertyReportsTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: Colors.white,
        indicatorColor: PgColors.lavender,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard, color: PgColors.primary),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people, color: PgColors.primary),
            label: 'Tenants',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long, color: PgColors.primary),
            label: 'Payments',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart, color: PgColors.primary),
            label: 'Reports',
          ),
        ],
      ),
    );
  }
}

// ─── Dashboard Tab (property overview + Floors & Rooms shortcut) ──────────────

class _PropertyDashboardTab extends StatefulWidget {
  final int propertyId;
  final Map<String, dynamic> property;
  final VoidCallback onNavigateToTenants;
  const _PropertyDashboardTab({
    required this.propertyId,
    required this.property,
    required this.onNavigateToTenants,
  });

  @override
  State<_PropertyDashboardTab> createState() => _PropertyDashboardTabState();
}

class _PropertyDashboardTabState extends State<_PropertyDashboardTab> {
  late Future<Map<String, dynamic>> _statsFuture;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  void _loadStats() {
    _statsFuture = context
        .read<AppState>()
        .apiClient
        .get('/properties/${widget.propertyId}/stats');
  }

  void _showVacantBeds(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _VacantBedsSheet(
        propertyId: widget.propertyId,
        onAssigned: () => setState(_loadStats),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => setState(_loadStats),
      child: ListView(
        children: [
          // ── Property hero card ─────────────────────────────────────
          _PropertyHeroCard(property: widget.property, statsFuture: _statsFuture),
          // ── Overview metric cards ──────────────────────────────────
          FutureBuilder<Map<String, dynamic>>(
            future: _statsFuture,
            builder: (context, snap) {
              final stats = snap.data ?? {};
              final totalTenants = stats['totalTenants'] ?? 0;
              final vacantBeds = stats['vacantBeds'] ?? 0;
              final totalBeds = (stats['totalBeds'] as num?)?.toInt() ?? 1;
              final vacPct = totalBeds > 0
                  ? '${((vacantBeds / totalBeds) * 100).round()}%'
                  : '0%';
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Overview',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A2E))),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            icon: Icons.people,
                            iconBg: const Color(0xFFEBF3FF),
                            iconColor: const Color(0xFF2563EB),
                            label: 'Total Tenants',
                            value: '$totalTenants',
                            sub: 'Active',
                            subColor: const Color(0xFF2563EB),
                            onTap: widget.onNavigateToTenants,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _StatCard(
                            icon: Icons.bed_outlined,
                            iconBg: const Color(0xFFFFF4E6),
                            iconColor: const Color(0xFFD97706),
                            label: 'Vacant Beds',
                            value: '$vacantBeds',
                            sub: vacPct,
                            subColor: const Color(0xFFD97706),
                            onTap: vacantBeds > 0
                                ? () => _showVacantBeds(context)
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          // ── Floors & Rooms shortcut ───────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: _ShortcutCard(
              icon: Icons.domain_outlined,
              title: 'Floors & Rooms',
              subtitle: 'Manage floors, rooms and bed assignments',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FloorsRoomsScreen(propertyId: widget.propertyId),
                ),
              ),
            ),
          ),
          // ── Shortcuts ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            child: _ShortcutCard(
              icon: Icons.currency_rupee_outlined,
              title: 'Room Pricing',
              subtitle: 'Set monthly rent per sharing type',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _SharingPricesScreen(propertyId: widget.propertyId),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortcutCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ShortcutCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: PgColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: PgColors.lavender, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: PgColors.primary, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

// ─── Vacant Beds Sheet ────────────────────────────────────────────────────────

class _VacantBedsSheet extends StatefulWidget {
  final int propertyId;
  final VoidCallback onAssigned;
  const _VacantBedsSheet({required this.propertyId, required this.onAssigned});

  @override
  State<_VacantBedsSheet> createState() => _VacantBedsSheetState();
}

class _VacantBedsSheetState extends State<_VacantBedsSheet>
    with SingleTickerProviderStateMixin {
  late Future<List<Map<String, dynamic>>> _future;
  List<Map<String, dynamic>> _beds = [];
  final _search = TextEditingController();
  late TabController _tabs;
  String _query = '';
  String? _selectedFloorId;
  String? _selectedRoomId;
  String? _selectedSharingType;
  String? _checkoutFilter;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
    _search.addListener(() => setState(() => _query = _search.text.toLowerCase()));
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  void _load() {
    _future = context
        .read<AppState>()
        .apiClient
        .get('/properties/${widget.propertyId}/vacant-beds')
        .then((d) {
          final items =
              (d['items'] is List ? d['items'] as List : []).cast<Map<String, dynamic>>();
          if (mounted) setState(() => _beds = items);
          return items;
        });
  }

  int get _activeFilterCount =>
      (_selectedFloorId != null ? 1 : 0) +
      (_selectedRoomId != null ? 1 : 0) +
      (_selectedSharingType != null ? 1 : 0) +
      (_checkoutFilter != null ? 1 : 0);

  void _clearAllFilters() => setState(() {
        _selectedFloorId = null;
        _selectedRoomId = null;
        _selectedSharingType = null;
        _checkoutFilter = null;
      });

  void _openFilterPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _VacantBedsFilterPanel(
        beds: _beds,
        initialFloorId: _selectedFloorId,
        initialRoomId: _selectedRoomId,
        initialSharingType: _selectedSharingType,
        initialCheckout: _checkoutFilter,
        onApply: (floor, room, sharing, checkout) => setState(() {
          _selectedFloorId = floor;
          _selectedRoomId = room;
          _selectedSharingType = sharing;
          _checkoutFilter = checkout;
        }),
      ),
    );
  }

  bool _passesCheckoutFilter(Map<String, dynamic> bed) {
    if (_checkoutFilter == null) return true;
    final raw = bed['expected_checkout_date'];
    if (raw == null) return false;
    final date = DateTime.tryParse('$raw');
    if (date == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    final diff = d.difference(today).inDays;
    switch (_checkoutFilter) {
      case 'today':  return diff == 0;
      case '1day':   return diff >= 0 && diff <= 1;
      case '2days':  return diff >= 0 && diff <= 2;
      case '3days':  return diff >= 0 && diff <= 3;
      case '7days':  return diff >= 0 && diff <= 7;
      case 'month':  return diff >= 0 && diff <= 30;
      default:       return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (ctx, sc) => Column(
        children: [
          // ── Handle ─────────────────────────────────────────────────
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),
          // ── Title row ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
            child: Row(children: [
              const Text('Vacant Beds',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              const Spacer(),
              IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx)),
            ]),
          ),
          // ── Search bar + filter icon ────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    hintText: 'Search bed, room or floor…',
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    prefixIcon:
                        Icon(Icons.search, size: 20, color: Colors.grey.shade400),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: PgColors.primary, width: 1.5),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _FilterIconButton(
                activeCount: _activeFilterCount,
                onTap: _openFilterPanel,
              ),
            ]),
          ),
          // ── Active filter pills ─────────────────────────────────────
          if (_activeFilterCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      if (_selectedFloorId != null)
                        _ActiveFilterPill(
                          label: _floorLabelFor(_selectedFloorId!),
                          onRemove: () => setState(() {
                            _selectedFloorId = null;
                            _selectedRoomId = null;
                          }),
                        ),
                      if (_selectedRoomId != null) ...[
                        const SizedBox(width: 6),
                        _ActiveFilterPill(
                          label: _roomLabelFor(_selectedRoomId!),
                          onRemove: () =>
                              setState(() => _selectedRoomId = null),
                        ),
                      ],
                      if (_selectedSharingType != null) ...[
                        const SizedBox(width: 6),
                        _ActiveFilterPill(
                          label: '$_selectedSharingType-Sharing',
                          color: const Color(0xFF7C3AED),
                          onRemove: () =>
                              setState(() => _selectedSharingType = null),
                        ),
                      ],
                      if (_checkoutFilter != null) ...[
                        const SizedBox(width: 6),
                        _ActiveFilterPill(
                          label: _checkoutLabel(_checkoutFilter!),
                          color: const Color(0xFF0D9488),
                          onRemove: () =>
                              setState(() => _checkoutFilter = null),
                        ),
                      ],
                    ]),
                  ),
                ),
                TextButton(
                  onPressed: _clearAllFilters,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red.shade400,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: const Text('Clear all'),
                ),
              ]),
            ),
          // ── Tab bar ──────────────────────────────────────────────────
          TabBar(
            controller: _tabs,
            labelColor: PgColors.primary,
            unselectedLabelColor: Colors.grey.shade500,
            indicatorColor: PgColors.primary,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            dividerColor: const Color(0xFFE5E7EB),
            tabs: const [
              Tab(text: 'Vacant'),
              Tab(text: 'Upcoming Vacant'),
            ],
          ),
          // ── Tab views ────────────────────────────────────────────────
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off, size: 40, color: Colors.grey),
                        const SizedBox(height: 8),
                        Text('${snapshot.error}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey)),
                        TextButton(
                            onPressed: () => setState(_load),
                            child: const Text('Retry')),
                      ],
                    ),
                  );
                }

                final beds = snapshot.data ?? [];
                final filtered = beds.where((b) {
                  if (_query.isNotEmpty) {
                    final q = _query;
                    if (!'${b['bed_name']}'.toLowerCase().contains(q) &&
                        !'${b['room_name']}'.toLowerCase().contains(q) &&
                        !'${b['floor_name']}'.toLowerCase().contains(q)) {
                      return false;
                    }
                  }
                  if (_selectedFloorId != null &&
                      '${b['floor_id']}' != _selectedFloorId) { return false; }
                  if (_selectedRoomId != null &&
                      '${b['room_id']}' != _selectedRoomId) { return false; }
                  if (_selectedSharingType != null &&
                      '${b['sharing_type']}' != _selectedSharingType) { return false; }
                  if (!_passesCheckoutFilter(b)) { return false; }
                  return true;
                }).toList();

                final vacant = filtered
                    .where((b) => '${b['bed_status']}' != 'UPCOMING')
                    .toList();
                final upcoming = filtered
                    .where((b) => '${b['bed_status']}' == 'UPCOMING')
                    .toList();

                Widget buildTabList(
                    List<Map<String, dynamic>> list, String emptyLabel, String emptySubLabel) {
                  if (list.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 72, height: 72,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Icon(Icons.bed_outlined,
                                size: 36, color: Colors.grey.shade400),
                          ),
                          const SizedBox(height: 16),
                          Text(emptyLabel,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 16)),
                          const SizedBox(height: 6),
                          Text(emptySubLabel,
                              style: TextStyle(
                                  color: Colors.grey.shade500, fontSize: 13)),
                        ],
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async => setState(_load),
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      itemCount: list.length,
                      itemBuilder: (context, i) => _VacantBedCard(
                        bed: list[i],
                        propertyId: widget.propertyId,
                        onAssigned: () {
                          setState(_load);
                          widget.onAssigned();
                        },
                      ),
                    ),
                  );
                }

                return TabBarView(
                  controller: _tabs,
                  children: [
                    buildTabList(
                      vacant,
                      beds.isEmpty ? 'No vacant beds' : 'No results',
                      beds.isEmpty
                          ? 'All beds are currently occupied.'
                          : 'Try adjusting your filters.',
                    ),
                    buildTabList(
                      upcoming,
                      beds.isEmpty ? 'No upcoming checkouts' : 'No results',
                      beds.isEmpty
                          ? 'No tenants have an upcoming checkout date.'
                          : 'Try adjusting your filters.',
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _floorLabelFor(String floorId) {
    for (final b in _beds) {
      if ('${b['floor_id']}' == floorId) {
        final num = b['floor_number'];
        return num != null ? 'Floor $num' : '${b['floor_name'] ?? 'Floor'}';
      }
    }
    return 'Floor';
  }

  String _roomLabelFor(String roomId) {
    for (final b in _beds) {
      if ('${b['room_id']}' == roomId) {
        final num = b['room_number'];
        return num != null ? 'Room $num' : '${b['room_name'] ?? 'Room'}';
      }
    }
    return 'Room';
  }
}

String _checkoutLabel(String filter) {
  switch (filter) {
    case 'today':  return 'Today';
    case '1day':   return 'By Tomorrow';
    case '2days':  return 'Within 2 Days';
    case '3days':  return 'Within 3 Days';
    case '7days':  return 'Within 7 Days';
    case 'month':  return 'This Month';
    default:       return filter;
  }
}

// ─── Filter Icon Button ────────────────────────────────────────────────────────

class _FilterIconButton extends StatelessWidget {
  final int activeCount;
  final VoidCallback onTap;
  const _FilterIconButton({required this.activeCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = activeCount > 0;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: active ? PgColors.primary : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: active ? PgColors.primary : Colors.grey.shade200),
            ),
            child: Icon(
              Icons.tune_rounded,
              color: active ? Colors.white : Colors.grey.shade600,
              size: 20,
            ),
          ),
          if (active)
            Positioned(
              top: -5,
              right: -5,
              child: Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                    color: Color(0xFFEF4444), shape: BoxShape.circle),
                child: Center(
                  child: Text('$activeCount',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Active Filter Pill ────────────────────────────────────────────────────────

class _ActiveFilterPill extends StatelessWidget {
  final String label;
  final Color? color;
  final VoidCallback onRemove;
  const _ActiveFilterPill(
      {required this.label, this.color, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final c = color ?? PgColors.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label,
            style: TextStyle(
                color: c, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: onRemove,
          child: Icon(Icons.close, size: 14, color: c),
        ),
      ]),
    );
  }
}

// ─── Vacant Beds Filter Panel ─────────────────────────────────────────────────

class _VacantBedsFilterPanel extends StatefulWidget {
  final List<Map<String, dynamic>> beds;
  final String? initialFloorId;
  final String? initialRoomId;
  final String? initialSharingType;
  final String? initialCheckout;
  final void Function(String? floor, String? room, String? sharing, String? checkout) onApply;
  const _VacantBedsFilterPanel({
    required this.beds,
    this.initialFloorId,
    this.initialRoomId,
    this.initialSharingType,
    this.initialCheckout,
    required this.onApply,
  });

  @override
  State<_VacantBedsFilterPanel> createState() =>
      _VacantBedsFilterPanelState();
}

class _VacantBedsFilterPanelState extends State<_VacantBedsFilterPanel> {
  String? _floorId;
  String? _roomId;
  String? _sharingType;
  String? _checkout;

  @override
  void initState() {
    super.initState();
    _floorId = widget.initialFloorId;
    _roomId = widget.initialRoomId;
    _sharingType = widget.initialSharingType;
    _checkout = widget.initialCheckout;
  }

  List<String> get _floorOrder {
    final order = <String>[];
    final seen = <String>{};
    for (final b in widget.beds) {
      final id = '${b['floor_id']}';
      if (!seen.contains(id)) {
        seen.add(id);
        order.add(id);
      }
    }
    return order;
  }

  Map<String, String> get _floorLabels {
    final labels = <String, String>{};
    for (final b in widget.beds) {
      final id = '${b['floor_id']}';
      if (!labels.containsKey(id)) {
        final num = b['floor_number'];
        labels[id] = num != null ? 'Floor $num' : '${b['floor_name'] ?? 'Floor'}';
      }
    }
    return labels;
  }

  List<String> get _roomOrder {
    final order = <String>[];
    final seen = <String>{};
    for (final b in widget.beds) {
      if (_floorId != null && '${b['floor_id']}' != _floorId) continue;
      final id = '${b['room_id']}';
      if (!seen.contains(id)) {
        seen.add(id);
        order.add(id);
      }
    }
    return order;
  }

  Map<String, String> get _roomLabels {
    final labels = <String, String>{};
    for (final b in widget.beds) {
      if (_floorId != null && '${b['floor_id']}' != _floorId) continue;
      final id = '${b['room_id']}';
      if (!labels.containsKey(id)) {
        final num = b['room_number'];
        labels[id] = num != null ? 'Room $num' : '${b['room_name'] ?? 'Room'}';
      }
    }
    return labels;
  }

  List<String> get _sharingTypes {
    final types = <String>[];
    final seen = <String>{};
    for (final b in widget.beds) {
      final t = b['sharing_type']?.toString();
      if (t != null && t.isNotEmpty && t != 'null' && !seen.contains(t)) {
        seen.add(t);
        types.add(t);
      }
    }
    types.sort((a, b) {
      final ai = int.tryParse(a);
      final bi = int.tryParse(b);
      if (ai != null && bi != null) { return ai.compareTo(bi); }
      return a.compareTo(b);
    });
    return types;
  }

  static const _checkoutOptions = [
    ['today', 'Today'],
    ['1day', 'Tomorrow'],
    ['2days', 'In 2 Days'],
    ['3days', 'In 3 Days'],
    ['7days', 'In 7 Days'],
    ['month', 'This Month'],
  ];

  @override
  Widget build(BuildContext context) {
    final floors = _floorOrder;
    final floorLbls = _floorLabels;
    final rooms = _roomOrder;
    final roomLbls = _roomLabels;
    final sharingTypes = _sharingTypes;
    final pad = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: pad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
            child: Row(children: [
              const Text('Filters',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() {
                  _floorId = null;
                  _roomId = null;
                  _sharingType = null;
                  _checkout = null;
                }),
                style: TextButton.styleFrom(
                    foregroundColor: Colors.red.shade400,
                    textStyle: const TextStyle(fontSize: 13)),
                child: const Text('Reset'),
              ),
              IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context)),
            ]),
          ),
          Container(height: 1, color: const Color(0xFFF3F4F6)),
          // Scrollable content
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Floor ──────────────────────────────────────────
                  _FilterSectionLabel(label: 'Floor'),
                  const SizedBox(height: 10),
                  if (floors.isEmpty)
                    Text('No floors available',
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 13))
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: floors
                          .map((id) => _PanelFilterChip(
                                label: floorLbls[id]!,
                                selected: _floorId == id,
                                onTap: () => setState(() {
                                  _floorId = _floorId == id ? null : id;
                                  _roomId = null;
                                }),
                              ))
                          .toList(),
                    ),
                  // ── Room (appears after floor is chosen) ───────────
                  if (_floorId != null && rooms.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _FilterSectionLabel(label: 'Room'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: rooms
                          .map((id) => _PanelFilterChip(
                                label: roomLbls[id]!,
                                selected: _roomId == id,
                                onTap: () => setState(() {
                                  _roomId = _roomId == id ? null : id;
                                }),
                              ))
                          .toList(),
                    ),
                  ],
                  // ── Sharing Type ───────────────────────────────────
                  if (sharingTypes.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _FilterSectionLabel(label: 'Sharing Type'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: sharingTypes
                          .map((t) => _PanelFilterChip(
                                label: '$t-Sharing',
                                selected: _sharingType == t,
                                accent: const Color(0xFF7C3AED),
                                onTap: () => setState(() {
                                  _sharingType = _sharingType == t ? null : t;
                                }),
                              ))
                          .toList(),
                    ),
                  ],
                  // ── Expected Checkout ──────────────────────────────
                  const SizedBox(height: 20),
                  Row(children: [
                    _FilterSectionLabel(label: 'Expected Checkout'),
                    const SizedBox(width: 8),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFBBF7D0)),
                      ),
                      child: const Text('Upcoming',
                          style: TextStyle(
                              fontSize: 10,
                              color: Color(0xFF16A34A),
                              fontWeight: FontWeight.w600)),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _checkoutOptions
                        .map((opt) => _PanelFilterChip(
                              label: opt[1],
                              selected: _checkout == opt[0],
                              accent: const Color(0xFF0D9488),
                              onTap: () => setState(() {
                                _checkout = _checkout == opt[0] ? null : opt[0];
                              }),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          // Apply button
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: FilledButton(
              onPressed: () {
                widget.onApply(_floorId, _roomId, _sharingType, _checkout);
                Navigator.pop(context);
              },
              style: FilledButton.styleFrom(
                backgroundColor: PgColors.primary,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700),
              ),
              child: const Text('Apply Filters'),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterSectionLabel extends StatelessWidget {
  final String label;
  const _FilterSectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(label,
        style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: Color(0xFF111827)));
  }
}

class _PanelFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? accent;
  const _PanelFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ?? PgColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? color : Colors.grey.shade300, width: 1.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }
}

// ─── Vacant Bed Card ──────────────────────────────────────────────────────────

class _VacantBedCard extends StatelessWidget {
  final Map<String, dynamic> bed;
  final int propertyId;
  final VoidCallback onAssigned;
  const _VacantBedCard(
      {required this.bed, required this.propertyId, required this.onAssigned});

  @override
  Widget build(BuildContext context) {
    final bedId = (bed['bed_id'] as num).toInt();
    final bedName = '${bed['bed_name'] ?? 'Bed'}';
    final roomName = '${bed['room_name'] ?? ''}';
    final floorName = '${bed['floor_name'] ?? ''}';
    final sharingType = bed['sharing_type']?.toString();
    final rent = bed['monthly_rent'];
    final expectedCheckout = bed['expected_checkout_date'];
    final isUpcoming = '${bed['bed_status']}' == 'UPCOMING';

    // Visual tokens per status
    final iconBg = isUpcoming ? const Color(0xFFFFF7ED) : const Color(0xFFDCFCE7);
    final iconColor = isUpcoming ? const Color(0xFFEA580C) : const Color(0xFF16A34A);
    final badgeBg = isUpcoming ? const Color(0xFFFFF7ED) : const Color(0xFFF0FDF4);
    final badgeBorder = isUpcoming ? const Color(0xFFFED7AA) : const Color(0xFFBBF7D0);
    final badgeText = isUpcoming ? const Color(0xFFEA580C) : const Color(0xFF16A34A);
    final badgeLabel = isUpcoming ? 'Checking Out' : 'Available';
    final borderColor = isUpcoming ? const Color(0xFFFED7AA) : const Color(0xFFE5E7EB);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top row: icon · name · status badge ──────────────────
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isUpcoming ? Icons.bed : Icons.bed_outlined,
                  color: iconColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(bedName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: Color(0xFF111827))),
                    const SizedBox(height: 3),
                    Row(children: [
                      Icon(Icons.location_on_outlined,
                          size: 12, color: Colors.grey.shade500),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text('$roomName  ·  $floorName',
                            style: TextStyle(
                                color: Colors.grey.shade500, fontSize: 12),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ]),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: badgeBorder),
                ),
                child: Text(badgeLabel,
                    style: TextStyle(
                        color: badgeText,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
            // ── Expected checkout banner (UPCOMING only) ─────────────
            if (isUpcoming && expectedCheckout != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFED7AA)),
                ),
                child: Row(children: [
                  const Icon(Icons.schedule_outlined,
                      size: 14, color: Color(0xFFEA580C)),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text('Checking out on  $expectedCheckout',
                        style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF9A3412),
                            fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
            ],
            // ── Divider ──────────────────────────────────────────────
            const SizedBox(height: 10),
            Container(height: 1, color: const Color(0xFFF3F4F6)),
            const SizedBox(height: 10),
            // ── Meta chips + action button ───────────────────────────
            Row(children: [
              if (sharingType != null) ...[
                _BedMetaChip(
                  icon: Icons.people_outline,
                  label: '$sharingType-Sharing',
                  color: PgColors.primary,
                ),
                const SizedBox(width: 7),
              ],
              if (rent != null)
                _BedMetaChip(
                  icon: Icons.currency_rupee,
                  label: '${_fmtRent(rent)}/mo',
                  color: const Color(0xFF0D9488),
                ),
              const Spacer(),
              if (isUpcoming)
                // Upcoming bed is still occupied — show informational label
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFED7AA)),
                  ),
                  child: const Text('Soon',
                      style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFFEA580C),
                          fontWeight: FontWeight.w600)),
                )
              else
                FilledButton.icon(
                  onPressed: () async {
                    final done = await showModalBottomSheet<bool>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(20))),
                      builder: (_) => AssignBedSheet(
                        bedId: bedId,
                        bedName: bedName,
                        propertyId: propertyId,
                        sharingType: sharingType,
                      ),
                    );
                    if (done == true) onAssigned();
                  },
                  icon: const Icon(Icons.person_add_outlined, size: 15),
                  label: const Text('Assign'),
                  style: FilledButton.styleFrom(
                    backgroundColor: PgColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    minimumSize: const Size(0, 36),
                  ),
                ),
            ]),
          ],
        ),
      ),
    );
  }

  String _fmtRent(dynamic value) {
    final n = double.tryParse('$value');
    if (n == null) return '$value';
    if (n >= 1000) {
      final s = (n / 1000).toStringAsFixed(1);
      return '₹${s.endsWith('.0') ? s.replaceAll('.0', '') : s}K';
    }
    return '₹${n.toStringAsFixed(0)}';
  }
}

class _BedMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _BedMetaChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ─── Floors & Rooms Screen ────────────────────────────────────────────────────

class FloorsRoomsScreen extends StatefulWidget {
  final int propertyId;
  const FloorsRoomsScreen({required this.propertyId, super.key});

  @override
  State<FloorsRoomsScreen> createState() => _FloorsRoomsScreenState();
}

class _FloorsRoomsScreenState extends State<FloorsRoomsScreen> {
  late Future<Map<String, dynamic>> _floorsFuture;
  int? _expandedFloorId;

  @override
  void initState() {
    super.initState();
    _loadFloors();
  }

  void _loadFloors() {
    _floorsFuture =
        context.read<AppState>().apiClient.get('/properties/${widget.propertyId}/floors');
  }

  void _addFloor() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddFloorSheet(propertyId: widget.propertyId),
    );
    if (added == true && mounted) setState(_loadFloors);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        centerTitle: false,
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Floors & Rooms',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            Text('Manage your property hierarchy',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                    fontWeight: FontWeight.w400)),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE5E7EB)),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addFloor,
        icon: const Icon(Icons.add),
        label: const Text('Add Floor'),
        backgroundColor: PgColors.primary,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(_loadFloors),
        child: FutureBuilder<Map<String, dynamic>>(
          future: _floorsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _WsError(
                  error: snapshot.error, onRetry: () => setState(_loadFloors));
            }
            final floors = (snapshot.data?['items'] as List?)
                    ?.cast<Map<String, dynamic>>() ??
                [];
            if (floors.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.domain_outlined,
                          size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      const Text('No floors yet',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 6),
                      Text('Tap "Add Floor" to build the layout.',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 13)),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Add Floor'),
                        onPressed: _addFloor,
                      ),
                    ],
                  ),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: floors.length,
              itemBuilder: (context, index) => _FloorTile(
                floor: floors[index],
                key: ValueKey(floors[index]['facilityId']),
                onReload: () => setState(_loadFloors),
                propertyId: widget.propertyId,
                expandedFloorId: _expandedFloorId,
                onFloorExpand: (id) => setState(() => _expandedFloorId = id),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── Property Hero Card ───────────────────────────────────────────────────────

class _PropertyHeroCard extends StatelessWidget {
  final Map<String, dynamic> property;
  final Future<Map<String, dynamic>> statsFuture;
  const _PropertyHeroCard({required this.property, required this.statsFuture});

  @override
  Widget build(BuildContext context) {
    final name = '${property['facilityName'] ?? 'Property'}';
    final desc = '${property['description'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF7C6FF7), Color(0xFF4A3FA6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6C5CE7).withValues(alpha: .35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              // Background decoration — faded building
              Positioned(
                right: -10,
                bottom: -10,
                child: Opacity(
                  opacity: 0.12,
                  child: const Icon(Icons.location_city,
                      color: Colors.white, size: 160),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Top: icon + name + location ──────────────────
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .2),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: .35),
                                width: 1.5),
                          ),
                          child: const Icon(Icons.apartment,
                              color: Colors.white, size: 32),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 24,
                                      letterSpacing: 0.3),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              if (desc.isNotEmpty) ...[
                                const SizedBox(height: 5),
                                Row(children: [
                                  const Icon(Icons.location_on_outlined,
                                      color: Colors.white70, size: 13),
                                  const SizedBox(width: 3),
                                  Expanded(
                                    child: Text(desc,
                                        style: const TextStyle(
                                            color: Colors.white70, fontSize: 12),
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                ]),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    // ── Stats row ────────────────────────────────────
                    FutureBuilder<Map<String, dynamic>>(
                      future: statsFuture,
                      builder: (context, snap) {
                        final s = snap.data ?? {};
                        return Row(
                          children: [
                            _HeroStat(
                                value: '${s['totalFloors'] ?? '—'}',
                                label: 'Floors'),
                            _HeroStatDivider(),
                            _HeroStat(
                                value: '${s['totalRooms'] ?? '—'}',
                                label: 'Rooms'),
                            _HeroStatDivider(),
                            _HeroStat(
                                value: '${s['totalBeds'] ?? '—'}',
                                label: 'Beds'),
                            _HeroStatDivider(),
                            _HeroStat(
                                value: '${s['occupiedBeds'] ?? '—'}',
                                label: 'Occupied Beds'),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String value;
  final String label;
  const _HeroStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 22)),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _HeroStatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 38,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      color: Colors.white.withValues(alpha: .3),
    );
  }
}

// ─── Stat Card ────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final String value;
  final String sub;
  final Color subColor;
  final VoidCallback? onTap;
  const _StatCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.sub,
    required this.subColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          splashColor: onTap != null ? iconColor.withValues(alpha: 0.12) : null,
          highlightColor: onTap != null ? iconColor.withValues(alpha: 0.07) : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                          color: iconBg, borderRadius: BorderRadius.circular(10)),
                      child: Icon(icon, color: iconColor, size: 20),
                    ),
                    if (onTap != null) ...[
                      const Spacer(),
                      Icon(Icons.chevron_right_rounded,
                          size: 16, color: Colors.grey.shade400),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Text(label,
                    style: const TextStyle(
                        fontSize: 10, color: Color(0xFF6B7280), fontWeight: FontWeight.w500),
                    maxLines: 2),
                const SizedBox(height: 4),
                Text(value,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E))),
                const SizedBox(height: 2),
                Text(sub,
                    style: TextStyle(fontSize: 11, color: subColor, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Floor Tile ───────────────────────────────────────────────────────────────

class _FloorTile extends StatefulWidget {
  final Map<String, dynamic> floor;
  final VoidCallback onReload;
  final int propertyId;
  final int? expandedFloorId;
  final void Function(int?) onFloorExpand;
  const _FloorTile({
    required this.floor,
    required this.onReload,
    required this.propertyId,
    required this.expandedFloorId,
    required this.onFloorExpand,
    super.key,
  });

  @override
  State<_FloorTile> createState() => _FloorTileState();
}

class _FloorTileState extends State<_FloorTile> {
  Future<Map<String, dynamic>>? _roomsFuture;
  int? _expandedRoomId;

  int get _floorId => (widget.floor['facilityId'] as num).toInt();
  String get _floorName => '${widget.floor['facilityName'] ?? 'Floor'}';
  String get _floorCode => '${widget.floor['facilityCode'] ?? ''}';
  bool get _expanded => widget.expandedFloorId == _floorId;

  @override
  void didUpdateWidget(_FloorTile old) {
    super.didUpdateWidget(old);
    final wasExpanded = old.expandedFloorId == _floorId;
    if (!wasExpanded && _expanded && _roomsFuture == null) {
      _roomsFuture = context.read<AppState>().apiClient.get('/floors/$_floorId/rooms');
    }
    if (wasExpanded && !_expanded) {
      _expandedRoomId = null;
    }
  }

  void _toggle() => widget.onFloorExpand(_expanded ? null : _floorId);

  void _loadRooms() {
    setState(() {
      _roomsFuture = context.read<AppState>().apiClient.get('/floors/$_floorId/rooms');
    });
  }

  void _addRoom() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddRoomSheet(floorId: _floorId, floorName: _floorName),
    );
    if (added == true && mounted) setState(_loadRooms);
  }

  void _editFloor() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EditFloorSheet(floor: widget.floor),
    );
    if (saved == true) widget.onReload();
  }

  @override
  Widget build(BuildContext context) {
    final floorNum = widget.floor['floorNumber'];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: const Color(0xFFFAF8FF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE9D5FF), width: 1),
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
            leading: CircleAvatar(
              backgroundColor: PgColors.lavender,
              child: Text(
                floorNum != null ? '$floorNum' : _floorCode.split('_').last,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: PgColors.primary),
              ),
            ),
            title: Text(_floorName, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: _floorCode.isNotEmpty
                ? Text(_floorCode, style: const TextStyle(fontSize: 12, color: Colors.grey))
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _toggle,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _expanded ? PgColors.lavender : Colors.transparent,
                      border: Border.all(color: const Color(0xFFE9D5FF)),
                    ),
                    child: Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color:
                          _expanded ? PgColors.primary : Colors.grey.shade600,
                      size: 20,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert,
                      size: 20, color: Colors.grey.shade600),
                  padding: EdgeInsets.zero,
                  onSelected: (v) {
                    if (v == 'edit') _editFloor();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Edit Floor'),
                      ]),
                    ),
                  ],
                ),
              ],
            ),
            onTap: _toggle,
          ),
          if (_expanded)
            FutureBuilder<Map<String, dynamic>>(
              future: _roomsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('Failed to load rooms',
                        style: const TextStyle(color: Colors.red)),
                  );
                }
                final rooms =
                    (snapshot.data?['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (rooms.isEmpty)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(0, 4, 0, 8),
                          child: Text('No rooms yet.',
                              style: TextStyle(color: Colors.grey, fontSize: 13)),
                        ),
                      // Timeline rows
                      ...rooms.asMap().entries.map((entry) {
                        final isLast = entry.key == rooms.length - 1;
                        return IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 16,
                                child: Column(
                                  children: [
                                    Container(
                                        width: 2,
                                        height: 20,
                                        color: const Color(0xFFD8B4FE)),
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white,
                                        border: Border.all(
                                            color: Colors.grey.shade400, width: 1.5),
                                      ),
                                    ),
                                    if (!isLast)
                                      Expanded(
                                        child: Container(
                                            width: 2,
                                            color: const Color(0xFFD8B4FE)),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _RoomTile(
                                  room: entry.value,
                                  key: ValueKey(entry.value['facilityId']),
                                  onReload: () => setState(_loadRooms),
                                  propertyId: widget.propertyId,
                                  expandedRoomId: _expandedRoomId,
                                  onRoomExpand: (id) => setState(() => _expandedRoomId = id),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _addRoom,
                        icon: const Icon(Icons.meeting_room_outlined, size: 16),
                        label: const Text('Add Room'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: PgColors.primary,
                          side: const BorderSide(color: PgColors.primary),
                          minimumSize: const Size(double.infinity, 44),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ─── Room Tile ────────────────────────────────────────────────────────────────

class _RoomTile extends StatefulWidget {
  final Map<String, dynamic> room;
  final VoidCallback onReload;
  final int propertyId;
  final int? expandedRoomId;
  final void Function(int?) onRoomExpand;
  const _RoomTile({
    required this.room,
    required this.onReload,
    required this.propertyId,
    required this.expandedRoomId,
    required this.onRoomExpand,
    super.key,
  });

  @override
  State<_RoomTile> createState() => _RoomTileState();
}

class _RoomTileState extends State<_RoomTile> {
  Future<Map<String, dynamic>>? _bedsFuture;

  int get _roomId => (widget.room['facilityId'] as num).toInt();
  String get _roomName => '${widget.room['facilityName'] ?? 'Room'}';
  String get _roomCode => '${widget.room['facilityCode'] ?? ''}';
  bool get _expanded => widget.expandedRoomId == _roomId;

  @override
  void didUpdateWidget(_RoomTile old) {
    super.didUpdateWidget(old);
    final wasExpanded = old.expandedRoomId == _roomId;
    if (!wasExpanded && _expanded && _bedsFuture == null) {
      _bedsFuture = context.read<AppState>().apiClient.get('/rooms/$_roomId/beds');
    }
  }

  void _toggle() => widget.onRoomExpand(_expanded ? null : _roomId);

  void _loadBeds() {
    setState(() {
      _bedsFuture = context.read<AppState>().apiClient.get('/rooms/$_roomId/beds');
    });
  }

  void _addBed() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddBedSheet(roomId: _roomId, roomName: _roomName),
    );
    if (added == true && mounted) setState(_loadBeds);
  }

  void _editRoom() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EditRoomSheet(room: widget.room),
    );
    if (saved == true) {
      _loadBeds();
      widget.onReload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sharing = widget.room['sharingType'] as String?;
    final sharingLabel = sharing != null ? '$sharing-Sharing' : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        children: [
          // ── Header row ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            child: Row(
              children: [
                // Room icon
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDBEAFE),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.meeting_room_outlined,
                      color: Color(0xFF2563EB), size: 20),
                ),
                const SizedBox(width: 10),
                // Name + code + sharing
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_roomName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      Row(
                        children: [
                          if (_roomCode.isNotEmpty)
                            Text(_roomCode,
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey)),
                          if (_roomCode.isNotEmpty && sharingLabel != null)
                            Container(
                              width: 4,
                              height: 4,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.grey),
                            ),
                          if (sharingLabel != null)
                            Text(sharingLabel,
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ],
                  ),
                ),
                // Expand/collapse circle
                InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: _toggle,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 18,
                      color: const Color(0xFF2563EB),
                    ),
                  ),
                ),
                // 3-dots menu
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert,
                      size: 20, color: Colors.grey.shade600),
                  padding: EdgeInsets.zero,
                  onSelected: (v) {
                    if (v == 'edit') _editRoom();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: 'edit',
                        child: Row(children: [
                          Icon(Icons.edit_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Edit Room'),
                        ])),
                  ],
                ),
              ],
            ),
          ),
          // ── Expanded beds ─────────────────────────────────────────────
          if (_expanded) ...[
            const Divider(height: 1, color: Color(0xFFBFDBFE)),
            FutureBuilder<Map<String, dynamic>>(
              future: _bedsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child:
                        Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('Failed to load beds',
                        style:
                            const TextStyle(color: Colors.red, fontSize: 12)),
                  );
                }
                final beds = (snapshot.data?['items'] as List?)
                        ?.cast<Map<String, dynamic>>() ??
                    [];
                final capacity = widget.room['capacity'] as int?;
                final atCapacity = capacity != null && beds.length >= capacity;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (beds.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 6),
                          child: Text('No beds yet.',
                              style: TextStyle(
                                  color: Colors.grey, fontSize: 12)),
                        ),
                      ...beds.map((bed) => _BedTile(
                            bed: bed,
                            onChanged: () => setState(_loadBeds),
                            propertyId: widget.propertyId,
                            sharingType: widget.room['sharingType'] as String?,
                          )),
                      const SizedBox(height: 4),
                      if (atCapacity)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_outline,
                                size: 13, color: Colors.grey[400]),
                            const SizedBox(width: 5),
                            Text('All $capacity beds added',
                                style: TextStyle(
                                    color: Colors.grey[500], fontSize: 12)),
                          ],
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: _addBed,
                          icon: const Icon(Icons.add, size: 14),
                          label: const Text('Add Bed'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: PgColors.primary,
                            side: const BorderSide(color: PgColors.primary),
                            minimumSize: const Size(double.infinity, 36),
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Bed Tile ─────────────────────────────────────────────────────────────────

class _BedTile extends StatelessWidget {
  final Map<String, dynamic> bed;
  final VoidCallback onChanged;
  final int? propertyId;
  final String? sharingType;
  const _BedTile({
    required this.bed,
    required this.onChanged,
    this.propertyId,
    this.sharingType,
  });

  @override
  Widget build(BuildContext context) {
    final name = '${bed['facilityName'] ?? 'Bed'}';
    final occupantName = bed['occupantName'] as String?;
    final isOccupied = occupantName != null;
    final bedId = (bed['facilityId'] as num).toInt();
    final occupantPartyId = bed['occupantPartyId'] != null
        ? (bed['occupantPartyId'] as num).toInt()
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isOccupied ? const Color(0xFFFFF1F2) : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: isOccupied
                ? const Color(0xFFFECACA)
                : const Color(0xFFBBF7D0)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: isOccupied && occupantPartyId != null
              ? () => _goToTenant(context, occupantPartyId)
              : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            child: Row(
          children: [
            // Bed icon container
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isOccupied
                    ? const Color(0xFFFECACA)
                    : const Color(0xFFBBF7D0),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isOccupied ? Icons.bed : Icons.bed_outlined,
                color: isOccupied ? PgColors.danger : PgColors.success,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            // Name + status
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(
                    isOccupied ? occupantName : 'Available',
                    style: TextStyle(
                        color: isOccupied
                            ? Colors.grey[600]
                            : PgColors.success,
                        fontSize: 12),
                  ),
                ],
              ),
            ),
            // Status badge
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isOccupied
                    ? PgColors.danger.withValues(alpha: .1)
                    : PgColors.success.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                isOccupied ? 'Occupied' : 'Available',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isOccupied ? PgColors.danger : PgColors.success),
              ),
            ),
            // 3-dots menu
            PopupMenuButton<String>(
              icon:
                  Icon(Icons.more_vert, size: 20, color: Colors.grey.shade600),
              padding: EdgeInsets.zero,
              onSelected: (v) async {
                if (v == 'assign') {
                  final done = await showModalBottomSheet<bool>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(20))),
                    builder: (_) => AssignBedSheet(
                      bedId: bedId,
                      bedName: name,
                      propertyId: propertyId,
                      sharingType: sharingType,
                    ),
                  );
                  if (done == true) onChanged();
                } else if (v == 'checkout') {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Checkout Tenant'),
                      content: Text(
                          'Check out ${occupantName ?? 'this tenant'} from $name?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel')),
                        FilledButton(
                            style: FilledButton.styleFrom(
                                backgroundColor: PgColors.danger),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Checkout')),
                      ],
                    ),
                  );
                  if (confirm == true && occupantPartyId != null) {
                    try {
                      await context
                          .read<AppState>()
                          .apiClient
                          .post('/occupancy/checkout', {
                        'partyId': occupantPartyId,
                      });
                      onChanged();
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(e
                                .toString()
                                .replaceFirst('Exception: ', ''))));
                      }
                    }
                  }
                } else if (v == 'edit') {
                  final saved = await showModalBottomSheet<bool>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(20))),
                    builder: (_) => _EditBedSheet(bed: bed),
                  );
                  if (saved == true) onChanged();
                }
              },
              itemBuilder: (_) => [
                if (!isOccupied)
                  const PopupMenuItem(
                      value: 'assign',
                      child: Row(children: [
                        Icon(Icons.person_add_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Assign Tenant'),
                      ])),
                if (isOccupied)
                  const PopupMenuItem(
                      value: 'checkout',
                      child: Row(children: [
                        Icon(Icons.logout, size: 18),
                        SizedBox(width: 8),
                        Text('Checkout Tenant'),
                      ])),
                const PopupMenuItem(
                    value: 'edit',
                    child: Row(children: [
                      Icon(Icons.edit_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Edit Bed'),
                    ])),
              ],
            ),
          ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _goToTenant(BuildContext context, int partyId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final tenant =
          await context.read<AppState>().apiClient.get('/tenants/$partyId');
      if (context.mounted) {
        Navigator.pop(context);
        Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => TenantDetailScreen(tenant: tenant)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }
}

// ─── Tenants Tab ──────────────────────────────────────────────────────────────

class _PropertyTenantsTab extends StatelessWidget {
  final int propertyId;
  const _PropertyTenantsTab({required this.propertyId});

  @override
  Widget build(BuildContext context) => TenantScreen(propertyId: propertyId);
}

// ─── Payments Tab ─────────────────────────────────────────────────────────────

class _PropertyPaymentsTab extends StatelessWidget {
  final int propertyId;
  const _PropertyPaymentsTab({required this.propertyId});

  @override
  Widget build(BuildContext context) => BillingScreen(embedded: true, propertyId: propertyId);
}

// ─── Reports Tab ──────────────────────────────────────────────────────────────

class _PropertyReportsTab extends StatelessWidget {
  const _PropertyReportsTab();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                  color: PgColors.lavender, borderRadius: BorderRadius.circular(18)),
              child: const Icon(Icons.bar_chart, size: 36, color: PgColors.primary),
            ),
            const SizedBox(height: 16),
            const Text('Reports',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            const SizedBox(height: 8),
            Text('Reports & analytics coming soon.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}

// ─── Edit Property Sheet ──────────────────────────────────────────────────────

class _EditPropertySheet extends StatefulWidget {
  final Map<String, dynamic> property;
  final void Function(String name, String desc) onSaved;
  const _EditPropertySheet({required this.property, required this.onSaved});

  @override
  State<_EditPropertySheet> createState() => _EditPropertySheetState();
}

class _EditPropertySheetState extends State<_EditPropertySheet> {
  late final TextEditingController _name;
  late final TextEditingController _desc;
  late final TextEditingController _capacity;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
        text: '${widget.property['facilityName'] ?? ''}');
    _desc = TextEditingController(
        text: '${widget.property['description'] ?? ''}');
    _capacity = TextEditingController(
        text: widget.property['capacity'] != null
            ? '${widget.property['capacity']}'
            : '');
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Property name must be at least 2 characters')));
      return;
    }
    setState(() => _saving = true);
    try {
      final facilityId = (widget.property['facilityId'] as num).toInt();
      await context.read<AppState>().apiClient.put('/facilities/$facilityId', {
        'facilityName': _name.text.trim(),
        'description': _desc.text.trim(),
        if (_capacity.text.trim().isNotEmpty)
          'capacity': int.tryParse(_capacity.text.trim()),
      });
      if (mounted) {
        widget.onSaved(_name.text.trim(), _desc.text.trim());
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, pad + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Text('Edit Property',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              const Spacer(),
              IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: 'Property Name *',
                  prefixIcon: Icon(Icons.apartment_outlined)),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              decoration: const InputDecoration(
                  labelText: 'Address / Location',
                  prefixIcon: Icon(Icons.location_on_outlined)),
              maxLines: 2,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _capacity,
              decoration: const InputDecoration(
                  labelText: 'Estimated Total Bed Capacity',
                  prefixIcon: Icon(Icons.bed_outlined)),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Add Sheets ───────────────────────────────────────────────────────────────

class _AddFloorSheet extends StatefulWidget {
  final int propertyId;
  const _AddFloorSheet({required this.propertyId});

  @override
  State<_AddFloorSheet> createState() => _AddFloorSheetState();
}

class _AddFloorSheetState extends State<_AddFloorSheet> {
  final _nameCtrl = TextEditingController();
  final _numCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _numCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Floor name is required')));
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<AppState>().apiClient.post('/facilities', {
        'parentFacilityId': widget.propertyId,
        'facilityTypeId': 'FLOOR',
        'facilityName': _nameCtrl.text.trim(),
        if (_numCtrl.text.trim().isNotEmpty)
          'floorNumber': int.tryParse(_numCtrl.text.trim()),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, pad + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Text('Add Floor',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const Spacer(),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
                labelText: 'Floor Name *', hintText: 'e.g. Ground Floor'),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _numCtrl,
            decoration: const InputDecoration(
                labelText: 'Floor Number (optional)', hintText: 'e.g. 0, 1, 2'),
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 18, width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Add Floor'),
          ),
        ],
      ),
    );
  }
}

class _AddRoomSheet extends StatefulWidget {
  final int floorId;
  final String floorName;
  const _AddRoomSheet({required this.floorId, required this.floorName});

  @override
  State<_AddRoomSheet> createState() => _AddRoomSheetState();
}

class _AddRoomSheetState extends State<_AddRoomSheet> {
  final _nameCtrl = TextEditingController();
  final _roomNumCtrl = TextEditingController();
  String _sharing = '2';
  bool _saving = false;

  static const _sharingOptions = [
    ('1', '1-Sharing (Single)'),
    ('2', '2-Sharing (Double)'),
    ('3', '3-Sharing (Triple)'),
    ('4', '4-Sharing'),
    ('5', '5-Sharing'),
    ('6', '6-Sharing'),
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _roomNumCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Room name is required')));
      return;
    }
    setState(() => _saving = true);
    try {
      final capacity = int.tryParse(_sharing) ?? 1;
      final result = await context.read<AppState>().apiClient.post('/facilities', {
        'parentFacilityId': widget.floorId,
        'facilityTypeId': 'ROOM',
        'facilityName': _nameCtrl.text.trim(),
        'sharingType': _sharing,
        'capacity': capacity,
        if (_roomNumCtrl.text.trim().isNotEmpty) 'roomNumber': _roomNumCtrl.text.trim(),
      });
      final roomId = result['facilityId'];
      if (roomId != null) {
        for (int i = 1; i <= capacity; i++) {
          await context.read<AppState>().apiClient.post('/facilities', {
            'parentFacilityId': roomId,
            'facilityTypeId': 'BED',
            'facilityName': 'BED$i',
            'capacity': 1,
          });
        }
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, pad + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text('Add Room — ${widget.floorName}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
                labelText: 'Room Name *', hintText: 'e.g. Room 101'),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _roomNumCtrl,
            decoration: const InputDecoration(
                labelText: 'Room Number (optional)', hintText: 'e.g. 101'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _sharing,
            decoration: const InputDecoration(labelText: 'Sharing Type'),
            items: _sharingOptions
                .map((opt) => DropdownMenuItem(value: opt.$1, child: Text(opt.$2)))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _sharing = v);
            },
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 18, width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Add Room'),
          ),
        ],
      ),
    );
  }
}

class _AddBedSheet extends StatefulWidget {
  final int roomId;
  final String roomName;
  const _AddBedSheet({required this.roomId, required this.roomName});

  @override
  State<_AddBedSheet> createState() => _AddBedSheetState();
}

class _AddBedSheetState extends State<_AddBedSheet> {
  final _nameCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Bed name is required')));
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<AppState>().apiClient.post('/facilities', {
        'parentFacilityId': widget.roomId,
        'facilityTypeId': 'BED',
        'facilityName': _nameCtrl.text.trim(),
        'capacity': 1,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, pad + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text('Add Bed — ${widget.roomName}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
                labelText: 'Bed Name *', hintText: 'e.g. Bed A, Bed 1'),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 18, width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Add Bed'),
          ),
        ],
      ),
    );
  }
}

// ─── Edit Floor Sheet ─────────────────────────────────────────────────────────

class _EditFloorSheet extends StatefulWidget {
  final Map<String, dynamic> floor;
  const _EditFloorSheet({required this.floor});

  @override
  State<_EditFloorSheet> createState() => _EditFloorSheetState();
}

class _EditFloorSheetState extends State<_EditFloorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _floorNum;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
        text: '${widget.floor['facilityName'] ?? ''}');
    _floorNum = TextEditingController(
        text: widget.floor['floorNumber'] != null
            ? '${widget.floor['floorNumber']}'
            : '');
  }

  @override
  void dispose() {
    _name.dispose();
    _floorNum.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Floor name is required')));
      return;
    }
    setState(() => _saving = true);
    try {
      final facilityId = (widget.floor['facilityId'] as num).toInt();
      await context.read<AppState>().apiClient.put('/facilities/$facilityId', {
        'facilityName': _name.text.trim(),
        if (_floorNum.text.trim().isNotEmpty)
          'floorNumber': int.tryParse(_floorNum.text.trim()),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, pad + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Text('Edit Floor',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const Spacer(),
            IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
                labelText: 'Floor Name *', hintText: 'e.g. Ground Floor'),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _floorNum,
            decoration: const InputDecoration(
                labelText: 'Floor Number (optional)', hintText: 'e.g. 0, 1, 2'),
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Save Changes'),
          ),
        ],
      ),
    );
  }
}

// ─── Edit Room Sheet ──────────────────────────────────────────────────────────

class _EditRoomSheet extends StatefulWidget {
  final Map<String, dynamic> room;
  const _EditRoomSheet({required this.room});

  @override
  State<_EditRoomSheet> createState() => _EditRoomSheetState();
}

class _EditRoomSheetState extends State<_EditRoomSheet> {
  late final TextEditingController _name;
  late final TextEditingController _roomNum;
  late String _sharing;
  bool _saving = false;

  static const _sharingOptions = [
    ('1', '1-Sharing (Single)'),
    ('2', '2-Sharing (Double)'),
    ('3', '3-Sharing (Triple)'),
    ('4', '4-Sharing'),
    ('5', '5-Sharing'),
    ('6', '6-Sharing'),
  ];

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
        text: '${widget.room['facilityName'] ?? ''}');
    _roomNum = TextEditingController(
        text: '${widget.room['roomNumber'] ?? ''}');
    _sharing = '${widget.room['sharingType'] ?? '2'}';
    if (!_sharingOptions.any((o) => o.$1 == _sharing)) _sharing = '2';
  }

  @override
  void dispose() {
    _name.dispose();
    _roomNum.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Room name is required')));
      return;
    }
    setState(() => _saving = true);
    try {
      final facilityId = (widget.room['facilityId'] as num).toInt();
      final newSharing = int.tryParse(_sharing) ?? 1;
      final oldSharing = int.tryParse('${widget.room['sharingType'] ?? '0'}') ?? 0;

      // When sharing count is reduced, validate and remove excess vacant beds
      if (newSharing < oldSharing) {
        final bedData = await context.read<AppState>().apiClient
            .get('/rooms/$facilityId/beds');
        final beds = (bedData['items'] as List? ?? [])
            .cast<Map<String, dynamic>>();
        final occupied = beds.where((b) => b['occupantName'] != null).toList();
        final vacant = beds.where((b) => b['occupantName'] == null).toList();
        final excess = beds.length - newSharing;

        if (occupied.length > newSharing) {
          if (mounted) {
            final n = occupied.length;
            setState(() => _saving = false);
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Cannot Reduce Sharing'),
                content: Text(
                    'Cannot reduce to $_sharing-sharing: $n bed${n == 1 ? ' is' : 's are'} currently occupied. Please check out the tenant(s) first.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          }
          return;
        }

        // Delete excess vacant beds starting from the last ones
        if (excess > 0) {
          for (final bed in vacant.reversed.take(excess)) {
            await context.read<AppState>().apiClient
                .delete('/facilities/${bed['facilityId']}');
          }
        }
      }

      await context.read<AppState>().apiClient.put('/facilities/$facilityId', {
        'facilityName': _name.text.trim(),
        if (_roomNum.text.trim().isNotEmpty) 'roomNumber': _roomNum.text.trim(),
        'sharingType': _sharing,
        'capacity': newSharing,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, pad + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Text('Edit Room',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const Spacer(),
            IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
                labelText: 'Room Name *', hintText: 'e.g. Room 101'),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _roomNum,
            decoration: const InputDecoration(
                labelText: 'Room Number (optional)', hintText: 'e.g. 101'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _sharing,
            decoration: const InputDecoration(labelText: 'Sharing Type'),
            items: _sharingOptions
                .map((opt) => DropdownMenuItem(value: opt.$1, child: Text(opt.$2)))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _sharing = v);
            },
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save Changes'),
          ),
        ],
      ),
    );
  }
}

// ─── Edit Bed Sheet ───────────────────────────────────────────────────────────

class _EditBedSheet extends StatefulWidget {
  final Map<String, dynamic> bed;
  const _EditBedSheet({required this.bed});

  @override
  State<_EditBedSheet> createState() => _EditBedSheetState();
}

class _EditBedSheetState extends State<_EditBedSheet> {
  late final TextEditingController _name;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: '${widget.bed['facilityName'] ?? ''}');
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bed name is required')));
      return;
    }
    setState(() => _saving = true);
    try {
      final facilityId = (widget.bed['facilityId'] as num).toInt();
      await context.read<AppState>().apiClient.put('/facilities/$facilityId', {
        'facilityName': _name.text.trim(),
        'capacity': 1,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, pad + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Text('Edit Bed',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const Spacer(),
            IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
                labelText: 'Bed Name *', hintText: 'e.g. Bed A, Bed 1'),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save Changes'),
          ),
        ],
      ),
    );
  }
}

// ─── Shared Helpers ───────────────────────────────────────────────────────────

class _WsError extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;
  const _WsError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: PgColors.danger),
              const SizedBox(height: 12),
              const Text('Could not load data',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('$error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      );
}

// ─── Sharing Prices Screen ────────────────────────────────────────────────────

class _SharingPricesScreen extends StatefulWidget {
  final int propertyId;
  const _SharingPricesScreen({required this.propertyId});

  @override
  State<_SharingPricesScreen> createState() => _SharingPricesScreenState();
}

class _SharingPricesScreenState extends State<_SharingPricesScreen> {
  static const _sharingOptions = [
    ('1', '1-Sharing (Single)'),
    ('2', '2-Sharing (Double)'),
    ('3', '3-Sharing (Triple)'),
    ('4', '4-Sharing'),
    ('5', '5-Sharing'),
    ('6', '6-Sharing'),
  ];

  final Map<String, TextEditingController> _rentCtrl = {};
  final Map<String, TextEditingController> _depositCtrl = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final o in _sharingOptions) {
      _rentCtrl[o.$1] = TextEditingController();
      _depositCtrl[o.$1] = TextEditingController();
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in _rentCtrl.values) { c.dispose(); }
    for (final c in _depositCtrl.values) { c.dispose(); }
    super.dispose();
  }

  void _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await context.read<AppState>().apiClient
          .get('/properties/${widget.propertyId}/sharing-prices');
      final items = (result['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final item in items) {
        final type = '${item['sharingType']}';
        final rent = item['monthlyRent'];
        final deposit = item['securityDeposit'];
        if (_rentCtrl.containsKey(type)) {
          _rentCtrl[type]!.text = rent != null ? '$rent' : '';
          _depositCtrl[type]!.text = (deposit != null && deposit != 0) ? '$deposit' : '';
        }
      }
      setState(() => _loading = false);
    } catch (e) {
      setState(() { _loading = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  Future<void> _save() async {
    final prices = <Map<String, dynamic>>[];
    for (final o in _sharingOptions) {
      final rentText = _rentCtrl[o.$1]!.text.trim();
      if (rentText.isEmpty) continue;
      final rent = double.tryParse(rentText);
      if (rent == null) continue;
      final depositText = _depositCtrl[o.$1]!.text.trim();
      prices.add({
        'sharingType': o.$1,
        'monthlyRent': rent,
        if (depositText.isNotEmpty) 'securityDeposit': double.tryParse(depositText) ?? 0,
      });
    }
    if (prices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter at least one sharing type price')));
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<AppState>().apiClient.put(
          '/properties/${widget.propertyId}/sharing-prices', {'prices': prices});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Prices saved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        centerTitle: false,
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Room Pricing',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            Text('Monthly rent per sharing type',
                style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w400)),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE5E7EB)),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _WsError(error: _error, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: PgColors.lavender,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFDDD6FE)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, size: 16, color: PgColors.primary),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Set standard prices for each sharing type. These auto-fill when assigning a tenant to a bed.',
                              style: TextStyle(fontSize: 12, color: PgColors.primary),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ..._sharingOptions.map((o) => _PriceRow(
                          label: o.$2,
                          rentCtrl: _rentCtrl[o.$1]!,
                          depositCtrl: _depositCtrl[o.$1]!,
                        )),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                          backgroundColor: PgColors.primary,
                          minimumSize: const Size(double.infinity, 48)),
                      child: _saving
                          ? const SizedBox(
                              height: 18, width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Save Prices'),
                    ),
                  ],
                ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  final String label;
  final TextEditingController rentCtrl;
  final TextEditingController depositCtrl;
  const _PriceRow({required this.label, required this.rentCtrl, required this.depositCtrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: rentCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Monthly Rent (₹)',
                    prefixIcon: Icon(Icons.currency_rupee, size: 18),
                    isDense: true,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: depositCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Deposit (₹)',
                    prefixIcon: Icon(Icons.currency_rupee, size: 18),
                    isDense: true,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
