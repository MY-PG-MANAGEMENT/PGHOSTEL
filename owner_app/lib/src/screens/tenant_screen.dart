import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/animations.dart';
import '../widgets/async_action_button.dart';
import '../widgets/error_retry_view.dart';
import 'billing_screen.dart' show InvoiceDetailSheet;
import 'checkout_sheet.dart' show CheckoutSheet, TransferBedSheet;

// ─── Helpers ─────────────────────────────────────────────────────────────────

// Official WhatsApp glyph (FontAwesome brand path) rendered inline — no asset/network needed.
const String _kWhatsAppSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 448 512">'
    '<path fill="#25D366" d="M380.9 97.1C339 55.1 283.2 32 223.9 32c-122.4 0-222 99.6-222 222 0 39.1 '
    '10.2 77.3 29.6 111L0 480l117.7-30.9c32.4 17.7 68.9 27 106.1 27h.1c122.3 0 224.1-99.6 224.1-222 '
    '0-59.3-25.2-115-67.2-157zm-157 341.6c-33.2 0-65.7-8.9-94-25.7l-6.7-4-69.8 18.3L72 359.2l-4.4-7c-18.5-29.4-28.2-63.3-28.2-98.2 '
    '0-101.7 82.8-184.5 184.6-184.5 49.3 0 95.6 19.2 130.4 54.1 34.8 34.9 56.2 81.2 56.1 130.5 0 101.8-84.9 184.6-186.6 184.6zm101.2-138.2c-5.5-2.8-32.8-16.2-37.9-18-5.1-1.9-8.8-2.8-12.5 '
    '2.8-3.7 5.6-14.3 18-17.6 21.8-3.2 3.7-6.5 4.2-12 1.4-32.6-16.3-54-29.1-75.5-66-5.7-9.8 5.7-9.1 '
    '16.3-30.3 1.8-3.7.9-6.9-.5-9.7-1.4-2.8-12.5-30.1-17.1-41.2-4.5-10.8-9.1-9.3-12.5-9.5-3.2-.2-6.9-.2-10.6-.2-3.7 '
    '0-9.7 1.4-14.8 6.9-5.1 5.6-19.4 19-19.4 46.3 0 27.3 19.9 53.7 22.6 57.4 2.8 3.7 39.1 59.7 94.8 '
    '83.8 35.2 15.2 49 16.5 66.6 13.9 10.7-1.6 32.8-13.4 37.4-26.4 4.6-13 4.6-24.1 3.2-26.4-1.3-2.5-5-3.9-10.5-6.6z"/></svg>';

String _initial(String name) {
  final parts = name.trim().split(' ').where((w) => w.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  return parts.map((p) => p[0].toUpperCase()).take(2).join();
}

Color _avatarColor(String name) {
  final palette = [PgColors.primary, const Color(0xFF2563EB), PgColors.success, PgColors.warning];
  return name.isEmpty ? palette[0] : palette[name.codeUnitAt(0) % palette.length];
}

Widget _tenantAvatar(String name, {double radius = 22}) {
  return CircleAvatar(
    radius: radius,
    backgroundColor: _avatarColor(name),
    child: Text(_initial(name),
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: radius * 0.7)),
  );
}

// ─── Tenant List Screen ───────────────────────────────────────────────────

class TenantScreen extends StatefulWidget {
  final int? propertyId;
  const TenantScreen({this.propertyId, super.key});

  @override
  State<TenantScreen> createState() => _TenantScreenState();
}

class _TenantScreenState extends State<TenantScreen> {
  late Future<Map<String, dynamic>> _future;
  final _search = TextEditingController();
  String _query = '';
  String _filter = 'ACTIVE'; // default to current tenants; All/Inactive on tap

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
    final path = widget.propertyId != null
        ? '/properties/${widget.propertyId}/tenants'
        : '/tenants';
    _future = context.read<AppState>().apiClient.get(path);
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> items) {
    var list = items;
    if (_query.isNotEmpty) {
      list = list
          .where((t) =>
              '${t['fullName']}'.toLowerCase().contains(_query) ||
              '${t['mobileNumber']}'.contains(_query))
          .toList();
    }
    if (_filter == 'ACTIVE') {
      list = list.where((t) => t['hasActiveAdmission'] == true).toList();
    } else if (_filter == 'INACTIVE') {
      list = list.where((t) => t['hasActiveAdmission'] != true).toList();
    }
    return list;
  }

  Widget _buildBody() {
    return Column(
      children: [
        TextField(
          controller: _search,
          decoration: const InputDecoration(
            hintText: 'Search by name or mobile…',
            prefixIcon: Icon(Icons.search),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ['ALL', 'ACTIVE', 'INACTIVE'].map((f) {
              final selected = _filter == f;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(f == 'ALL' ? 'All Tenants' : f),
                  selected: selected,
                  selectedColor: PgColors.lavender,
                  checkmarkColor: PgColors.primary,
                  labelStyle: TextStyle(
                      color: selected ? PgColors.primary : null,
                      fontWeight: selected ? FontWeight.w700 : null),
                  onSelected: (_) => setState(() => _filter = f),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: FutureBuilder<Map<String, dynamic>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _TenantErrorState(
                    error: snapshot.error, onRetry: () => setState(_load));
              }
              final data = snapshot.data ?? {};
              final rawList = data['items'];
              final List raw = rawList is List ? rawList : [];
              final tenants = _applyFilters(raw.cast<Map<String, dynamic>>());

              if (tenants.isEmpty) {
                return _TenantEmptyState(onAdd: _query.isEmpty ? _openAdd : null);
              }
              return RefreshIndicator(
                onRefresh: () async => setState(_load),
                child: ListView.separated(
                  itemCount: tenants.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => FadeSlideIn(
                    delay: Duration(milliseconds: 40 * (i.clamp(0, 8))),
                    child: _TenantCard(
                      data: tenants[i],
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(
                            builder: (_) => TenantDetailScreen(tenant: tenants[i]),
                          ))
                          .then((_) => setState(_load)),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.propertyId != null) {
      return Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _buildBody(),
          ),
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton(
              heroTag: 'addTenant_${widget.propertyId}',
              onPressed: _openAdd,
              tooltip: 'Add Tenant',
              child: const Icon(Icons.person_add_outlined),
            ),
          ),
        ],
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: PgColors.textPrimary,
        elevation: 0,
        title: const Text('Tenants',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            tooltip: 'Add Tenant',
            onPressed: _openAdd,
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: PgColors.hairline),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: _buildBody(),
      ),
    );
  }

  void _openAdd() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
          builder: (_) => AddTenantScreen(propertyId: widget.propertyId)),
    );
    if (added == true) setState(_load);
  }
}

// ─── Tenant Card ──────────────────────────────────────────────────────────

class _TenantCard extends StatelessWidget {
  const _TenantCard({required this.data, required this.onTap});

  final Map<String, dynamic> data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = '${data['fullName'] ?? 'Tenant'}';
    final mobile = '${data['mobileNumber'] ?? ''}';
    final room = data['currentRoomName'];
    final bed = data['currentBedName'];
    final active = data['hasActiveAdmission'] == true;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              _tenantAvatar(name, radius: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15)),
                        ),
                        _ActiveBadge(active),
                      ],
                    ),
                    if (mobile.isNotEmpty)
                      Text(mobile, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                    if (active && (room != null || bed != null)) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.bed_outlined, size: 14, color: PgColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          [if (room != null) room, if (bed != null) bed].join(' › '),
                          style: const TextStyle(
                              color: PgColors.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13),
                        ),
                      ]),
                    ],
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

class _ActiveBadge extends StatelessWidget {
  const _ActiveBadge(this.active);
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (active ? PgColors.success : Colors.grey).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        active ? 'Active' : 'Inactive',
        style: TextStyle(
          color: active ? PgColors.success : Colors.grey,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─── Tenant Detail Screen ─────────────────────────────────────────────────

class TenantDetailScreen extends StatefulWidget {
  const TenantDetailScreen({required this.tenant, super.key});

  final Map<String, dynamic> tenant;

  @override
  State<TenantDetailScreen> createState() => _TenantDetailScreenState();
}

class _TenantDetailScreenState extends State<TenantDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late Map<String, dynamic> _tenant;
  List<Map<String, dynamic>> _scheduled = [];

  @override
  void initState() {
    super.initState();
    _tenant = widget.tenant;
    _tabs = TabController(length: 5, vsync: this);
    _refreshTenant();
    _loadScheduled();
  }

  Future<void> _loadScheduled() async {
    final id = _tenant['tenantId'];
    try {
      final data = await context.read<AppState>().apiClient
          .get('/occupancy/scheduled-transfers/$id');
      final list = (data is List ? data : (data['items'] ?? data['data'] ?? []))
          .cast<Map<String, dynamic>>();
      if (mounted) setState(() => _scheduled = list);
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = '${_tenant['fullName'] ?? 'Tenant'}';
    final active = _tenant['hasActiveAdmission'] == true;

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          PopupMenuButton<String>(
            onSelected: _onMenuAction,
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit Profile')),
              const PopupMenuItem(value: 'emergency', child: Text('Emergency Contact')),
              const PopupMenuItem(value: 'employment', child: Text('Employment')),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Profile'),
            Tab(text: 'Payments'),
            Tab(text: 'Emergency'),
            Tab(text: 'Employment'),
            Tab(text: 'Documents'),
          ],
        ),
      ),
      body: Column(
        children: [
          _TenantHeader(tenant: _tenant, active: active, onShift: _openTransfer),
          if (_tenant['inTemporaryStay'] == true)
            _TempStayBanner(
              bedName: '${_tenant['tempBedName'] ?? 'a bed'}',
              onMovePermanent: _makePermanent,
            ),
          for (final s in _scheduled)
            _ScheduledTransferBanner(
              scheduled: s,
              onCancel: () => _cancelScheduled((s['scheduledBedTransferId'] as num).toInt()),
            ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _ProfileTab(
                  tenant: _tenant,
                  onCheckoutDateSet: _refreshTenant,
                  onCheckedOut: _refreshTenant,
                ),
                _TenantPaymentsTab(tenantId: (_tenant['tenantId'] as num).toInt()),
                _EmergencyTab(tenant: _tenant),
                _EmploymentTab(tenant: _tenant),
                const _DocumentsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshTenant() async {
    final id = _tenant['tenantId'];
    try {
      final fresh = await context.read<AppState>().apiClient.get('/tenants/$id');
      if (mounted) setState(() => _tenant = fresh);
    } catch (_) {}
    await _loadScheduled();
  }

  Future<void> _cancelScheduled(int id) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().apiClient.delete('/occupancy/scheduled-transfers/$id');
      await _refreshTenant();
      messenger.showSnackBar(const SnackBar(content: Text('Scheduled transfer cancelled')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _makePermanent() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _MakePermanentDialog(
        tenantName: '${_tenant['fullName'] ?? 'Tenant'}',
        tempBedName: '${_tenant['tempBedName'] ?? 'this bed'}',
        partyId: (_tenant['tenantId'] as num).toInt(),
        tempBedFacilityId: (_tenant['tempBedFacilityId'] as num).toInt(),
        propertyId: (_tenant['currentPropertyId'] as num?)?.toInt(),
      ),
    );
    if (ok == true) await _refreshTenant();
  }

  void _onMenuAction(String action) async {
    bool? changed;
    if (action == 'edit') {
      changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => EditTenantScreen(tenant: _tenant)),
      );
    } else if (action == 'emergency') {
      changed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => _EditEmergencyContactSheet(tenant: _tenant),
      );
    } else if (action == 'employment') {
      changed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => _EditEmploymentSheet(tenant: _tenant),
      );
    }
    if (changed == true && mounted) {
      await _refreshTenant();
    }
  }

  Future<void> _openTransfer() async {
    // Refresh first so we have the latest currentPropertyId from the detail API
    await _refreshTenant();
    if (!mounted) return;
    final propertyId = _tenant['currentPropertyId'];
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => TransferBedSheet(
        partyId: (_tenant['tenantId'] as num).toInt(),
        tenantName: '${_tenant['fullName'] ?? 'Tenant'}',
        currentPropertyId: propertyId != null ? (propertyId as num).toInt() : null,
        moveInDateIso: _tenant['moveInDate'] as String?,
        currentSharingType: _tenant['currentSharingType'] as String?,
        onTransferred: _refreshTenant,
      ),
    );
    if (changed == true && mounted) {
      await _refreshTenant();
    }
  }
}

class _TenantHeader extends StatelessWidget {
  const _TenantHeader({required this.tenant, required this.active, required this.onShift});

  final Map<String, dynamic> tenant;
  final bool active;
  final VoidCallback onShift;

  String _digits(String mobile) => mobile.replaceAll(RegExp(r'\D'), '');

  String _waNumber(String mobile) {
    final d = _digits(mobile);
    // wa.me needs a country code — assume India (+91) for plain 10-digit numbers.
    return d.length == 10 ? '91$d' : d;
  }

  Future<void> _launch(BuildContext context, Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No app available for this action')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No app available for this action')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = '${tenant['fullName'] ?? 'Tenant'}';
    final mobile = '${tenant['mobileNumber'] ?? ''}';
    final room = tenant['currentRoomName'];
    final bed = tenant['currentBedName'];
    final hasMobile = _digits(mobile).isNotEmpty;

    return Container(
      color: const Color(0xFFF5F6FA),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3)),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Column(
          children: [
            // ── Avatar on the left, details on the right ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: _avatarColor(name).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _initial(name),
                    style: TextStyle(
                        color: _avatarColor(name), fontWeight: FontWeight.w800, fontSize: 26),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(name,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                          ),
                          const SizedBox(width: 8),
                          _StatusPill(active: active),
                        ],
                      ),
                      if (mobile.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(children: [
                          Icon(Icons.phone_outlined, size: 13, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(mobile, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                        ]),
                      ],
                      if (active && (room != null || bed != null)) ...[
                        const SizedBox(height: 4),
                        Row(children: [
                          const Icon(Icons.bed_outlined, size: 14, color: PgColors.primary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              [if (room != null) room, if (bed != null) bed].join(' › '),
                              style: const TextStyle(
                                  color: PgColors.primary, fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ),
                        ]),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _TenantAction(
                  icon: Icons.call,
                  label: 'Call',
                  bg: const Color(0xFFE8EEFF),
                  fg: const Color(0xFF2563EB),
                  onTap: hasMobile ? () => _launch(context, Uri(scheme: 'tel', path: mobile)) : null,
                ),
                _TenantAction(
                  label: 'WhatsApp',
                  bg: const Color(0xFFD9F7E3),
                  fg: const Color(0xFF25D366),
                  iconChild: SvgPicture.string(_kWhatsAppSvg, width: 26, height: 26),
                  onTap: hasMobile
                      ? () => _launch(context, Uri.parse('https://wa.me/${_waNumber(mobile)}'))
                      : null,
                ),
                _TenantAction(
                  icon: Icons.sms_outlined,
                  label: 'Message',
                  bg: const Color(0xFFEDE7FB),
                  fg: const Color(0xFF7C3AED),
                  onTap: hasMobile ? () => _launch(context, Uri(scheme: 'sms', path: mobile)) : null,
                ),
                _TenantAction(
                  icon: Icons.swap_horiz,
                  label: 'Shift',
                  bg: const Color(0xFFFDEFC9),
                  fg: const Color(0xFFD97706),
                  onTap: active ? onShift : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? PgColors.success : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(active ? 'Active' : 'Inactive',
              style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _TenantAction extends StatelessWidget {
  const _TenantAction({
    this.icon,
    this.iconChild,
    required this.label,
    required this.bg,
    required this.fg,
    required this.onTap,
  }) : assert(icon != null || iconChild != null);

  final IconData? icon;
  final Widget? iconChild;
  final String label;
  final Color bg;
  final Color fg;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Opacity(
      opacity: disabled ? 0.4 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: iconChild ?? Icon(icon, color: fg, size: 24),
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ─── Temporary-stay banner ────────────────────────────────────────────────

class _TempStayBanner extends StatelessWidget {
  const _TempStayBanner({
    required this.bedName,
    required this.onMovePermanent,
  });

  final String bedName;
  final VoidCallback onMovePermanent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: PgColors.warning.withValues(alpha: 0.10),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.timelapse_outlined, size: 16, color: PgColors.warning),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Temporary stay in $bedName — no billing',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.event_seat_outlined, size: 16),
              label: const Text('Assign Permanent Bed', style: TextStyle(fontSize: 12.5)),
              style: FilledButton.styleFrom(
                  backgroundColor: PgColors.primary, visualDensity: VisualDensity.compact),
              onPressed: onMovePermanent,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Scheduled-transfer banner ────────────────────────────────────────────

class _ScheduledTransferBanner extends StatelessWidget {
  const _ScheduledTransferBanner({required this.scheduled, required this.onCancel});

  final Map<String, dynamic> scheduled;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final eff = scheduled['effectiveDate'];
    final rent = scheduled['newMonthlyRent'];
    return Container(
      width: double.infinity,
      color: PgColors.primary.withValues(alpha: 0.07),
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(children: [
        const Icon(Icons.event_repeat_outlined, size: 16, color: PgColors.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Bed transfer scheduled for ${eff ?? 'the next billing date'}'
            '${rent != null ? ' • new rent ₹$rent' : ''}',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: PgColors.primary),
          ),
        ),
        TextButton(
          onPressed: onCancel,
          child: const Text('Cancel', style: TextStyle(fontSize: 12.5)),
        ),
      ]),
    );
  }
}

// ─── Make-permanent dialog ────────────────────────────────────────────────

class _MakePermanentDialog extends StatefulWidget {
  const _MakePermanentDialog({
    required this.tenantName,
    required this.tempBedName,
    required this.partyId,
    required this.tempBedFacilityId,
    this.propertyId,
  });

  final String tenantName;
  final String tempBedName;
  final int partyId;
  final int tempBedFacilityId;
  final int? propertyId;

  @override
  State<_MakePermanentDialog> createState() => _MakePermanentDialogState();
}

class _MakePermanentDialogState extends State<_MakePermanentDialog> {
  final _rentCtrl = TextEditingController();
  bool _saving = false;
  late int _bedId = widget.tempBedFacilityId;
  // Bed options: the current temp bed first, then any vacant beds in the property.
  late List<Map<String, dynamic>> _beds = [
    {'bed_id': widget.tempBedFacilityId, 'label': '${widget.tempBedName} (current)'},
  ];

  @override
  void initState() {
    super.initState();
    _loadBeds();
  }

  @override
  void dispose() {
    _rentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBeds() async {
    final pid = widget.propertyId;
    if (pid == null) return;
    try {
      final result = await context.read<AppState>().apiClient.get('/properties/$pid/vacant-beds');
      final all = (result is List ? result : (result['items'] ?? result['data'] ?? []))
          .cast<Map<String, dynamic>>();
      final vacant = all
          .where((b) => '${b['bed_status']}'.toUpperCase() == 'VACANT')
          .map((b) => {
                'bed_id': (b['bed_id'] as num).toInt(),
                'label': '${b['bed_name'] ?? 'Bed'}'
                    '${b['room_name'] != null ? ' · ${b['room_name']}' : ''}',
              })
          .toList();
      if (mounted) {
        setState(() => _beds = [
              {'bed_id': widget.tempBedFacilityId, 'label': '${widget.tempBedName} (current)'},
              ...vacant,
            ]);
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final rent = double.tryParse(_rentCtrl.text.trim());
    try {
      await context.read<AppState>().apiClient.post('/occupancy/temp-stay/make-permanent', {
        'partyId': widget.partyId,
        'bedFacilityId': _bedId,
        if (rent != null && rent > 0) 'monthlyRent': rent,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        messenger.showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Assign Permanent Bed', style: TextStyle(fontWeight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Assign ${widget.tenantName} to a permanent bed.',
              style: TextStyle(fontSize: 13, color: Colors.grey[700])),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            value: _bedId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Permanent Bed',
              prefixIcon: Icon(Icons.bed_outlined),
              border: OutlineInputBorder(),
            ),
            items: _beds
                .map((b) => DropdownMenuItem<int>(
                      value: b['bed_id'] as int,
                      child: Text('${b['label']}', overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: _saving ? null : (v) => setState(() => _bedId = v ?? _bedId),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _rentCtrl,
            decoration: const InputDecoration(
              labelText: 'Monthly Rent (₹) — optional',
              helperText: 'Leave blank to use the standard sharing price',
              prefixIcon: Icon(Icons.currency_rupee),
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: PgColors.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Billing starts from the temporary join date (the tenant\'s original cycle is kept).',
              style: TextStyle(fontSize: 12, color: PgColors.primary),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Assign'),
        ),
      ],
    );
  }
}

// ─── Profile Tab ──────────────────────────────────────────────────────────

class _ProfileTab extends StatefulWidget {
  const _ProfileTab({
    required this.tenant,
    required this.onCheckoutDateSet,
    required this.onCheckedOut,
  });

  final Map<String, dynamic> tenant;
  final VoidCallback onCheckoutDateSet;
  final VoidCallback onCheckedOut;

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  Future<void> _openCheckout() async {
    final tenantId = widget.tenant['tenantId'];
    final name = '${widget.tenant['fullName'] ?? 'Tenant'}';
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => CheckoutSheet(
        partyId: (tenantId as num).toInt(),
        tenantName: name,
        onCheckedOut: widget.onCheckedOut,
      ),
    );
  }

  Future<void> _setCheckoutDate() async {
    final tenantId = widget.tenant['tenantId'];
    final existing = widget.tenant['expectedCheckoutDate'] as String?;
    final moveIn = widget.tenant['moveInDate'] as String?;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _SetCheckoutDateDialog(
        partyId: tenantId,
        existingIso: existing,
        moveInDateIso: moveIn,
      ),
    );
    if (saved == true) widget.onCheckoutDateSet();
  }

  @override
  Widget build(BuildContext context) {
    final tenant = widget.tenant;
    final moveIn = tenant['moveInDate'] as String?;
    final rent = tenant['monthlyRent'];
    final deposit = tenant['securityDeposit'];
    final expectedCheckout = tenant['expectedCheckoutDate'] as String?;
    final hasAdmission = tenant['hasActiveAdmission'] == true;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (moveIn != null || rent != null)
          _TenancyBanner(moveInDate: moveIn, monthlyRent: rent, securityDeposit: deposit, expectedCheckoutDate: expectedCheckout),
        if (moveIn != null || rent != null) const SizedBox(height: 8),
        if (hasAdmission)
          OutlinedButton.icon(
            icon: const Icon(Icons.event_available_outlined, size: 16),
            label: Text(expectedCheckout != null ? 'Update Checkout Date' : 'Set Checkout Date'),
            style: OutlinedButton.styleFrom(
              foregroundColor: PgColors.primary,
              side: const BorderSide(color: PgColors.primary),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            onPressed: _setCheckoutDate,
          ),
        if (hasAdmission) const SizedBox(height: 8),
        if (hasAdmission)
          OutlinedButton.icon(
            icon: const Icon(Icons.logout_outlined, size: 16),
            label: const Text('Checkout Tenant'),
            style: OutlinedButton.styleFrom(
              foregroundColor: PgColors.danger,
              side: const BorderSide(color: PgColors.danger),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            onPressed: _openCheckout,
          ),
        if (hasAdmission) const SizedBox(height: 12),
        _InfoSection(title: 'Personal Details', items: [
          ('Full Name', '${tenant['fullName'] ?? '—'}', Icons.person_outline),
          ('Mobile', '${tenant['mobileNumber'] ?? '—'}', Icons.phone_outlined),
          ('Gender', '${tenant['gender'] ?? '—'}', Icons.wc_outlined),
          ('Date of Birth', '${tenant['dateOfBirth'] ?? '—'}', Icons.cake_outlined),
          ('Email', '${tenant['email'] ?? '—'}', Icons.email_outlined),
          ('Vehicle', tenant['hasVehicle'] == true ? 'Yes' : 'No', Icons.two_wheeler_outlined),
        ]),
        const SizedBox(height: 12),
        _InfoSection(title: 'Identity', items: [
          ('Aadhaar', _maskAadhaar(tenant['aadhaarNumber']), Icons.credit_card_outlined),
        ]),
        const SizedBox(height: 12),
        _InfoSection(title: 'Permanent Address', items: [
          ('Address', '${tenant['permanentAddress'] ?? '—'}', Icons.home_outlined),
        ]),
      ],
    );
  }

  String _maskAadhaar(dynamic v) {
    final s = '$v';
    if (s.length == 12) return 'XXXX XXXX ${s.substring(8)}';
    return s == 'null' ? '—' : s;
  }
}

// ─── Set Checkout Date Dialog ─────────────────────────────────────────────

class _SetCheckoutDateDialog extends StatefulWidget {
  const _SetCheckoutDateDialog({
    required this.partyId,
    this.existingIso,
    this.moveInDateIso,
  });

  final dynamic partyId;
  final String? existingIso;
  final String? moveInDateIso;

  @override
  State<_SetCheckoutDateDialog> createState() => _SetCheckoutDateDialogState();
}

class _SetCheckoutDateDialogState extends State<_SetCheckoutDateDialog> {
  DateTime? _selected;
  bool _saving = false;

  DateTime? get _maxDate {
    if (widget.moveInDateIso == null) return null;
    try {
      final moveIn = DateTime.parse(widget.moveInDateIso!);
      final now = DateTime.now();
      DateTime thisMonthDue;
      try {
        thisMonthDue = DateTime(now.year, now.month, moveIn.day);
      } catch (_) {
        thisMonthDue = DateTime(now.year, now.month + 1, 1);
      }
      final nextDue = !thisMonthDue.isAfter(now)
          ? DateTime(now.year, now.month + 1, moveIn.day)
          : thisMonthDue;
      return nextDue.subtract(const Duration(days: 1));
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.existingIso != null) {
      try {
        _selected = DateTime.parse(widget.existingIso!);
      } catch (_) {}
    }
  }

  Future<void> _pickDate() async {
    final max = _maxDate;
    final now = DateTime.now();
    final initial = _selected ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: (max != null && initial.isAfter(max)) ? max : initial,
      firstDate: now,
      lastDate: max ?? DateTime(now.year + 5),
      helpText: max != null
          ? 'Max: ${max.day.toString().padLeft(2, '0')}-${max.month.toString().padLeft(2, '0')}-${max.year}'
          : 'Select expected checkout date',
    );
    if (picked != null) setState(() => _selected = picked);
  }

  Future<void> _save() async {
    final iso = _selected != null
        ? '${_selected!.year}-${_selected!.month.toString().padLeft(2, '0')}-${_selected!.day.toString().padLeft(2, '0')}'
        : null;
    setState(() => _saving = true);
    try {
      await context.read<AppState>().apiClient.put('/occupancy/expected-checkout', {
        'partyId': widget.partyId,
        'expectedCheckoutDate': iso,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final max = _maxDate;
    final label = _selected != null
        ? '${_selected!.day.toString().padLeft(2, '0')}-${_selected!.month.toString().padLeft(2, '0')}-${_selected!.year}'
        : 'Tap to select date';
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Set Checkout Date', style: TextStyle(fontWeight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (max != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Must be before next payment date (${max.day.toString().padLeft(2, '0')}-${max.month.toString().padLeft(2, '0')}-${max.year})',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ),
          InkWell(
            onTap: _saving ? null : _pickDate,
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Expected Checkout Date',
                prefixIcon: Icon(Icons.event_available_outlined),
                border: OutlineInputBorder(),
              ),
              child: Text(label),
            ),
          ),
          if (_selected != null)
            TextButton(
              onPressed: _saving ? null : () => setState(() => _selected = null),
              child: const Text('Clear date'),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save'),
        ),
      ],
    );
  }
}

// ─── Emergency Tab ────────────────────────────────────────────────────────

class _EmergencyTab extends StatelessWidget {
  const _EmergencyTab({required this.tenant});

  final Map<String, dynamic> tenant;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _InfoSection(title: 'Emergency Contact', items: [
          ('Name', '${tenant['emergencyContactName'] ?? '—'}', Icons.person_outline),
          ('Mobile', '${tenant['emergencyContactMobile'] ?? '—'}', Icons.phone_outlined),
          ('Relation', '${tenant['emergencyContactRelation'] ?? '—'}', Icons.family_restroom),
        ]),
      ],
    );
  }
}

// ─── Employment Tab ───────────────────────────────────────────────────────

class _EmploymentTab extends StatelessWidget {
  const _EmploymentTab({required this.tenant});

  final Map<String, dynamic> tenant;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _InfoSection(title: 'Employment Details', items: [
          ('Employer', '${tenant['employerName'] ?? '—'}', Icons.business_outlined),
          ('Designation', '${tenant['designation'] ?? '—'}', Icons.work_outline),
          ('Work Address', '${tenant['workAddress'] ?? '—'}', Icons.location_on_outlined),
        ]),
      ],
    );
  }
}

// ─── Documents Tab ────────────────────────────────────────────────────────

class _DocumentsTab extends StatelessWidget {
  const _DocumentsTab();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_outlined, size: 56, color: PgColors.primary),
            SizedBox(height: 16),
            Text('Documents', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            SizedBox(height: 6),
            Text('Document upload will be available soon.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

// ─── Tenancy Banner ───────────────────────────────────────────────────────

class _TenancyBanner extends StatelessWidget {
  final String? moveInDate;
  final dynamic monthlyRent;
  final dynamic securityDeposit;
  final String? expectedCheckoutDate;
  const _TenancyBanner({this.moveInDate, this.monthlyRent, this.securityDeposit, this.expectedCheckoutDate});

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  String _fmt(String? iso) {
    if (iso == null) return '—';
    try {
      final d = DateTime.parse(iso);
      return '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year}';
    } catch (_) {
      return iso;
    }
  }

  String _nextPayment(String? iso) {
    if (iso == null) return '—';
    try {
      final moveIn = DateTime.parse(iso);
      final now = DateTime.now();
      DateTime candidate;
      try {
        candidate = DateTime(now.year, now.month, moveIn.day);
      } catch (_) {
        candidate = DateTime(now.year, now.month + 1, 1);
      }
      if (!candidate.isAfter(now)) {
        try {
          candidate = DateTime(now.year, now.month + 1, moveIn.day);
        } catch (_) {
          candidate = DateTime(now.year + 1, 1, moveIn.day);
        }
      }
      return '${candidate.day.toString().padLeft(2, '0')} ${_months[candidate.month - 1]} ${candidate.year}';
    } catch (_) {
      return '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    final rentStr = monthlyRent != null ? '₹$monthlyRent/mo' : '—';
    final depositStr = (securityDeposit != null && securityDeposit != 0) ? '₹$securityDeposit' : null;
    final checkoutStr = expectedCheckoutDate != null ? _fmt(expectedCheckoutDate) : null;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4F2DE4), Color(0xFF7C5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Tenancy Details',
              style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _BannerStat(label: 'Move-in', value: _fmt(moveInDate))),
              Container(width: 1, height: 32, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 8)),
              Expanded(child: _BannerStat(label: 'Monthly Rent', value: rentStr)),
              Container(width: 1, height: 32, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 8)),
              Expanded(child: _BannerStat(label: 'Next Payment', value: _nextPayment(moveInDate))),
            ],
          ),
          if (depositStr != null || checkoutStr != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (depositStr != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Security Deposit: $depositStr',
                        style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                if (checkoutStr != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.event_available_outlined, size: 12, color: Colors.white70),
                        const SizedBox(width: 4),
                        Text('Checkout: $checkoutStr',
                            style: const TextStyle(color: Colors.white, fontSize: 12)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BannerStat extends StatelessWidget {
  final String label;
  final String value;
  const _BannerStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

// ─── Tenant Payments Tab ──────────────────────────────────────────────────

class _TenantPaymentsTab extends StatefulWidget {
  final int tenantId;
  const _TenantPaymentsTab({required this.tenantId});

  @override
  State<_TenantPaymentsTab> createState() => _TenantPaymentsTabState();
}

class _TenantPaymentsTabState extends State<_TenantPaymentsTab> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = context.read<AppState>().apiClient.get('/billing/invoices?partyId=${widget.tenantId}');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ErrorRetryView(
              error: snapshot.error ?? Exception('Unknown error'),
              onRetry: () => setState(_load));
        }
        final raw = (snapshot.data?['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        // Sort newest invoice month first
        final items = [...raw]..sort((a, b) {
            final am = '${a['invoice_month'] ?? ''}';
            final bm = '${b['invoice_month'] ?? ''}';
            return bm.compareTo(am);
          });
        if (items.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_long_outlined, size: 56, color: PgColors.primary),
                  SizedBox(height: 16),
                  Text('No Payments Yet', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  SizedBox(height: 6),
                  Text('Payment history will appear here once invoices are generated.',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => setState(_load),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _InvoiceCard(
              invoice: items[i],
              onTap: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.white,
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                builder: (_) => InvoiceDetailSheet(
                  invoice: items[i],
                  onRefresh: () => setState(_load),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  final Map<String, dynamic> invoice;
  final VoidCallback? onTap;
  const _InvoiceCard({required this.invoice, this.onTap});

  static const _statusColor = {
    'PAID': Color(0xFF16A34A),
    'PENDING': Color(0xFFD97706),
    'OVERDUE': Color(0xFFDC2626),
    'PARTIAL': Color(0xFF2563EB),
  };
  static const _statusBg = {
    'PAID': Color(0xFFF0FDF4),
    'PENDING': Color(0xFFFFFBEB),
    'OVERDUE': Color(0xFFFFF1F2),
    'PARTIAL': Color(0xFFEFF6FF),
  };
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  String _month(dynamic v) {
    if (v == null) return '—';
    try {
      final parts = '$v'.split('-');
      if (parts.length < 2) return '$v';
      final m = int.parse(parts[1]) - 1;
      return '${_months[m.clamp(0, 11)]} ${parts[0]}';
    } catch (_) {
      return '$v';
    }
  }

  String _fmtDate(dynamic v) {
    if (v == null) return '—';
    try {
      final d = DateTime.parse('$v');
      return '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year}';
    } catch (_) {
      return '$v';
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = '${invoice['status'] ?? ''}';
    final color = _statusColor[status] ?? Colors.grey;
    final bgColor = _statusBg[status] ?? Colors.grey.shade50;
    final total = invoice['total_amount'] ?? 0;
    final paid = invoice['paid_amount'] ?? 0;
    final balance = invoice['balance'] ?? 0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .05), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(_month(invoice['invoice_month']),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: color.withValues(alpha: .3)),
                    ),
                    child: Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey[400]),
                  ],
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  _AmountChip(label: 'Total', value: '₹$total', color: Colors.grey.shade700),
                  const SizedBox(width: 14),
                  _AmountChip(label: 'Paid', value: '₹$paid', color: const Color(0xFF16A34A)),
                  const SizedBox(width: 14),
                  _AmountChip(
                    label: 'Balance',
                    value: '₹$balance',
                    color: (balance is num && balance > 0) ? const Color(0xFFDC2626) : Colors.grey.shade600,
                  ),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Icon(Icons.calendar_today_outlined, size: 12, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text('Due: ${_fmtDate(invoice['due_date'])}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AmountChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _AmountChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}

// ─── Tenant Self Check-in (QR → form) ─────────────────────────────────────

class _SelfCheckinCard extends StatelessWidget {
  const _SelfCheckinCard({this.propertyId});

  final int? propertyId;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => _SelfCheckinSheet(propertyId: propertyId),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4F2DE4), Color(0xFF7C5CF6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.qr_code_2, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Tenant Self Check-in',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
              SizedBox(height: 2),
              Text('Show a QR the new tenant scans to fill their own details',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
          const Icon(Icons.chevron_right, color: Colors.white70),
        ]),
      ),
    );
  }
}

class _SelfCheckinSheet extends StatefulWidget {
  const _SelfCheckinSheet({this.propertyId});

  final int? propertyId;

  @override
  State<_SelfCheckinSheet> createState() => _SelfCheckinSheetState();
}

class _SelfCheckinSheetState extends State<_SelfCheckinSheet> {
  String? _url;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<AppState>().apiClient;
      final query = widget.propertyId != null ? '?propertyId=${widget.propertyId}' : '';
      final data = await api.get('/tenants/self-checkin-link$query');
      if (!mounted) return;
      // Build the QR URL from the SAME backend origin the app is talking to, so the
      // QR host can never diverge from a working server (fixes localhost/LAN mismatch).
      final path = '${data['path'] ?? ''}';
      final base = api.baseUrl; // e.g. http://192.168.1.25:8080/api
      final origin = base.endsWith('/api') ? base.substring(0, base.length - 4) : base;
      setState(() {
        _url = path.isNotEmpty ? '$origin$path' : '${data['url'] ?? ''}';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(children: const [
              Icon(Icons.qr_code_2, color: PgColors.primary),
              SizedBox(width: 8),
              Expanded(
                child: Text('Tenant Self Check-in',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              ),
            ]),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              _buildError()
            else
              ..._buildQr(),
          ],
        ),
      ),
    );
  }

  Widget _buildError() => Column(children: [
        Text(_error.toString().replaceFirst('Exception: ', ''),
            textAlign: TextAlign.center,
            style: const TextStyle(color: PgColors.danger, fontSize: 13)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Retry'),
          onPressed: _load,
        ),
      ]);

  List<Widget> _buildQr() => [
        Text(
          'Ask the new tenant to scan this with their phone camera. They fill in their '
          'details and submit — the tenant then appears in your Tenants list, ready for '
          'bed assignment.',
          style: TextStyle(fontSize: 13, color: Colors.grey[700]),
        ),
        const SizedBox(height: 16),
        Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: PgColors.hairline),
            ),
            child: QrImageView(data: _url!, size: 220, backgroundColor: Colors.white),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
              color: const Color(0xFFF5F6FA), borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            Expanded(
              child: Text(_url!,
                  style: const TextStyle(fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: 'Copy link',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _url!));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Link copied')));
              },
            ),
          ]),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('Preview form'),
          onPressed: () =>
              launchUrl(Uri.parse(_url!), mode: LaunchMode.externalApplication),
        ),
      ];
}

// ─── Vehicle Yes/No field ─────────────────────────────────────────────────

class _VehicleField extends StatelessWidget {
  const _VehicleField({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Vehicle',
        prefixIcon: Icon(Icons.two_wheeler_outlined),
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      child: Row(
        children: [
          const Expanded(child: Text('Owns a vehicle?')),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: const [
              ButtonSegment(value: false, label: Text('No')),
              ButtonSegment(value: true, label: Text('Yes')),
            ],
            selected: {value},
            onSelectionChanged: (s) => onChanged(s.first),
          ),
        ],
      ),
    );
  }
}

// ─── Add Tenant Screen ────────────────────────────────────────────────────

class AddTenantScreen extends StatefulWidget {
  final int? propertyId;
  const AddTenantScreen({this.propertyId, super.key});

  @override
  State<AddTenantScreen> createState() => _AddTenantScreenState();
}

class _AddTenantScreenState extends State<AddTenantScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();
  final _aadhaar = TextEditingController();
  DateTime? _dob;
  final _address = TextEditingController();
  String? _gender;
  bool _hasVehicle = false;

  @override
  void dispose() {
    _fullName.dispose();
    _mobile.dispose();
    _email.dispose();
    _aadhaar.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 20),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      helpText: 'Select date of birth',
    );
    if (picked != null) setState(() => _dob = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Tenant')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SelfCheckinCard(propertyId: widget.propertyId),
                  const SizedBox(height: 16),
                  const Text('Personal Details',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _fullName,
                    decoration: const InputDecoration(
                        labelText: 'Full Name *',
                        prefixIcon: Icon(Icons.person_outline)),
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    validator: (v) =>
                        v == null || v.trim().length < 2 ? 'Min 2 characters' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _mobile,
                    decoration: const InputDecoration(
                        labelText: 'Mobile Number *',
                        prefixIcon: Icon(Icons.phone_outlined)),
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    textInputAction: TextInputAction.next,
                    validator: (v) =>
                        v == null || !RegExp(r'^[0-9]{10}$').hasMatch(v)
                            ? '10-digit mobile number required'
                            : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _gender,
                    decoration: const InputDecoration(
                        labelText: 'Gender', prefixIcon: Icon(Icons.wc_outlined)),
                    items: const [
                      DropdownMenuItem(value: 'MALE', child: Text('Male')),
                      DropdownMenuItem(value: 'FEMALE', child: Text('Female')),
                      DropdownMenuItem(value: 'OTHER', child: Text('Other')),
                    ],
                    onChanged: (v) => setState(() => _gender = v),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(
                        labelText: 'Email (optional)',
                        prefixIcon: Icon(Icons.email_outlined)),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _aadhaar,
                    decoration: const InputDecoration(
                        labelText: 'Aadhaar Number (12 digits)',
                        prefixIcon: Icon(Icons.credit_card_outlined)),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(12),
                    ],
                    textInputAction: TextInputAction.next,
                    validator: (v) {
                      if (v == null || v.isEmpty) return null;
                      return v.length != 12 ? '12-digit Aadhaar required' : null;
                    },
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: _pickDob,
                    borderRadius: BorderRadius.circular(8),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Date of Birth',
                        prefixIcon: const Icon(Icons.cake_outlined),
                        border: const OutlineInputBorder(),
                        suffixIcon: _dob != null
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () => setState(() => _dob = null),
                              )
                            : null,
                      ),
                      child: Text(
                        _dob != null
                            ? '${_dob!.day.toString().padLeft(2, '0')}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.year}'
                            : 'Tap to select',
                        style: _dob == null ? TextStyle(color: Colors.grey[500]) : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _address,
                    decoration: const InputDecoration(
                        labelText: 'Permanent Address',
                        prefixIcon: Icon(Icons.home_outlined)),
                    maxLines: 2,
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),
                  _VehicleField(
                    value: _hasVehicle,
                    onChanged: (v) => setState(() => _hasVehicle = v),
                  ),
                  const SizedBox(height: 24),
                  AsyncActionButton(
                    label: 'Register Tenant',
                    onPressed: () async {
                      if (!_formKey.currentState!.validate()) return;
                      try {
                        await context.read<AppState>().apiClient.post('/tenants', {
                          'fullName': _fullName.text.trim(),
                          'mobileNumber': _mobile.text.trim(),
                          if (_gender != null) 'gender': _gender,
                          if (_email.text.isNotEmpty) 'email': _email.text.trim(),
                          if (_aadhaar.text.isNotEmpty)
                            'aadhaarNumber': _aadhaar.text.trim(),
                          if (_dob != null)
                            'dateOfBirth': '${_dob!.year}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}',
                          if (_address.text.isNotEmpty)
                            'permanentAddress': _address.text.trim(),
                          'hasVehicle': _hasVehicle,
                          if (widget.propertyId != null)
                            'propertyId': widget.propertyId,
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
          ],
        ),
      ),
    );
  }
}

// ─── Edit Tenant Screen ───────────────────────────────────────────────────

class EditTenantScreen extends StatefulWidget {
  const EditTenantScreen({required this.tenant, super.key});

  final Map<String, dynamic> tenant;

  @override
  State<EditTenantScreen> createState() => _EditTenantScreenState();
}

class _EditTenantScreenState extends State<EditTenantScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _fullName =
      TextEditingController(text: '${widget.tenant['fullName'] ?? ''}');
  late final _mobile =
      TextEditingController(text: '${widget.tenant['mobileNumber'] ?? ''}');
  late final _email = TextEditingController(text: '${widget.tenant['email'] ?? ''}');
  late DateTime? _dob = () {
    final raw = widget.tenant['dateOfBirth']?.toString();
    if (raw == null || raw.isEmpty) return null;
    try { return DateTime.parse(raw); } catch (_) { return null; }
  }();
  late final _address =
      TextEditingController(text: '${widget.tenant['permanentAddress'] ?? ''}');
  late String? _gender = widget.tenant['gender'] as String?;
  late bool _hasVehicle = widget.tenant['hasVehicle'] == true;

  @override
  void dispose() {
    _fullName.dispose();
    _mobile.dispose();
    _email.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 20),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      helpText: 'Select date of birth',
    );
    if (picked != null) setState(() => _dob = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Tenant')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _fullName,
                    decoration: const InputDecoration(
                        labelText: 'Full Name *',
                        prefixIcon: Icon(Icons.person_outline)),
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    validator: (v) =>
                        v == null || v.trim().length < 2 ? 'Min 2 characters' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _mobile,
                    decoration: const InputDecoration(
                        labelText: 'Mobile Number *',
                        prefixIcon: Icon(Icons.phone_outlined)),
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    textInputAction: TextInputAction.next,
                    validator: (v) =>
                        v == null || !RegExp(r'^[0-9]{10}$').hasMatch(v)
                            ? '10-digit mobile number required'
                            : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _gender,
                    decoration: const InputDecoration(labelText: 'Gender'),
                    items: const [
                      DropdownMenuItem(value: 'MALE', child: Text('Male')),
                      DropdownMenuItem(value: 'FEMALE', child: Text('Female')),
                      DropdownMenuItem(value: 'OTHER', child: Text('Other')),
                    ],
                    onChanged: (v) => setState(() => _gender = v),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(
                        labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: _pickDob,
                    borderRadius: BorderRadius.circular(8),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Date of Birth',
                        prefixIcon: const Icon(Icons.cake_outlined),
                        border: const OutlineInputBorder(),
                        suffixIcon: _dob != null
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () => setState(() => _dob = null),
                              )
                            : null,
                      ),
                      child: Text(
                        _dob != null
                            ? '${_dob!.day.toString().padLeft(2, '0')}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.year}'
                            : 'Tap to select',
                        style: _dob == null ? TextStyle(color: Colors.grey[500]) : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _address,
                    decoration: const InputDecoration(
                        labelText: 'Permanent Address',
                        prefixIcon: Icon(Icons.home_outlined)),
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),
                  _VehicleField(
                    value: _hasVehicle,
                    onChanged: (v) => setState(() => _hasVehicle = v),
                  ),
                  const SizedBox(height: 24),
                  AsyncActionButton(
                    label: 'Save Changes',
                    onPressed: () async {
                      if (!_formKey.currentState!.validate()) return;
                      final id = widget.tenant['tenantId'];
                      try {
                        await context.read<AppState>().apiClient.put(
                            '/tenants/$id', {
                          'fullName': _fullName.text.trim(),
                          'mobileNumber': _mobile.text.trim(),
                          if (_gender != null) 'gender': _gender,
                          if (_email.text.isNotEmpty) 'email': _email.text.trim(),
                          if (_dob != null)
                            'dateOfBirth': '${_dob!.year}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}',
                          if (_address.text.isNotEmpty)
                            'permanentAddress': _address.text.trim(),
                          'hasVehicle': _hasVehicle,
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
          ],
        ),
      ),
    );
  }
}

// ─── Edit Emergency Contact Sheet ─────────────────────────────────────────

class _EditEmergencyContactSheet extends StatefulWidget {
  const _EditEmergencyContactSheet({required this.tenant});

  final Map<String, dynamic> tenant;

  @override
  State<_EditEmergencyContactSheet> createState() =>
      _EditEmergencyContactSheetState();
}

class _EditEmergencyContactSheetState extends State<_EditEmergencyContactSheet> {
  late final _name =
      TextEditingController(text: '${widget.tenant['emergencyContactName'] ?? ''}');
  late final _mobile = TextEditingController(
      text: '${widget.tenant['emergencyContactMobile'] ?? ''}');
  late final _relation = TextEditingController(
      text: '${widget.tenant['emergencyContactRelation'] ?? ''}');
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    _relation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, padding + 20),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Text('Emergency Contact',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              const Spacer(),
              IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: 'Contact Name *',
                  prefixIcon: Icon(Icons.person_outline)),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _mobile,
              decoration: const InputDecoration(
                  labelText: 'Mobile Number *',
                  prefixIcon: Icon(Icons.phone_outlined)),
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  v == null || !RegExp(r'^[0-9]{10}$').hasMatch(v)
                      ? '10-digit mobile number required'
                      : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _relation,
              decoration: const InputDecoration(
                  labelText: 'Relation (e.g. Parent, Sibling)',
                  prefixIcon: Icon(Icons.family_restroom)),
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 20),
            AsyncActionButton(
              label: 'Save',
              onPressed: () async {
                if (!_formKey.currentState!.validate()) return;
                final id = widget.tenant['tenantId'];
                try {
                  await context.read<AppState>().apiClient.patch(
                      '/tenants/$id', {
                    'emergencyContactName': _name.text.trim(),
                    'emergencyContactMobile': _mobile.text.trim(),
                    'emergencyContactRelation': _relation.text.trim(),
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
    );
  }
}

// ─── Edit Employment Sheet ────────────────────────────────────────────────

class _EditEmploymentSheet extends StatefulWidget {
  const _EditEmploymentSheet({required this.tenant});

  final Map<String, dynamic> tenant;

  @override
  State<_EditEmploymentSheet> createState() => _EditEmploymentSheetState();
}

class _EditEmploymentSheetState extends State<_EditEmploymentSheet> {
  late final _employer =
      TextEditingController(text: '${widget.tenant['employerName'] ?? ''}');
  late final _designation =
      TextEditingController(text: '${widget.tenant['designation'] ?? ''}');
  late final _workAddress =
      TextEditingController(text: '${widget.tenant['workAddress'] ?? ''}');

  @override
  void dispose() {
    _employer.dispose();
    _designation.dispose();
    _workAddress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, padding + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Text('Employment Details',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const Spacer(),
            IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 16),
          TextFormField(
            controller: _employer,
            decoration: const InputDecoration(
                labelText: 'Employer Name',
                prefixIcon: Icon(Icons.business_outlined)),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _designation,
            decoration: const InputDecoration(
                labelText: 'Designation', prefixIcon: Icon(Icons.work_outline)),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _workAddress,
            decoration: const InputDecoration(
                labelText: 'Work Address',
                prefixIcon: Icon(Icons.location_on_outlined)),
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 20),
          AsyncActionButton(
            label: 'Save',
            onPressed: () async {
              final id = widget.tenant['tenantId'];
              try {
                await context.read<AppState>().apiClient.patch('/tenants/$id', {
                  if (_employer.text.isNotEmpty) 'employerName': _employer.text.trim(),
                  if (_designation.text.isNotEmpty)
                    'designation': _designation.text.trim(),
                  if (_workAddress.text.isNotEmpty)
                    'workAddress': _workAddress.text.trim(),
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
    );
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────────────

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.title, required this.items});

  final String title;
  final List<(String, String, IconData)> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: PgColors.primary)),
            const SizedBox(height: 12),
            ...items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(item.$3, size: 18, color: Colors.grey),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.$1,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey)),
                            Text(item.$2,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _TenantErrorState extends StatelessWidget {
  const _TenantErrorState({required this.error, required this.onRetry});
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) =>
      ErrorRetryView(error: error ?? Exception('Unknown error'), onRetry: onRetry);
}

class _TenantEmptyState extends StatelessWidget {
  const _TenantEmptyState({this.onAdd});
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.people_outline, size: 56, color: PgColors.primary),
            const SizedBox(height: 16),
            const Text('No tenants found',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 6),
            const Text('Register tenants to track occupancy and payments.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey)),
            if (onAdd != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('Add Tenant'),
                onPressed: onAdd,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
