import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_shell.dart';

class PgDashboardScreen extends StatefulWidget {
  const PgDashboardScreen({super.key});
  @override
  State<PgDashboardScreen> createState() => _PgDashboardScreenState();
}

class _PgDashboardScreenState extends State<PgDashboardScreen> {
  late Future<Map<String, dynamic>> data;
  @override
  void initState() { super.initState(); data = context.read<AppState>().apiClient.get('/owner/dashboard'); }

  @override
  Widget build(BuildContext context) => AppShell(
        title: 'Dashboard',
        actions: [IconButton(tooltip: 'Analytics', onPressed: () => context.go('/dashboard/analytics'), icon: const Icon(Icons.insights_outlined))],
        child: FutureBuilder<Map<String, dynamic>>(
          future: data,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError) return ErrorState(error: snapshot.error, retry: () => setState(() => data = context.read<AppState>().apiClient.get('/owner/dashboard')));
            final value = snapshot.data ?? const <String, dynamic>{};
            return ListView(children: [
              Text('Welcome back 👋', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 18),
              Wrap(spacing: 12, runSpacing: 12, children: [
                MetricCard(label: 'Total Tenants', value: value['totalTenants'], icon: Icons.people_outline, color: PgColors.primary),
                MetricCard(label: 'Occupied Beds', value: value['occupiedBeds'], icon: Icons.bed, color: const Color(0xFF2563EB)),
                MetricCard(label: 'Vacant Beds', value: value['vacantBeds'], icon: Icons.bed_outlined, color: PgColors.success),
                MetricCard(label: 'Monthly Revenue', value: '₹${value['revenue'] ?? 0}', icon: Icons.currency_rupee, color: PgColors.warning),
              ]),
              const SizedBox(height: 20),
              LayoutBuilder(builder: (context, constraints) {
                final horizontal = constraints.maxWidth > 700;
                final cards = [
                  _Panel(title: 'Revenue overview', child: SizedBox(height: 180, child: CustomPaint(painter: _TrendPainter()))),
                  _Panel(title: 'Pending payments', child: ListTile(contentPadding: EdgeInsets.zero, title: Text('₹${value['pendingRent'] ?? 0}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: PgColors.danger)), subtitle: const Text('Review outstanding invoices'), trailing: const Icon(Icons.chevron_right))),
                ];
                return horizontal ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: cards.map((e) => Expanded(child: Padding(padding: const EdgeInsets.only(right: 12), child: e))).toList()) : Column(children: cards);
              }),
              const SizedBox(height: 20),
              _Panel(title: 'Quick actions', child: Wrap(spacing: 12, runSpacing: 12, children: [
                QuickAction(label: 'Add tenant', icon: Icons.person_add_alt, path: '/tenants/manage'),
                QuickAction(label: 'Add room', icon: Icons.add_home_work_outlined, path: '/properties/manage'),
                QuickAction(label: 'Collect rent', icon: Icons.currency_rupee, path: '/billing/manage'),
                QuickAction(label: 'New notice', icon: Icons.note_add_outlined, path: '/notifications'),
                QuickAction(label: 'Reports', icon: Icons.bar_chart, path: '/dashboard/analytics'),
              ])),
            ]);
          },
        ),
      );
}

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});
  @override
  Widget build(BuildContext context) => AppShell(
        title: 'Analytics',
        child: ListView(children: [
          Wrap(spacing: 12, runSpacing: 12, children: const [
            MetricCard(label: 'Occupancy Rate', value: '—', icon: Icons.donut_large, color: PgColors.primary),
            MetricCard(label: 'Collection Rate', value: '—', icon: Icons.trending_up, color: Color(0xFF2563EB)),
            MetricCard(label: 'Avg. Rent / Bed', value: '—', icon: Icons.bed, color: PgColors.success),
            MetricCard(label: 'Total Revenue', value: '—', icon: Icons.currency_rupee, color: PgColors.warning),
          ]),
          const SizedBox(height: 16),
          const _Panel(title: 'Revenue overview', child: SizedBox(height: 280, child: CustomPaint(painter: _BarPainter()))),
        ]),
      );
}

class ModuleOverviewScreen extends StatefulWidget {
  const ModuleOverviewScreen({required this.title, required this.endpoint, required this.features, super.key});
  final String title;
  final String endpoint;
  final List<ModuleFeature> features;
  @override
  State<ModuleOverviewScreen> createState() => _ModuleOverviewScreenState();
}

class _ModuleOverviewScreenState extends State<ModuleOverviewScreen> {
  late Future<Map<String, dynamic>> future;
  @override
  void initState() { super.initState(); future = context.read<AppState>().apiClient.get(widget.endpoint); }
  @override
  Widget build(BuildContext context) => AppShell(
        title: widget.title,
        child: ListView(children: [
          Wrap(spacing: 12, runSpacing: 12, children: widget.features.map((f) => SizedBox(
            width: 210,
            child: Card(child: InkWell(borderRadius: BorderRadius.circular(14), onTap: f.path == null ? null : () => context.go(f.path!), child: Padding(
              padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(backgroundColor: PgColors.lavender, foregroundColor: PgColors.primary, child: Icon(f.icon)),
                const SizedBox(height: 14), Text(f.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4), Text(f.description, style: Theme.of(context).textTheme.bodySmall),
                if (f.disabled) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Storage not configured', style: TextStyle(color: PgColors.warning, fontSize: 12))),
              ]),
            ))),
          )).toList()),
          const SizedBox(height: 20),
          _Panel(title: 'Current records', child: FutureBuilder<Map<String, dynamic>>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()));
              if (snapshot.hasError) return ErrorState(error: snapshot.error, retry: () => setState(() => future = context.read<AppState>().apiClient.get(widget.endpoint)));
              final raw = snapshot.data ?? const <String, dynamic>{};
              final items = raw['items'];
              if (items is List) return RecordList(items: items);
              return KeyValueSummary(values: raw);
            },
          )),
        ]),
      );
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String filter = 'ACTIVE';
  late Future<Map<String, dynamic>> future;
  @override
  void initState() { super.initState(); _load(); }
  void _load() { future = context.read<AppState>().apiClient.get('/notifications?state=$filter'); }
  @override
  Widget build(BuildContext context) => AppShell(
        title: filter == 'ARCHIVED' ? 'Archived Notifications' : 'Notifications',
        actions: [IconButton(tooltip: 'Notification settings', onPressed: () => context.go('/notifications/settings'), icon: const Icon(Icons.settings_outlined))],
        child: Column(children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              children: ['ACTIVE', 'UNREAD', 'IMPORTANT', 'ARCHIVED']
                  .map(
                    (v) => ChoiceChip(
                  label: Text(v.toLowerCase()),
                  selected: filter == v,
                  onSelected: (_) {
                    setState(() {
                      filter = v;
                      _load();
                    });
                  },
                ),
              )
                  .toList(),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: FutureBuilder<Map<String, dynamic>>(future: future, builder: (context, snapshot) {
            if (!snapshot.hasData) return snapshot.hasError ? ErrorState(error: snapshot.error, retry: () => setState(_load)) : const Center(child: CircularProgressIndicator());
            final items = snapshot.data!['items'] as List? ?? [];
            if (items.isEmpty) return const EmptyState(icon: Icons.notifications_none, title: 'No notifications', message: 'Updates will appear here.');
            return ListView.separated(itemCount: items.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (context, index) {
              final item = items[index] as Map<String, dynamic>;
              return Card(child: ListTile(
                leading: const CircleAvatar(backgroundColor: PgColors.lavender, child: Icon(Icons.notifications_outlined, color: PgColors.primary)),
                title: Text('${item['title']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${item['message']}'),
                trailing: PopupMenuButton<String>(onSelected: (action) async {
                  final id = item['notification_id'];
                  await context.read<AppState>().apiClient.patch('/notifications/$id/${action == 'read' ? 'read' : 'archive'}', {});
                  setState(_load);
                }, itemBuilder: (_) => const [PopupMenuItem(value: 'read', child: Text('Mark as read')), PopupMenuItem(value: 'archive', child: Text('Archive'))]),
              ));
            });
          })),
        ]),
      );
}

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});
  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}
class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  late Future<Map<String, dynamic>> future;
  @override
  void initState() { super.initState(); future = context.read<AppState>().apiClient.get('/notifications/preferences'); }
  @override
  Widget build(BuildContext context) => AppShell(title: 'Notification Settings', child: FutureBuilder<Map<String, dynamic>>(future: future, builder: (context, snapshot) {
    final items = snapshot.data?['items'] as List?;
    if (items == null) return const Center(child: CircularProgressIndicator());
    return ListView(children: items.map((raw) {
      final item = raw as Map<String, dynamic>;
      final enabled = item['enabled'] == true || item['enabled'] == 1;
      return Card(child: SwitchListTile(value: enabled, title: Text('${item['name']}', style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text('${item['description'] ?? ''}'), onChanged: (value) async {
        await context.read<AppState>().apiClient.patch('/notifications/preferences', {'${item['category_id']}': value});
        setState(() => future = context.read<AppState>().apiClient.get('/notifications/preferences'));
      }));
    }).toList());
  }));
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}
class _SettingsScreenState extends State<SettingsScreen> {
  late Future<Map<String, dynamic>> preferences;
  @override
  void initState() { super.initState(); preferences = context.read<AppState>().apiClient.get('/account/preferences'); }
  @override
  Widget build(BuildContext context) => AppShell(title: 'Settings', child: ListView(children: [
    Card(child: ListTile(leading: const CircleAvatar(backgroundColor: PgColors.lavender, child: Icon(Icons.person, color: PgColors.primary)), title: const Text('Profile Information'), subtitle: const Text('Personal and work information'), trailing: const Icon(Icons.chevron_right), onTap: () => context.go('/settings/profile'))),
    const SizedBox(height: 12),
    _SettingsGroup(title: 'Account', children: [
      _SettingTile(icon: Icons.lock_outline, title: 'Change Password', onTap: () => context.go('/settings/password')),
      FutureBuilder<String?>(future: context.read<AppState>().storage.read(key: 'biometricEnabled'), builder: (context, snapshot) => SwitchListTile(
        secondary: const Icon(Icons.fingerprint), title: const Text('Biometric & Security'), subtitle: const Text('Unlock locally using device security'),
        value: snapshot.data == 'true', onChanged: (value) async { await context.read<AppState>().setBiometricEnabled(value); if (mounted) setState(() {}); },
      )),
      const _SettingTile(icon: Icons.phonelink_lock, title: 'Two-Factor Authentication', subtitle: 'Provider-ready'),
    ]),
    _SettingsGroup(title: 'Preferences', children: [
      _SettingTile(icon: Icons.notifications_outlined, title: 'Notification Settings', onTap: () => context.go('/notifications/settings')),
      FutureBuilder<Map<String, dynamic>>(future: preferences, builder: (context, snapshot) => _SettingTile(icon: Icons.palette_outlined, title: 'Theme & Appearance', subtitle: '${snapshot.data?['theme'] ?? 'LIGHT'}')),
      const _SettingTile(icon: Icons.language, title: 'Language', subtitle: 'English'),
    ]),
    _SettingsGroup(title: 'Data & Storage', children: [
      const _SettingTile(icon: Icons.cloud_off_outlined, title: 'Backup & Sync', subtitle: 'Cloud backup is not configured'),
      _SettingTile(icon: Icons.delete_outline, title: 'Clear Cache', onTap: () async {
        final cache = await SharedPreferences.getInstance(); await cache.clear();
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Local cache cleared. Account data remains synchronized.')));
      }),
    ]),
  ]));
}

class SuperAdminScreen extends StatefulWidget {
  const SuperAdminScreen({super.key});
  @override
  State<SuperAdminScreen> createState() => _SuperAdminScreenState();
}
class _SuperAdminScreenState extends State<SuperAdminScreen> {
  int selected = 0;
  static const sections = [
    ('Dashboard', '/super-admin/dashboard', Icons.dashboard_outlined), ('Properties', '/super-admin/properties', Icons.apartment_outlined),
    ('Customers', '/super-admin/organizations', Icons.business_outlined), ('Users', '/super-admin/users', Icons.people_outline),
    ('Roles & Permissions', '/super-admin/roles', Icons.admin_panel_settings_outlined), ('Plans & Pricing', '/super-admin/plans', Icons.sell_outlined),
    ('Reports', '/super-admin/reports/revenue', Icons.bar_chart), ('Audit Logs', '/super-admin/audit-logs', Icons.history),
    ('System Settings', '/super-admin/system-settings', Icons.settings_outlined),
  ];
  @override
  Widget build(BuildContext context) {
    final section = sections[selected];
    return AppShell(title: section.$1, child: Row(children: [
      NavigationRail(selectedIndex: selected, labelType: NavigationRailLabelType.none, onDestinationSelected: (value) => setState(() => selected = value), destinations: sections.map((s) => NavigationRailDestination(icon: Icon(s.$3), label: Text(s.$1))).toList()),
      const VerticalDivider(width: 1),
      Expanded(child: Padding(padding: const EdgeInsets.only(left: 20), child: FutureBuilder<Map<String, dynamic>>(
        key: ValueKey(selected), future: context.read<AppState>().apiClient.get(section.$2), builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return ErrorState(error: snapshot.error, retry: () => setState(() {}));
          final data = snapshot.data ?? const <String, dynamic>{};
          final items = data['items'];
          if (items is List) return RecordList(items: items);
          return ListView(children: [KeyValueSummary(values: data)]);
        },
      ))),
    ]));
  }
}

class ModuleFeature {
  const ModuleFeature(this.label, this.description, this.icon, {this.path, this.disabled = false});
  final String label;
  final String description;
  final IconData icon;
  final String? path;
  final bool disabled;
}

class MetricCard extends StatelessWidget {
  const MetricCard({required this.label, required this.value, required this.icon, required this.color, super.key});
  final String label; final Object? value; final IconData icon; final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(width: 210, child: Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
    CircleAvatar(backgroundColor: color.withValues(alpha: .1), foregroundColor: color, child: Icon(icon)), const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: Theme.of(context).textTheme.bodySmall), const SizedBox(height: 6), Text('${value ?? '—'}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800))])),
  ]))));
}

class QuickAction extends StatelessWidget {
  const QuickAction({required this.label, required this.icon, required this.path, super.key});
  final String label; final IconData icon; final String path;
  @override
  Widget build(BuildContext context) => InkWell(onTap: () => context.go(path), borderRadius: BorderRadius.circular(12), child: Container(width: 130, padding: const EdgeInsets.all(14), decoration: BoxDecoration(border: Border.all(color: PgColors.border), borderRadius: BorderRadius.circular(12)), child: Column(children: [Icon(icon, color: PgColors.primary), const SizedBox(height: 8), Text(label, textAlign: TextAlign.center)])));
}

class RecordList extends StatelessWidget {
  const RecordList({required this.items, super.key}); final List items;
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const EmptyState(icon: Icons.inbox_outlined, title: 'No records yet', message: 'Create your first record to get started.');
    return ListView.separated(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: items.length, separatorBuilder: (_, __) => const Divider(), itemBuilder: (_, index) {
      final raw = items[index]; final map = raw is Map ? raw : {'value': raw};
      final title = map['facilityName'] ?? map['facility_name'] ?? map['fullName'] ?? map['full_name'] ?? map['name'] ?? map['title'] ?? 'Record ${index + 1}';
      final subtitle = map.entries.where((e) => !['facilityName','facility_name','fullName','full_name','name','title'].contains(e.key)).take(3).map((e) => '${e.key}: ${e.value}').join('  •  ');
      return ListTile(leading: const CircleAvatar(backgroundColor: PgColors.lavender, child: Icon(Icons.business_outlined, color: PgColors.primary)), title: Text('$title', style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(subtitle), trailing: const Icon(Icons.chevron_right));
    });
  }
}

class KeyValueSummary extends StatelessWidget {
  const KeyValueSummary({required this.values, super.key}); final Map<String, dynamic> values;
  @override
  Widget build(BuildContext context) => Wrap(spacing: 12, runSpacing: 12, children: values.entries.where((e) => e.value is! List && e.value is! Map).map((e) => MetricCard(label: _label(e.key), value: e.value, icon: Icons.analytics_outlined, color: PgColors.primary)).toList());
  String _label(String value) => value.replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(1)}').replaceAll('_', ' ').trim();
}

class ErrorState extends StatelessWidget {
  const ErrorState({required this.error, required this.retry, super.key}); final Object? error; final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.cloud_off, size: 48, color: PgColors.danger), const SizedBox(height: 12), const Text('Could not load data', style: TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 6), Text('$error', textAlign: TextAlign.center), const SizedBox(height: 12), OutlinedButton(onPressed: retry, child: const Text('Try again'))]));
}
class EmptyState extends StatelessWidget {
  const EmptyState({required this.icon, required this.title, required this.message, super.key}); final IconData icon; final String title; final String message;
  @override Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(30), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 52, color: PgColors.primary), const SizedBox(height: 12), Text(title, style: const TextStyle(fontWeight: FontWeight.w700)), Text(message, textAlign: TextAlign.center)])));
}
class _Panel extends StatelessWidget { const _Panel({required this.title, required this.child}); final String title; final Widget child; @override Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)), const SizedBox(height: 14), child]))); }
class _SettingsGroup extends StatelessWidget { const _SettingsGroup({required this.title, required this.children}); final String title; final List<Widget> children; @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(top: 18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: PgColors.primary, fontWeight: FontWeight.w700)), const SizedBox(height: 8), Card(child: Column(children: children))])); }
class _SettingTile extends StatelessWidget { const _SettingTile({required this.icon, required this.title, this.subtitle, this.onTap}); final IconData icon; final String title; final String? subtitle; final VoidCallback? onTap; @override Widget build(BuildContext context) => ListTile(leading: Icon(icon), title: Text(title), subtitle: subtitle == null ? null : Text(subtitle!), trailing: onTap == null ? null : const Icon(Icons.chevron_right), onTap: onTap); }

class _TrendPainter extends CustomPainter { const _TrendPainter(); @override void paint(Canvas canvas, Size size) { final p = Paint()..color = PgColors.primary..strokeWidth = 3..style = PaintingStyle.stroke; final path = Path()..moveTo(0,size.height*.8)..lineTo(size.width*.2,size.height*.6)..lineTo(size.width*.38,size.height*.7)..lineTo(size.width*.58,size.height*.4)..lineTo(size.width*.75,size.height*.5)..lineTo(size.width,size.height*.15); canvas.drawPath(path,p); } @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false; }
class _BarPainter extends CustomPainter { const _BarPainter(); @override void paint(Canvas canvas, Size size) { final p=Paint()..color=PgColors.primary.withValues(alpha:.75); const count=7; final gap=size.width/(count*2); for(var i=0;i<count;i++){final h=size.height*(.25+(i%4)*.17); canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(gap+i*gap*2,size.height-h,gap,h),const Radius.circular(6)),p);} } @override bool shouldRepaint(covariant CustomPainter oldDelegate)=>false; }
