import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/animations.dart';
import 'property_workspace_screen.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _greeting() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Good Morning';
  if (h < 17) return 'Good Afternoon';
  return 'Good Evening';
}

String _compactAmount(dynamic v) {
  if (v == null) return '—';
  final d = (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;
  if (d >= 100000) return '₹${(d / 100000).toStringAsFixed(2)}L';
  if (d >= 1000) return '₹${(d / 1000).toStringAsFixed(0)}K';
  return '₹${d.toStringAsFixed(0)}';
}

// ─── Dashboard Screen ─────────────────────────────────────────────────────────

class PgDashboardScreen extends StatefulWidget {
  const PgDashboardScreen({super.key});
  @override
  State<PgDashboardScreen> createState() => _PgDashboardScreenState();
}

class _PgDashboardScreenState extends State<PgDashboardScreen> {
  late Future<_DashData> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final api = context.read<AppState>().apiClient;
    _future = Future.wait([
      api.get('/owner/dashboard'),
      api.get('/owner/properties'),
    ]).then((results) => _DashData(
          stats: results[0],
          properties: results[1]['items'] is List
              ? (results[1]['items'] as List).cast<Map<String, dynamic>>()
              : <Map<String, dynamic>>[],
        ));
  }

  void _openAddProperty() {
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DashAddPropertySheet(onSaved: () => setState(_load)),
    ).then((added) {
      if (added == true) setState(_load);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ownerName = context.watch<AppState>().ownerName ?? 'Owner';
    final firstName = ownerName.split(' ').first;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: FutureBuilder<_DashData>(
          future: _future,
          builder: (context, snapshot) {
            final data = snapshot.data;
            final stats = data?.stats ?? {};
            final properties = data?.properties ?? [];

            return RefreshIndicator(
              onRefresh: () async => setState(_load),
              child: CustomScrollView(
                slivers: [
                  // ── Top bar ─────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                      child: Row(
                        children: [
                          // Purple hamburger circle
                          GestureDetector(
                            onTap: () => context.go('/settings'),
                            child: Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: PgColors.primary,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.menu_rounded,
                                  color: Colors.white, size: 22),
                            ),
                          ),
                          const Spacer(),
                          // Notification bell with badge
                          Stack(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.notifications_outlined,
                                    size: 26, color: PgColors.textPrimary),
                                onPressed: () => context.push('/notifications'),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  width: 9,
                                  height: 9,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFEF4444),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Greeting ─────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: FadeSlideIn(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RichText(
                              text: TextSpan(
                                style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: PgColors.textPrimary),
                                children: [
                                  TextSpan(text: '${_greeting()}, $firstName! '),
                                  const TextSpan(text: '👋'),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              "Here's what's happening with your properties today.",
                              style: TextStyle(
                                  fontSize: 13.5,
                                  color: PgColors.textSecondary,
                                  height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ── Stats row ─────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: FadeSlideIn(
                      delay: const Duration(milliseconds: 60),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                        child: snapshot.connectionState ==
                                ConnectionState.waiting
                            ? _StatsShimmer()
                            : Row(
                                children: [
                                  _StatCard(
                                    icon: Icons.apartment_rounded,
                                    iconColor: PgColors.primary,
                                    iconBg: const Color(0xFFEDE9FF),
                                    value: '${properties.length}',
                                    label: 'Properties',
                                    accentColor: PgColors.primary,
                                  ),
                                  _StatCard(
                                    icon: Icons.bed_outlined,
                                    iconColor: const Color(0xFF0D9488),
                                    iconBg: const Color(0xFFCCFBF1),
                                    value: '${stats['totalBeds'] ?? 0}',
                                    label: 'Total Beds',
                                    accentColor: const Color(0xFF0D9488),
                                  ),
                                  _StatCard(
                                    icon: Icons.people_alt_outlined,
                                    iconColor: const Color(0xFF2563EB),
                                    iconBg: const Color(0xFFDBEAFE),
                                    value: '${stats['occupiedBeds'] ?? 0}',
                                    label: 'Occupied',
                                    accentColor: const Color(0xFF2563EB),
                                  ),
                                  _StatCard(
                                    icon: Icons.account_balance_wallet_outlined,
                                    iconColor: const Color(0xFFD97706),
                                    iconBg: const Color(0xFFFEF3C7),
                                    value: _compactAmount(stats['revenue']),
                                    label: 'Monthly',
                                    accentColor: const Color(0xFFD97706),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),

                  // ── Section header ────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: FadeSlideIn(
                      delay: const Duration(milliseconds: 100),
                      child: Padding(
                        padding:
                            const EdgeInsets.fromLTRB(20, 24, 16, 14),
                        child: Row(
                          children: [
                            const Text('Your Properties',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: PgColors.textPrimary)),
                            const Spacer(),
                            FilledButton.icon(
                              onPressed: _openAddProperty,
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Add Property'),
                              style: FilledButton.styleFrom(
                                backgroundColor: PgColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                textStyle: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(24)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ── Property list ──────────────────────────────────────────
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const SliverToBoxAdapter(
                      child: Center(
                          child: Padding(
                        padding: EdgeInsets.all(48),
                        child: CircularProgressIndicator(),
                      )),
                    )
                  else if (snapshot.hasError)
                    SliverToBoxAdapter(child: _ErrorBanner(onRetry: () => setState(_load)))
                  else if (properties.isEmpty)
                    SliverToBoxAdapter(child: _EmptyProperties(onAdd: _openAddProperty))
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      sliver: SliverList.separated(
                        itemCount: properties.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, i) => FadeSlideIn(
                          delay: Duration(milliseconds: 40 * i.clamp(0, 8)),
                          child: _PropertyCard(
                            property: properties[i],
                            colorIndex: i,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => PropertyWorkspaceScreen(
                                      property: properties[i])),
                            ).then((_) => setState(_load)),
                          ),
                        ),
                      ),
                    ),

                  // ── Grow CTA ──────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: FadeSlideIn(
                      delay: const Duration(milliseconds: 150),
                      child: Padding(
                        padding:
                            const EdgeInsets.fromLTRB(16, 4, 16, 28),
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFEDE9FF),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color:
                                      PgColors.primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(Icons.bar_chart_rounded,
                                    color: PgColors.primary, size: 26),
                              ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text('Grow Your Business',
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                            color: PgColors.primary)),
                                    SizedBox(height: 3),
                                    Text(
                                      'Add more properties and manage everything in one place.',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: PgColors.textSecondary,
                                          height: 1.4),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: _openAddProperty,
                                style: TextButton.styleFrom(
                                    foregroundColor: PgColors.primary,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6)),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('Add',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13)),
                                    SizedBox(width: 2),
                                    Icon(Icons.chevron_right, size: 18),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── Data container ────────────────────────────────────────────────────────────

class _DashData {
  final Map<String, dynamic> stats;
  final List<Map<String, dynamic>> properties;
  const _DashData({required this.stats, required this.properties});
}

// ─── Stat Card ────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.value,
    required this.label,
    required this.accentColor,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String value;
  final String label;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: accentColor,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: PgColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Container(
              height: 3,
              width: 22,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Stats shimmer (loading placeholder) ──────────────────────────────────────

class _StatsShimmer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(
        4,
        (_) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            height: 100,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Property Card ────────────────────────────────────────────────────────────

class _PropertyCard extends StatefulWidget {
  const _PropertyCard({
    required this.property,
    required this.colorIndex,
    required this.onTap,
  });
  final Map<String, dynamic> property;
  final int colorIndex;
  final VoidCallback onTap;

  @override
  State<_PropertyCard> createState() => _PropertyCardState();
}

class _PropertyCardState extends State<_PropertyCard> {
  Map<String, dynamic>? _stats;

  static const _gradients = [
    [Color(0xFF4F46E5), Color(0xFF7C3AED)], // indigo → violet
    [Color(0xFF059669), Color(0xFF0D9488)], // emerald → teal
    [Color(0xFF0284C7), Color(0xFF0EA5E9)], // sky blue
    [Color(0xFFDC2626), Color(0xFFEA580C)], // red → orange
  ];

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    final id = widget.property['facilityId'];
    if (id == null) return;
    try {
      final data = await context.read<AppState>().apiClient.get('/properties/$id/stats');
      if (mounted) setState(() => _stats = data as Map<String, dynamic>?);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.property;
    final name = '${p['facilityName'] ?? 'Property'}';
    final desc = '${p['description'] ?? ''}';
    final capacity = p['capacity'];

    final pair = _gradients[widget.colorIndex % _gradients.length];

    final totalFloors = _stats?['totalFloors'] ?? '—';
    final totalRooms = _stats?['totalRooms'] ?? _stats?['totalBeds'] ?? capacity ?? '—';
    final occupied = _stats?['occupiedBeds'] ?? '—';
    final vacant = _stats?['vacantBeds'] ?? '—';

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Gradient thumbnail ───────────────────────────────────────
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
              child: Container(
                width: 110,
                height: 130,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: pair,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.apartment_rounded,
                        color: Colors.white54, size: 52),
                    Positioned(
                      bottom: 8,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.layers_outlined,
                                  color: Colors.white, size: 12),
                              const SizedBox(width: 3),
                              Text(
                                '$totalFloors Floors',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Content ───────────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: PgColors.textPrimary,
                            ),
                          ),
                        ),
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.chevron_right,
                              color: PgColors.textSecondary, size: 18),
                        ),
                      ],
                    ),
                    if (desc.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined,
                              size: 12, color: PgColors.textSecondary),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              desc,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12, color: PgColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    // Stats chips
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _MiniStat(
                          icon: Icons.bed_outlined,
                          value: '$totalRooms',
                          label: 'Rooms',
                          color: const Color(0xFF2563EB),
                          bg: const Color(0xFFEFF6FF),
                        ),
                        _MiniStat(
                          icon: Icons.people_alt_outlined,
                          value: '$occupied',
                          label: 'Occupied',
                          color: const Color(0xFF059669),
                          bg: const Color(0xFFECFDF5),
                        ),
                        _MiniStat(
                          icon: Icons.door_front_door_outlined,
                          value: '$vacant',
                          label: 'Vacant',
                          color: const Color(0xFFD97706),
                          bg: const Color(0xFFFEF3C7),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Mini Stat Chip ───────────────────────────────────────────────────────────

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.bg,
  });
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: color)),
              Text(label,
                  style: const TextStyle(
                      fontSize: 9,
                      color: PgColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Error banner ─────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 48, color: PgColors.danger),
          const SizedBox(height: 12),
          const Text('Could not load data',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyProperties extends StatelessWidget {
  const _EmptyProperties({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [PgColors.primary, Color(0xFF7C3AED)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.apartment_rounded,
                size: 40, color: Colors.white),
          ),
          const SizedBox(height: 20),
          const Text('No properties yet',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 8),
          Text(
            'Add your first property to start managing\ntenants, rooms, and payments.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600], height: 1.5),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add Property'),
          ),
        ],
      ),
    );
  }
}

// ─── Add Property Sheet ───────────────────────────────────────────────────────

class _DashAddPropertySheet extends StatefulWidget {
  final VoidCallback onSaved;
  const _DashAddPropertySheet({required this.onSaved});
  @override
  State<_DashAddPropertySheet> createState() => _DashAddPropertySheetState();
}

class _DashAddPropertySheetState extends State<_DashAddPropertySheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _capacity = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final api = context.read<AppState>().apiClient;
      final storage = context.read<AppState>().storage;
      final orgId = await storage.read(key: 'organizationId');
      await api.post('/facilities', {
        'parentFacilityId': int.parse(orgId ?? '0'),
        'facilityTypeId': 'PROPERTY',
        'facilityName': _name.text.trim(),
        if (_desc.text.isNotEmpty) 'description': _desc.text.trim(),
        if (_capacity.text.isNotEmpty) 'capacity': int.parse(_capacity.text),
      });
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSaved();
    } catch (e) {
      setState(() => _saving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
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
                textCapitalization: TextCapitalization.words,
                validator: (v) => v == null || v.trim().length < 2 ? 'Min 2 characters' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _desc,
                decoration: const InputDecoration(
                    labelText: 'Address / Location',
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
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Add Property'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Analytics stub ───────────────────────────────────────────────────────────

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Analytics')),
        body: const FadeSlideIn(child: Center(child: Text('Analytics coming soon'))),
      );
}
