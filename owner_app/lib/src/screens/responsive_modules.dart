import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../theme/app_theme.dart';
import 'property_workspace_screen.dart';

class PgDashboardScreen extends StatefulWidget {
  const PgDashboardScreen({super.key});
  @override
  State<PgDashboardScreen> createState() => _PgDashboardScreenState();
}

class _PgDashboardScreenState extends State<PgDashboardScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = context.read<AppState>().apiClient.get('/owner/properties');
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Top bar ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.menu, size: 24),
                    style: IconButton.styleFrom(
                        padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    onPressed: () => context.go('/settings'),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined, size: 24),
                    style: IconButton.styleFrom(
                        padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    onPressed: () => context.push('/notifications'),
                  ),
                ],
              ),
            ),
            // ─── Title ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Property Dashboard',
                      style: TextStyle(
                          fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E))),
                  const SizedBox(height: 4),
                  Text(
                    'Welcome back, ${context.watch<AppState>().ownerName ?? 'Owner'}!',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // ─── Section header ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
              child: Row(
                children: [
                  const Text('Your Properties',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A2E))),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: _openAddProperty,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Property'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: PgColors.primary,
                      side: const BorderSide(color: PgColors.primary),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            // ─── Property list ────────────────────────────────────────
            Expanded(
              child: FutureBuilder<Map<String, dynamic>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.cloud_off, size: 48, color: PgColors.danger),
                            const SizedBox(height: 12),
                            const Text('Could not load properties',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            Text('${snapshot.error}',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                            const SizedBox(height: 16),
                            OutlinedButton(
                                onPressed: () => setState(_load),
                                child: const Text('Try again')),
                          ],
                        ),
                      ),
                    );
                  }
                  final items =
                      (snapshot.data?['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                  if (items.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [PgColors.primary, PgColors.primaryDark],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Icon(Icons.apartment_outlined,
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
                              onPressed: _openAddProperty,
                              icon: const Icon(Icons.add),
                              label: const Text('Add Property'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async => setState(_load),
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final prop = items[index];
                        return _PropertyCard(
                          property: prop,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    PropertyWorkspaceScreen(property: prop)),
                          ).then((_) => setState(_load)),
                        );
                      },
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
}

// ─── Property Card ────────────────────────────────────────────────────────────

class _PropertyCard extends StatelessWidget {
  final Map<String, dynamic> property;
  final VoidCallback onTap;
  const _PropertyCard({required this.property, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = '${property['facilityName'] ?? 'Property'}';
    final desc = '${property['description'] ?? ''}';
    final capacity = property['capacity'];
    // Color derived from property name for visual variety
    final colors = [
      [const Color(0xFF6C5CE7), const Color(0xFF4A3FA6)],
      [const Color(0xFF00B894), const Color(0xFF007A63)],
      [const Color(0xFF0984E3), const Color(0xFF0652A1)],
      [const Color(0xFFE17055), const Color(0xFFA84532)],
    ];
    final colorPair = colors[name.hashCode.abs() % colors.length];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Building image placeholder
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: colorPair,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.apartment, color: Colors.white, size: 30),
                      const SizedBox(height: 4),
                      Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'P',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: Color(0xFF1A1A2E))),
                      if (desc.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(desc,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Color(0xFF6B7280), fontSize: 13)),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.bed_outlined,
                              size: 14, color: colorPair[0]),
                          const SizedBox(width: 4),
                          Text(
                            capacity != null ? '$capacity Rooms' : 'Tap to view',
                            style: TextStyle(
                                color: colorPair[0],
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Color(0xFFD1D5DB)),
              ],
            ),
          ),
        ),
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
      final orgId = await context.read<AppState>().storage.read(key: 'organizationId');
      await context.read<AppState>().apiClient.post('/facilities', {
        'parentFacilityId': int.parse(orgId ?? '0'),
        'facilityTypeId': 'PROPERTY',
        'facilityName': _name.text.trim(),
        if (_desc.text.isNotEmpty) 'description': _desc.text.trim(),
        if (_capacity.text.isNotEmpty) 'capacity': int.parse(_capacity.text),
      });
      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
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

// ─── Shared widgets re-exported for other files ────────────────────────────────

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Analytics')),
        body: const Center(child: Text('Analytics coming soon')),
      );
}
