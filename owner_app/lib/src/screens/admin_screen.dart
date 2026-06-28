import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme/app_theme.dart';
import '../utils/validators.dart';
import '../widgets/animations.dart';
import '../widgets/error_retry_view.dart';

// ─── Shell ────────────────────────────────────────────────────────────────────

class SuperAdminScreen extends StatefulWidget {
  const SuperAdminScreen({super.key});
  @override
  State<SuperAdminScreen> createState() => _SuperAdminScreenState();
}

class _SuperAdminScreenState extends State<SuperAdminScreen> {
  int _sel = 0;

  static const _nav = [
    (Icons.dashboard_outlined,   Icons.dashboard,    'Dashboard'),
    (Icons.business_outlined,    Icons.business,     'Organizations'),
    (Icons.upload_file_outlined, Icons.upload_file,  'Data Upload'),
    (Icons.people_outline,       Icons.people,       'Users'),
    (Icons.sell_outlined,        Icons.sell,         'Plans'),
    (Icons.bar_chart_outlined,   Icons.bar_chart,    'Reports'),
    (Icons.history_outlined,     Icons.history,      'Audit Logs'),
    (Icons.settings_outlined,    Icons.settings,     'System Settings'),
  ];

  Widget get _body => switch (_sel) {
    0 => const _AdminDashboard(),
    1 => const _AdminOrganizations(),
    2 => const _AdminDataUpload(),
    3 => const _AdminUsers(),
    4 => const _AdminPlans(),
    5 => const _AdminReports(),
    6 => const _AdminAuditLogs(),
    7 => const _AdminSettings(),
    _ => const SizedBox.shrink(),
  };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final sidebar = _Sidebar(sel: _sel, nav: _nav, onSel: (i) {
      setState(() => _sel = i);
      if (!wide) Navigator.pop(context);
    });
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5FA),
      appBar: wide ? null : AppBar(
        title: const Text('Admin Console', style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.white,
        foregroundColor: PgColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1)),
      ),
      drawer: wide ? null : Drawer(child: sidebar),
      body: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              sidebar,
              Expanded(child: _body),
            ])
          : _body,
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.sel, required this.nav, required this.onSel});
  final int sel;
  final List<(IconData, IconData, String)> nav;
  final ValueChanged<int> onSel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: PgColors.border)),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
          child: Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(color: PgColors.primary, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.admin_panel_settings_outlined, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Admin Console', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: PgColors.ink)),
              Text('Super Admin', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ]),
          ]),
        ),
        const Divider(height: 1),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: nav.length,
            itemBuilder: (_, i) {
              final (unsel, selIcon, label) = nav[i];
              final active = sel == i;
              return Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onSel(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: active ? PgColors.lavender : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      Icon(active ? selIcon : unsel, size: 18,
                          color: active ? PgColors.primary : const Color(0xFF9CA3AF)),
                      const SizedBox(width: 10),
                      Text(label, style: TextStyle(
                        fontSize: 13,
                        fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                        color: active ? PgColors.primary : PgColors.ink,
                      )),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(color: PgColors.lavender, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.person, size: 16, color: PgColors.primary),
            ),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Admin', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: PgColors.ink)),
              Text('SUPER_ADMIN', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
            ])),
            IconButton(
              icon: const Icon(Icons.logout, size: 18, color: PgColors.danger),
              tooltip: 'Logout',
              onPressed: () async {
                await context.read<AppState>().logout();
              },
            ),
          ]),
        ),
      ]),
    );
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.title, required this.subtitle, this.action});
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: PgColors.ink)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
        ])),
        if (action != null) action!,
      ]),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
      Container(
        width: 40, height: 40,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 20),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: PgColors.ink)),
      ])),
    ])),
  );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final active = status == 'ACTIVE';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: active ? PgColors.success.withValues(alpha: 0.1) : Colors.grey[100],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? PgColors.success.withValues(alpha: 0.3) : Colors.grey[300]!),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6,
          decoration: BoxDecoration(color: active ? PgColors.success : Colors.grey[400], shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
            color: active ? PgColors.success : Colors.grey[600])),
      ]),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 56, height: 56,
        decoration: BoxDecoration(color: PgColors.lavender, borderRadius: BorderRadius.circular(16)),
        child: Icon(icon, color: PgColors.primary, size: 28),
      ),
      const SizedBox(height: 12),
      Text(message, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)),
    ]),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 130, child: Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)))),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: PgColors.ink))),
    ]),
  );
}

// ─── Dashboard ────────────────────────────────────────────────────────────────

class _AdminDashboard extends StatefulWidget {
  const _AdminDashboard();
  @override
  State<_AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<_AdminDashboard> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  void _fetch() => setState(() {
    _future = context.read<AppState>().apiClient.get('/super-admin/dashboard');
  });

  void _showBroadcastDialog() {
    showDialog(context: context, builder: (_) => _BroadcastDialog(
      apiClient: context.read<AppState>().apiClient,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _PageHeader(
        title: 'Dashboard',
        subtitle: 'Platform-wide overview',
        action: FilledButton.icon(
          onPressed: _showBroadcastDialog,
          icon: const Icon(Icons.campaign_outlined, size: 16),
          label: const Text('Send Announcement', style: TextStyle(fontSize: 13)),
          style: FilledButton.styleFrom(
            backgroundColor: PgColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
      ),
      const Divider(height: 1),
      Expanded(child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return ErrorRetryView(error: snap.error!, onRetry: _fetch);
          final d = snap.data ?? {};
          final activity = (d['recentActivity'] as List? ?? []).cast<Map<String, dynamic>>();
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: FadeSlideIn(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              LayoutBuilder(builder: (_, constraints) {
                final cols = constraints.maxWidth > 800 ? 4 : 2;
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: cols,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.8,
                  children: [
                    _MetricCard('Total Orgs',  '${d['totalOrganizations'] ?? 0}',  Icons.business,     PgColors.primary),
                    _MetricCard('Active Orgs', '${d['activeOrganizations'] ?? 0}', Icons.check_circle, PgColors.success),
                    _MetricCard('Properties',  '${d['totalProperties'] ?? 0}',     Icons.apartment,    PgColors.warning),
                    _MetricCard('Tenants',     '${d['totalTenants'] ?? 0}',        Icons.people,       const Color(0xFF2563EB)),
                  ],
                );
              }),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(color: PgColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.currency_rupee, color: PgColors.success, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Monthly Revenue', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                      Text('₹${d['monthlyRevenue'] ?? 0}',
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: PgColors.success)),
                    ]),
                  ]),
                ),
              ),
              const SizedBox(height: 24),
              const Text('Recent Activity', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: PgColors.ink)),
              const SizedBox(height: 10),
              if (activity.isEmpty)
                _EmptyState(icon: Icons.history, message: 'No recent activity')
              else
                Card(
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: activity.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
                    itemBuilder: (_, i) {
                      final a = activity[i];
                      return ListTile(
                        dense: true,
                        leading: Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(color: PgColors.lavender, borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.bolt, size: 16, color: PgColors.primary),
                        ),
                        title: Text('${a['action']} — ${a['entity_type']}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        subtitle: Text('${a['created_at'] ?? ''}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                      );
                    },
                  ),
                ),
            ])),
          );
        },
      )),
    ]);
  }
}

// ─── Broadcast Dialog ─────────────────────────────────────────────────────────

class _BroadcastDialog extends StatefulWidget {
  const _BroadcastDialog({required this.apiClient});
  final dynamic apiClient;

  @override
  State<_BroadcastDialog> createState() => _BroadcastDialogState();
}

class _BroadcastDialogState extends State<_BroadcastDialog> {
  final _form = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  bool _important = false;
  bool _sending = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      final res = await widget.apiClient.post('/super-admin/broadcast', {
        'title': _titleCtrl.text.trim(),
        'message': _msgCtrl.text.trim(),
        'important': _important,
      });
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Announcement sent to ${res['sentToOrgs'] ?? 0} organization(s)'),
          backgroundColor: PgColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: PgColors.danger),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: PgColors.lavender, borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.campaign_outlined, color: PgColors.primary, size: 20),
        ),
        const SizedBox(width: 12),
        const Text('Send Announcement', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ]),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(
              'This message will appear in the notification bar of all PG owners.',
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _titleCtrl,
              decoration: _inputDeco('Title', 'e.g. Platform maintenance scheduled'),
              maxLength: 160,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Title is required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _msgCtrl,
              decoration: _inputDeco('Message', 'Enter your announcement message…'),
              maxLines: 4,
              maxLength: 500,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Message is required' : null,
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              value: _important,
              onChanged: (v) => setState(() => _important = v ?? false),
              title: const Text('Mark as important', style: TextStyle(fontSize: 13)),
              subtitle: const Text('Highlights the notification in the owner app', style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
              activeColor: PgColors.primary,
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _sending ? null : _send,
          icon: _sending
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send, size: 16),
          label: Text(_sending ? 'Sending…' : 'Send to All Owners'),
          style: FilledButton.styleFrom(backgroundColor: PgColors.primary),
        ),
      ],
    );
  }

  InputDecoration _inputDeco(String label, String hint) => InputDecoration(
    labelText: label,
    hintText: hint,
    isDense: true,
    filled: true,
    fillColor: const Color(0xFFF9F9FD),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: PgColors.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: PgColors.border)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: PgColors.primary)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: PgColors.danger)),
  );
}

// ─── Organizations ────────────────────────────────────────────────────────────

class _AdminOrganizations extends StatefulWidget {
  const _AdminOrganizations();
  @override
  State<_AdminOrganizations> createState() => _AdminOrgsState();
}

class _AdminOrgsState extends State<_AdminOrganizations> {
  List<Map<String, dynamic>> _orgs = [];
  bool _loading = true;
  Object? _error;
  String _query = '';
  String _filter = 'ALL';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await context.read<AppState>().apiClient.get('/super-admin/organizations');
      setState(() { _orgs = (data['items'] as List? ?? []).cast<Map<String, dynamic>>();  _loading = false; });
    } catch (e) {
      setState(() { _error = e; _loading = false; });
    }
  }

  List<Map<String, dynamic>> get _filtered => _orgs.where((o) {
    final matchFilter = _filter == 'ALL' || o['status'] == _filter;
    final matchQuery = _query.isEmpty || '${o['facility_name']}'.toLowerCase().contains(_query.toLowerCase());
    return matchFilter && matchQuery;
  }).toList();

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _PageHeader(
        title: 'Organizations',
        subtitle: '${_orgs.length} total',
        action: Row(mainAxisSize: MainAxisSize.min, children: [
          FilledButton.icon(
            onPressed: _showCreateOrgDialog,
            icon: const Icon(Icons.add_business_outlined, size: 16),
            label: const Text('New Organization', style: TextStyle(fontSize: 13)),
            style: FilledButton.styleFrom(
              backgroundColor: PgColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(icon: const Icon(Icons.refresh, size: 20), tooltip: 'Refresh', onPressed: _load),
        ]),
      ),
      const Divider(height: 1),
      if (_loading) const Expanded(child: Center(child: CircularProgressIndicator()))
      else if (_error != null) Expanded(child: ErrorRetryView(error: _error!, onRetry: _load))
      else ...[
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 14),
          child: Row(children: [
            Expanded(child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: 'Search organizations…',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                filled: true, fillColor: const Color(0xFFF9F9FD),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: PgColors.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: PgColors.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: PgColors.primary)),
              ),
              onChanged: (v) => setState(() => _query = v),
            )),
            const SizedBox(width: 12),
            for (final f in ['ALL', 'ACTIVE', 'INACTIVE'])
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: ChoiceChip(
                  label: Text(f, style: TextStyle(fontSize: 12, color: _filter == f ? Colors.white : PgColors.ink)),
                  selected: _filter == f,
                  selectedColor: PgColors.primary,
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: PgColors.border),
                  onSelected: (_) => setState(() => _filter = f),
                ),
              ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(child: _filtered.isEmpty
            ? _EmptyState(icon: Icons.business_center, message: 'No organizations match your filters')
            : ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: _filtered.length,
                itemBuilder: (_, i) => FadeSlideIn(
                  delay: Duration(milliseconds: 40 * (i.clamp(0, 8))),
                  child: _OrgCard(org: _filtered[i], onTap: () => _showDetail(_filtered[i])),
                ),
              )),
      ],
    ]);
  }

  void _showDetail(Map<String, dynamic> org) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _OrgDetailSheet(org: org, onStatusChanged: _load),
    );
  }

  void _showCreateOrgDialog() {
    showDialog(context: context, builder: (_) => _CreateOrgDialog(
      apiClient: context.read<AppState>().apiClient,
      onCreated: _load,
    ));
  }
}

// ─── Create Organization Dialog ───────────────────────────────────────────────

class _CreateOrgDialog extends StatefulWidget {
  const _CreateOrgDialog({required this.apiClient, required this.onCreated});
  final dynamic apiClient;
  final VoidCallback onCreated;

  @override
  State<_CreateOrgDialog> createState() => _CreateOrgDialogState();
}

class _CreateOrgDialogState extends State<_CreateOrgDialog> {
  final _form = GlobalKey<FormState>();
  final _orgName = TextEditingController();
  final _fullName = TextEditingController();
  final _mobile = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _saving = false;

  @override
  void dispose() {
    _orgName.dispose();
    _fullName.dispose();
    _mobile.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final res = await widget.apiClient.post('/super-admin/organizations', {
        'organizationName': _orgName.text.trim(),
        'fullName': _fullName.text.trim(),
        'mobileNumber': _mobile.text.trim(),
        'username': _username.text.trim(),
        'password': _password.text,
      });
      if (!mounted) return;
      Navigator.pop(context);
      widget.onCreated();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Organization "${res['organizationName']}" created with owner @${res['ownerUsername']}'),
          backgroundColor: PgColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: PgColors.danger),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: PgColors.lavender, borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.add_business_outlined, color: PgColors.primary, size: 20),
        ),
        const SizedBox(width: 12),
        const Text('New Organization', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ]),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(
                'Creates the organization and its owner login. The owner can then sign in with these credentials.',
                style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _orgName,
                decoration: _deco('Organization Name', Icons.business_outlined),
                textInputAction: TextInputAction.next,
                validator: (v) => Validators.minLength(v, 2, label: 'Organization name'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _fullName,
                decoration: _deco('Owner Full Name', Icons.person_outline),
                textInputAction: TextInputAction.next,
                validator: (v) => Validators.minLength(v, 2, label: 'Full name'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _mobile,
                decoration: _deco('Owner Mobile Number', Icons.phone_outlined),
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                textInputAction: TextInputAction.next,
                validator: Validators.mobile,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _username,
                decoration: _deco('Username', Icons.alternate_email),
                textInputAction: TextInputAction.next,
                validator: Validators.username,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                decoration: _deco('Password', Icons.lock_outline).copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: Validators.password,
              ),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check, size: 16),
          label: Text(_saving ? 'Creating…' : 'Create Organization'),
          style: FilledButton.styleFrom(backgroundColor: PgColors.primary),
        ),
      ],
    );
  }

  InputDecoration _deco(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, size: 20),
    isDense: true,
    filled: true,
    fillColor: const Color(0xFFF9F9FD),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: PgColors.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: PgColors.border)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: PgColors.primary)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: PgColors.danger)),
  );
}

class _OrgCard extends StatelessWidget {
  const _OrgCard({required this.org, required this.onTap});
  final Map<String, dynamic> org;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = '${org['facility_name'] ?? 'Unnamed'}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(color: PgColors.lavender, borderRadius: BorderRadius.circular(10)),
            child: Center(child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(color: PgColors.primary, fontWeight: FontWeight.w700, fontSize: 17),
            )),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: PgColors.ink)),
            const SizedBox(height: 3),
            Text('Created: ${org['created_at'] ?? '—'}', style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
          ])),
          _StatusBadge('${org['status'] ?? 'ACTIVE'}'),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF), size: 18),
        ])),
      ),
    );
  }
}

class _OrgDetailSheet extends StatefulWidget {
  const _OrgDetailSheet({required this.org, required this.onStatusChanged});
  final Map<String, dynamic> org;
  final VoidCallback onStatusChanged;
  @override
  State<_OrgDetailSheet> createState() => _OrgDetailSheetState();
}

class _OrgDetailSheetState extends State<_OrgDetailSheet> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  Map<String, dynamic>? _detail;
  List<Map<String, dynamic>> _tenants = [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() { super.initState(); _tabs = TabController(length: 2, vsync: this); _load(); }
  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _load() async {
    final orgId = widget.org['organization_id'];
    setState(() { _loading = true; _error = null; });
    try {
      final detail = await context.read<AppState>().apiClient.get('/super-admin/organizations/$orgId');
      final tenants = await context.read<AppState>().apiClient.get('/super-admin/organizations/$orgId/tenants');
      setState(() {
        _detail = detail;
        _tenants = (tenants['items'] as List? ?? []).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e; _loading = false; });
    }
  }

  Future<void> _toggleStatus() async {
    final orgId = widget.org['organization_id'];
    final current = '${_detail?['status'] ?? widget.org['status'] ?? 'ACTIVE'}';
    final next = current == 'ACTIVE' ? 'INACTIVE' : 'ACTIVE';
    try {
      await context.read<AppState>().apiClient.patch('/super-admin/organizations/$orgId/status', {'status': next});
      widget.onStatusChanged();
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = '${widget.org['facility_name'] ?? 'Organization'}';
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, ctrl) => Column(children: [
        const SizedBox(height: 12),
        Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: PgColors.lavender, borderRadius: BorderRadius.circular(12)),
              child: Center(child: Text(name[0].toUpperCase(),
                  style: const TextStyle(color: PgColors.primary, fontWeight: FontWeight.w800, fontSize: 18))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: PgColors.ink))),
            if (_detail != null) _StatusBadge('${_detail!['status'] ?? 'ACTIVE'}'),
          ]),
        ),
        const SizedBox(height: 16),
        if (_loading) const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_error != null) Expanded(child: Center(child: Text('Error: $_error', style: const TextStyle(color: PgColors.danger))))
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(children: [
              _StatPill('Properties', '${_detail!['propertyCount'] ?? 0}'),
              const SizedBox(width: 8),
              _StatPill('Tenants', '${_detail!['tenantCount'] ?? 0}'),
              const SizedBox(width: 8),
              _StatPill('Beds', '${_detail!['occupiedBeds'] ?? 0}/${_detail!['totalBeds'] ?? 0}'),
            ]),
          ),
          const SizedBox(height: 12),
          TabBar(
            controller: _tabs,
            labelColor: PgColors.primary,
            unselectedLabelColor: const Color(0xFF6B7280),
            indicatorColor: PgColors.primary,
            tabs: const [Tab(text: 'Overview'), Tab(text: 'Tenants')],
          ),
          const Divider(height: 1),
          Expanded(child: TabBarView(controller: _tabs, children: [
            ListView(controller: ctrl, padding: const EdgeInsets.all(24), children: [
              _InfoRow('Status', '${_detail!['status'] ?? '—'}'),
              _InfoRow('Org ID', '${_detail!['organization_id']}'),
              _InfoRow('Created', '${_detail!['created_at'] ?? '—'}'),
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _detail!['status'] == 'ACTIVE' ? PgColors.danger : PgColors.success,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _toggleStatus,
                  child: Text(_detail!['status'] == 'ACTIVE' ? 'Deactivate Organization' : 'Activate Organization'),
                ),
              ),
            ]),
            _tenants.isEmpty
                ? _EmptyState(icon: Icons.people_outline, message: 'No active tenants')
                : ListView.separated(
                    controller: ctrl,
                    itemCount: _tenants.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
                    itemBuilder: (_, i) {
                      final t = _tenants[i];
                      return ListTile(
                        leading: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(color: PgColors.lavender, borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.person, size: 18, color: PgColors.primary),
                        ),
                        title: Text('${t['full_name'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Text('${t['mobile_number'] ?? '—'}  •  Bed: ${t['bed_name'] ?? 'Unassigned'}',
                            style: const TextStyle(fontSize: 12)),
                      );
                    }),
          ])),
        ],
      ]),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: PgColors.lavender,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: PgColors.primary)),
      Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280))),
    ]),
  );
}

// ─── Data Upload ──────────────────────────────────────────────────────────────

class _AdminDataUpload extends StatefulWidget {
  const _AdminDataUpload();
  @override
  State<_AdminDataUpload> createState() => _AdminDataUploadState();
}

class _AdminDataUploadState extends State<_AdminDataUpload> {
  int _step = 0;
  List<Map<String, dynamic>> _orgs = [];
  Map<String, dynamic>? _selectedOrg;
  String _uploadType = 'FACILITIES';
  XFile? _pickedFile;
  Map<String, dynamic>? _result;
  bool _uploading = false;
  Object? _uploadError;

  static const _facilityCols = [
    'property_name', 'floor_name', 'floor_number', 'room_name',
    'room_number', 'sharing_type', 'monthly_rent', 'bed_name',
  ];
  static const _tenantCols = [
    'full_name', 'mobile_number', 'email', 'gender', 'date_of_birth',
    'aadhaar_number', 'occupation', 'permanent_address',
    'emergency_contact_name', 'emergency_contact_mobile', 'emergency_contact_relation',
    'property_name', 'floor_name', 'room_name', 'bed_name',
    'move_in_date', 'monthly_rent', 'security_deposit',
  ];

  @override
  void initState() { super.initState(); _loadOrgs(); }

  Future<void> _loadOrgs() async {
    try {
      final data = await context.read<AppState>().apiClient.get('/super-admin/organizations');
      setState(() { _orgs = (data['items'] as List? ?? []).cast<Map<String, dynamic>>(); });
    } catch (_) {}
  }

  List<String> get _cols => _uploadType == 'FACILITIES' ? _facilityCols : _tenantCols;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const _PageHeader(title: 'Data Upload', subtitle: 'Bulk import facilities and tenants via CSV'),
      const Divider(height: 1),
      Expanded(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: _result != null
            ? FadeSlideIn(child: _UploadResultView(result: _result!, onReset: _reset))
            : FadeSlideIn(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _StepIndicator(current: _step),
                const SizedBox(height: 24),
                if (_step == 0) _buildStep1(),
                if (_step == 1) _buildStep2(),
                if (_step == 2) _buildStep3(),
              ])),
      )),
    ]);
  }

  Widget _buildStep1() => Card(
    child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Select Organization', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: PgColors.ink)),
      const SizedBox(height: 4),
      const Text('Choose which organization to upload data for', style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
      const SizedBox(height: 16),
      DropdownButtonFormField<Map<String, dynamic>>(
        value: _selectedOrg,
        hint: const Text('Choose an organization'),
        decoration: const InputDecoration(isDense: true),
        items: _orgs.map((o) => DropdownMenuItem(value: o, child: Text('${o['facility_name']}'))).toList(),
        onChanged: (v) => setState(() => _selectedOrg = v),
      ),
      const SizedBox(height: 20),
      Align(alignment: Alignment.centerRight, child: FilledButton(
        onPressed: _selectedOrg == null ? null : () => setState(() => _step = 1),
        child: const Text('Continue'),
      )),
    ])),
  );

  Widget _buildStep2() => Card(
    child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Choose Upload Type', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: PgColors.ink)),
      const SizedBox(height: 4),
      const Text('Select what kind of data you want to import', style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
      const SizedBox(height: 16),
      _UploadTypeCard(
        title: 'Facilities',
        subtitle: 'Floors, rooms, and beds under a property',
        icon: Icons.apartment,
        selected: _uploadType == 'FACILITIES',
        onTap: () => setState(() => _uploadType = 'FACILITIES'),
      ),
      const SizedBox(height: 8),
      _UploadTypeCard(
        title: 'Tenants',
        subtitle: 'Create tenants and optionally assign to beds',
        icon: Icons.people,
        selected: _uploadType == 'TENANTS',
        onTap: () => setState(() => _uploadType = 'TENANTS'),
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF9F9FD),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: PgColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.table_chart_outlined, size: 16, color: Color(0xFF6B7280)),
            const SizedBox(width: 6),
            const Text('CSV Columns', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.copy, size: 13),
              label: const Text('Copy Header', style: TextStyle(fontSize: 12)),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _cols.join(',')));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Header copied to clipboard'), duration: Duration(seconds: 2)),
                );
              },
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6, runSpacing: 6,
            children: _cols.map((c) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: PgColors.lavender,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(c, style: const TextStyle(fontSize: 11, color: PgColors.primary, fontFamily: 'monospace')),
            )).toList(),
          ),
        ]),
      ),
      const SizedBox(height: 20),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        OutlinedButton(onPressed: () => setState(() => _step = 0), child: const Text('Back')),
        FilledButton(onPressed: () => setState(() => _step = 2), child: const Text('Continue')),
      ]),
    ])),
  );

  Widget _buildStep3() => Card(
    child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Upload CSV File', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: PgColors.ink)),
      const SizedBox(height: 4),
      Text('Uploading ${_uploadType.toLowerCase()} for: ${_selectedOrg?['facility_name'] ?? '—'}',
          style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
      const SizedBox(height: 20),
      InkWell(
        onTap: _pickFile,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 28),
          decoration: BoxDecoration(
            color: const Color(0xFFF9F9FD),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _pickedFile != null ? PgColors.primary : PgColors.border,
              width: _pickedFile != null ? 1.5 : 1,
              style: BorderStyle.solid,
            ),
          ),
          child: Column(children: [
            Icon(
              _pickedFile != null ? Icons.check_circle : Icons.upload_file_outlined,
              size: 36,
              color: _pickedFile != null ? PgColors.success : const Color(0xFF9CA3AF),
            ),
            const SizedBox(height: 8),
            Text(
              _pickedFile?.name ?? 'Tap to browse CSV file',
              style: TextStyle(
                fontWeight: _pickedFile != null ? FontWeight.w600 : FontWeight.normal,
                color: _pickedFile != null ? PgColors.ink : const Color(0xFF9CA3AF),
              ),
            ),
            if (_pickedFile == null)
              const Text('.csv files only', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
          ]),
        ),
      ),
      if (_uploadError != null) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: PgColors.danger.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            const Icon(Icons.error_outline, size: 16, color: PgColors.danger),
            const SizedBox(width: 6),
            Expanded(child: Text('$_uploadError', style: const TextStyle(color: PgColors.danger, fontSize: 12))),
          ]),
        ),
      ],
      const SizedBox(height: 20),
      if (_uploading)
        const LinearProgressIndicator()
      else
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          OutlinedButton(onPressed: () => setState(() => _step = 1), child: const Text('Back')),
          FilledButton.icon(
            icon: const Icon(Icons.upload, size: 18),
            label: const Text('Upload'),
            onPressed: _pickedFile == null ? null : _upload,
          ),
        ]),
    ])),
  );

  Future<void> _pickFile() async {
    const typeGroup = XTypeGroup(label: 'CSV', extensions: ['csv']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file != null) setState(() { _pickedFile = file; _uploadError = null; });
  }

  Future<void> _upload() async {
    if (_pickedFile == null || _selectedOrg == null) return;
    setState(() { _uploading = true; _uploadError = null; });
    try {
      final bytes = await _pickedFile!.readAsBytes();
      final orgId = _selectedOrg!['organization_id'];
      final type = _uploadType.toLowerCase();
      final data = await context.read<AppState>().apiClient.postFile(
        '/super-admin/upload/$type/$orgId', bytes, _pickedFile!.name);
      setState(() { _result = data; _uploading = false; });
    } catch (e) {
      setState(() { _uploadError = e; _uploading = false; });
    }
  }

  void _reset() => setState(() {
    _step = 0; _selectedOrg = null; _pickedFile = null;
    _result = null; _uploadError = null; _uploading = false;
  });
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.current});
  final int current;
  static const _steps = ['Select Org', 'Choose Type', 'Upload File'];

  @override
  Widget build(BuildContext context) => Row(
    children: List.generate(_steps.length * 2 - 1, (i) {
      if (i.isOdd) {
        return Expanded(child: Container(height: 2,
            color: i ~/ 2 < current ? PgColors.primary : PgColors.border));
      }
      final step = i ~/ 2;
      final done = step < current;
      final active = step == current;
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: done ? PgColors.success : active ? PgColors.primary : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: done ? PgColors.success : active ? PgColors.primary : PgColors.border,
              width: 2,
            ),
          ),
          child: Center(child: done
              ? const Icon(Icons.check, size: 14, color: Colors.white)
              : Text('${step + 1}', style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: active ? Colors.white : const Color(0xFF9CA3AF)))),
        ),
        const SizedBox(height: 4),
        Text(_steps[step], style: TextStyle(
            fontSize: 11,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            color: active ? PgColors.primary : const Color(0xFF9CA3AF))),
      ]);
    }),
  );
}

class _UploadTypeCard extends StatelessWidget {
  const _UploadTypeCard({required this.title, required this.subtitle, required this.icon,
      required this.selected, required this.onTap});
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(10),
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: selected ? PgColors.primary : PgColors.border, width: selected ? 1.5 : 1),
        color: selected ? PgColors.lavender : Colors.white,
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: selected ? PgColors.primary : const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: selected ? Colors.white : const Color(0xFF6B7280)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14,
              color: selected ? PgColors.primary : PgColors.ink)),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
        ])),
        if (selected) const Icon(Icons.check_circle, color: PgColors.primary, size: 18),
      ]),
    ),
  );
}

class _UploadResultView extends StatelessWidget {
  const _UploadResultView({required this.result, required this.onReset});
  final Map<String, dynamic> result;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final errors = (result['errors'] as List? ?? []).cast<Map<String, dynamic>>();
    final failed = result['failed'] as int? ?? 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Card(
        child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: failed == 0 ? PgColors.success.withValues(alpha: 0.1) : PgColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(failed == 0 ? Icons.check_circle : Icons.warning_amber_rounded,
                  color: failed == 0 ? PgColors.success : PgColors.warning, size: 24),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Upload Complete', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              Text(failed == 0 ? 'All rows processed successfully' : '$failed row(s) had errors',
                  style: TextStyle(fontSize: 13, color: failed == 0 ? PgColors.success : PgColors.warning)),
            ]),
          ]),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _ResultStat('Total', '${result['totalRows'] ?? 0}', PgColors.primary)),
            Expanded(child: _ResultStat('Created', '${result['created'] ?? 0}', PgColors.success)),
            Expanded(child: _ResultStat('Updated', '${result['updated'] ?? 0}', PgColors.warning)),
            Expanded(child: _ResultStat('Failed', '${result['failed'] ?? 0}', PgColors.danger)),
          ]),
        ])),
      ),
      if (errors.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Row Errors (${errors.length})',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: PgColors.ink)),
        const SizedBox(height: 8),
        Card(
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: errors.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final e = errors[i];
              return ListTile(
                dense: true,
                leading: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: PgColors.danger.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                  child: Center(child: Text('${e['row']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: PgColors.danger))),
                ),
                title: Text('[${e['column']}] ${e['message']}', style: const TextStyle(fontSize: 12)),
              );
            },
          ),
        ),
      ],
      const SizedBox(height: 20),
      OutlinedButton.icon(
        icon: const Icon(Icons.upload_file, size: 18),
        label: const Text('Upload Another File'),
        onPressed: onReset,
      ),
    ]);
  }
}

class _ResultStat extends StatelessWidget {
  const _ResultStat(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
    Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
  ]);
}

// ─── Users ────────────────────────────────────────────────────────────────────

class _AdminUsers extends StatefulWidget {
  const _AdminUsers();
  @override
  State<_AdminUsers> createState() => _AdminUsersState();
}

class _AdminUsersState extends State<_AdminUsers> {
  late Future<Map<String, dynamic>> _future;
  String _query = '';

  @override
  void initState() { super.initState(); _fetch(); }

  void _fetch() => setState(() {
    _future = context.read<AppState>().apiClient.get('/super-admin/users');
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const _PageHeader(title: 'Users', subtitle: 'All registered users across organizations'),
      const Divider(height: 1),
      Expanded(child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return ErrorRetryView(error: snap.error!, onRetry: _fetch);
          final users = (snap.data?['items'] as List? ?? []).cast<Map<String, dynamic>>();
          final filtered = users.where((u) {
            final str = '${u['full_name'] ?? ''} ${u['username'] ?? ''}'.toLowerCase();
            return _query.isEmpty || str.contains(_query.toLowerCase());
          }).toList();
          return Column(children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 14),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: 'Search users…',
                  isDense: true,
                  filled: true, fillColor: const Color(0xFFF9F9FD),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: PgColors.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: PgColors.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: PgColors.primary)),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const Divider(height: 1),
            Expanded(child: filtered.isEmpty
                ? _EmptyState(icon: Icons.people_outline, message: 'No users found')
                : ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final u = filtered[i];
                      final role = '${u['role_type_id'] ?? ''}';
                      final roleColor = role == 'SUPER_ADMIN' ? PgColors.danger
                          : role == 'OWNER' ? PgColors.primary
                          : PgColors.warning;
                      return FadeSlideIn(
                        delay: Duration(milliseconds: 40 * (i.clamp(0, 8))),
                        child: Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          leading: Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(color: PgColors.lavender, borderRadius: BorderRadius.circular(10)),
                            child: Center(child: Text(
                              '${u['full_name'] ?? u['username'] ?? '?'}'.isNotEmpty
                                  ? '${u['full_name'] ?? u['username']}'[0].toUpperCase() : '?',
                              style: const TextStyle(color: PgColors.primary, fontWeight: FontWeight.w700, fontSize: 15),
                            )),
                          ),
                          title: Text('${u['full_name'] ?? u['username'] ?? '—'}',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: Text('@${u['username']}  •  ${u['mobile_number'] ?? '—'}',
                              style: const TextStyle(fontSize: 12)),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: roleColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: roleColor.withValues(alpha: 0.2)),
                            ),
                            child: Text(role, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: roleColor)),
                          ),
                        ),
                      ));
                    },
                  )),
          ]);
        },
      )),
    ]);
  }
}

// ─── Plans ────────────────────────────────────────────────────────────────────

class _AdminPlans extends StatefulWidget {
  const _AdminPlans();
  @override
  State<_AdminPlans> createState() => _AdminPlansState();
}

class _AdminPlansState extends State<_AdminPlans> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() { super.initState(); _fetch(); }

  void _fetch() => setState(() {
    _future = context.read<AppState>().apiClient.get('/super-admin/plans');
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _PageHeader(
        title: 'Plans',
        subtitle: 'Subscription plans and pricing',
        action: FilledButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New Plan'),
          onPressed: _showCreateDialog,
        ),
      ),
      const Divider(height: 1),
      Expanded(child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return ErrorRetryView(error: snap.error!, onRetry: _fetch);
          final plans = (snap.data?['items'] as List? ?? []).cast<Map<String, dynamic>>();
          if (plans.isEmpty) return _EmptyState(icon: Icons.sell_outlined, message: 'No plans configured yet');
          return GridView.builder(
            padding: const EdgeInsets.all(20),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 260, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.1),
            itemCount: plans.length,
            itemBuilder: (_, i) => FadeSlideIn(
              delay: Duration(milliseconds: 40 * (i.clamp(0, 8))),
              child: _PlanCard(plan: plans[i]),
            ),
          );
        },
      )),
    ]);
  }

  void _showCreateDialog() {
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final limitCtrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('New Plan', style: TextStyle(fontWeight: FontWeight.w700)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: 'Plan Code', isDense: true)),
        const SizedBox(height: 12),
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Plan Name', isDense: true)),
        const SizedBox(height: 12),
        TextField(controller: priceCtrl, decoration: const InputDecoration(labelText: 'Monthly Price (₹)', isDense: true), keyboardType: TextInputType.number),
        const SizedBox(height: 12),
        TextField(controller: limitCtrl, decoration: const InputDecoration(labelText: 'Property Limit (optional)', isDense: true), keyboardType: TextInputType.number),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            try {
              await context.read<AppState>().apiClient.post('/super-admin/plans', {
                'planCode': codeCtrl.text.trim(),
                'name': nameCtrl.text.trim(),
                'priceMonthly': double.tryParse(priceCtrl.text) ?? 0,
                if (limitCtrl.text.isNotEmpty) 'propertyLimit': int.tryParse(limitCtrl.text),
              });
              if (ctx.mounted) Navigator.pop(ctx);
              _fetch();
            } catch (e) {
              if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$e')));
            }
          },
          child: const Text('Create'),
        ),
      ],
    ));
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan});
  final Map<String, dynamic> plan;

  @override
  Widget build(BuildContext context) {
    final active = plan['active'] == true;
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: PgColors.lavender, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.sell, size: 18, color: PgColors.primary),
          ),
          const Spacer(),
          _StatusBadge(active ? 'ACTIVE' : 'INACTIVE'),
        ]),
        const SizedBox(height: 12),
        Text('${plan['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: PgColors.ink)),
        const SizedBox(height: 4),
        Text('₹${plan['price_monthly'] ?? 0}/month',
            style: const TextStyle(color: PgColors.success, fontWeight: FontWeight.w800, fontSize: 18)),
        const Spacer(),
        Text(
          plan['property_limit'] != null ? 'Up to ${plan['property_limit']} properties' : 'Unlimited properties',
          style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
        ),
      ])),
    );
  }
}

// ─── Reports ──────────────────────────────────────────────────────────────────

class _AdminReports extends StatefulWidget {
  const _AdminReports();
  @override
  State<_AdminReports> createState() => _AdminReportsState();
}

class _AdminReportsState extends State<_AdminReports> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() { super.initState(); _fetch(); }
  void _fetch() => setState(() {
    _future = context.read<AppState>().apiClient.get('/super-admin/reports/revenue');
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const _PageHeader(title: 'Reports', subtitle: 'Revenue and usage statistics'),
      const Divider(height: 1),
      Expanded(child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return ErrorRetryView(error: snap.error!, onRetry: _fetch);
          final rows = (snap.data?['items'] as List? ?? []).cast<Map<String, dynamic>>();
          if (rows.isEmpty) return _EmptyState(icon: Icons.bar_chart, message: 'No revenue data yet');
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: FadeSlideIn(child: Card(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(const Color(0xFFF9F9FD)),
                  columns: const [
                    DataColumn(label: Text('Period', style: TextStyle(fontWeight: FontWeight.w600))),
                    DataColumn(label: Text('Org ID', style: TextStyle(fontWeight: FontWeight.w600))),
                    DataColumn(label: Text('Amount (₹)', style: TextStyle(fontWeight: FontWeight.w600))),
                  ],
                  rows: rows.map((r) => DataRow(cells: [
                    DataCell(Text('${r['period'] ?? '—'}')),
                    DataCell(Text('${r['organization_id'] ?? '—'}')),
                    DataCell(Text('${r['amount'] ?? 0}',
                        style: const TextStyle(fontWeight: FontWeight.w600, color: PgColors.success))),
                  ])).toList(),
                ),
              ),
            )),
          );
        },
      )),
    ]);
  }
}

// ─── Audit Logs ───────────────────────────────────────────────────────────────

class _AdminAuditLogs extends StatefulWidget {
  const _AdminAuditLogs();
  @override
  State<_AdminAuditLogs> createState() => _AdminAuditLogsState();
}

class _AdminAuditLogsState extends State<_AdminAuditLogs> {
  late Future<Map<String, dynamic>> _future;
  String _query = '';

  @override
  void initState() { super.initState(); _fetch(); }
  void _fetch() => setState(() {
    _future = context.read<AppState>().apiClient.get('/super-admin/audit-logs?limit=200');
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const _PageHeader(title: 'Audit Logs', subtitle: 'System activity and event history'),
      const Divider(height: 1),
      Expanded(child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return ErrorRetryView(error: snap.error!, onRetry: _fetch);
          final logs = (snap.data?['items'] as List? ?? []).cast<Map<String, dynamic>>();
          final filtered = logs.where((l) =>
              _query.isEmpty || '${l['action']} ${l['entity_type']}'.toLowerCase().contains(_query.toLowerCase())).toList();
          return Column(children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 14),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: 'Filter by action or entity…',
                  isDense: true,
                  filled: true, fillColor: const Color(0xFFF9F9FD),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: PgColors.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: PgColors.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: PgColors.primary)),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const Divider(height: 1),
            Expanded(child: filtered.isEmpty
                ? _EmptyState(icon: Icons.history, message: 'No audit logs found')
                : ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final l = filtered[i];
                      final action = '${l['action'] ?? ''}';
                      final isLogin = action.contains('LOGIN');
                      final isDelete = action.contains('DELETE') || action.contains('DEACTIVAT');
                      final iconColor = isDelete ? PgColors.danger : isLogin ? PgColors.success : PgColors.primary;
                      final icon = isDelete ? Icons.delete_outline : isLogin ? Icons.login : Icons.edit_outlined;
                      return FadeSlideIn(
                        delay: Duration(milliseconds: 40 * (i.clamp(0, 8))),
                        child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Column(children: [
                            Container(
                              width: 34, height: 34,
                              decoration: BoxDecoration(
                                color: iconColor.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: iconColor.withValues(alpha: 0.15)),
                              ),
                              child: Icon(icon, size: 16, color: iconColor),
                            ),
                            if (i < filtered.length - 1)
                              Container(width: 1, height: 18, color: PgColors.border),
                          ]),
                          const SizedBox(width: 10),
                          Expanded(child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: PgColors.border),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(action, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: PgColors.ink)),
                              const SizedBox(height: 3),
                              Text('${l['entity_type']} #${l['entity_id']}  •  User ${l['user_login_id']}',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                              const SizedBox(height: 2),
                              Text('${l['created_at'] ?? ''}',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                            ]),
                          )),
                        ]),
                      ));
                    },
                  )),
          ]);
        },
      )),
    ]);
  }
}

// ─── System Settings ──────────────────────────────────────────────────────────

class _AdminSettings extends StatefulWidget {
  const _AdminSettings();
  @override
  State<_AdminSettings> createState() => _AdminSettingsState();
}

class _AdminSettingsState extends State<_AdminSettings> {
  List<Map<String, dynamic>> _settings = [];
  final Map<String, TextEditingController> _ctrls = {};
  bool _loading = true;
  bool _saving = false;
  Object? _error;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { for (final c in _ctrls.values) c.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await context.read<AppState>().apiClient.get('/super-admin/system-settings');
      final items = (data['items'] as List? ?? []).cast<Map<String, dynamic>>();
      for (final c in _ctrls.values) c.dispose();
      _ctrls.clear();
      for (final s in items) {
        _ctrls[s['setting_key'] as String] = TextEditingController(text: s['setting_value'] as String? ?? '');
      }
      setState(() { _settings = items; _loading = false; });
    } catch (e) {
      setState(() { _error = e; _loading = false; });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<AppState>().apiClient.patch('/super-admin/system-settings',
          {for (final e in _ctrls.entries) e.key: e.value.text});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved successfully')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _PageHeader(
        title: 'System Settings',
        subtitle: 'Platform configuration and defaults',
        action: FilledButton.icon(
          icon: _saving
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save, size: 18),
          label: const Text('Save'),
          onPressed: _saving || _loading ? null : _save,
        ),
      ),
      const Divider(height: 1),
      if (_loading) const Expanded(child: Center(child: CircularProgressIndicator()))
      else if (_error != null) Expanded(child: ErrorRetryView(error: _error!, onRetry: _load))
      else if (_settings.isEmpty) Expanded(child: _EmptyState(icon: Icons.settings, message: 'No system settings configured'))
      else Expanded(child: ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: _settings.length,
          itemBuilder: (_, i) {
            final s = _settings[i];
            final key = s['setting_key'] as String;
            final encrypted = s['encrypted'] == true;
            return FadeSlideIn(
              delay: Duration(milliseconds: 40 * (i.clamp(0, 8))),
              child: Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(key, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: PgColors.ink)),
                const SizedBox(height: 8),
                encrypted
                    ? Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: const Color(0xFFF9F9FD), borderRadius: BorderRadius.circular(8)),
                        child: const Row(children: [
                          Icon(Icons.lock_outline, size: 14, color: Color(0xFF9CA3AF)),
                          SizedBox(width: 6),
                          Text('Encrypted value', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                        ]),
                      )
                    : TextField(
                        controller: _ctrls[key],
                        decoration: const InputDecoration(isDense: true),
                      ),
              ])),
            ));
          },
        )),
    ]);
  }
}
