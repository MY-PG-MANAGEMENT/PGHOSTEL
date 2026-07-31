import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../reports/active_tenants_pdf.dart';
import '../reports/report_ui.dart';
import '../theme/app_theme.dart';
import '../utils/money.dart';
import '../utils/validators.dart';
import '../widgets/animations.dart';
import '../widgets/app_toast.dart';
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
    (Icons.bar_chart_outlined,   Icons.bar_chart,    'Reports'),
    (Icons.history_outlined,     Icons.history,      'Audit Logs'),
    (Icons.settings_outlined,    Icons.settings,     'System Settings'),
    (Icons.forum_outlined,       Icons.forum,        'Messaging'),
  ];

  // Users live under Organizations → Users / Tenants (that is where passwords are reset),
  // so there is no top-level Users section. Plans is gone entirely — see V29.
  Widget get _body => switch (_sel) {
    0 => const _AdminDashboard(),
    1 => const _AdminOrganizations(),
    2 => const _AdminDataUpload(),
    3 => const _AdminReports(),
    4 => const _AdminAuditLogs(),
    5 => const _AdminSettings(),
    6 => const _AdminMessaging(),
    _ => const SizedBox.shrink(),
  };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final sidebar = _Sidebar(sel: _sel, nav: _nav, onSel: (i) {
      setState(() => _sel = i);
      if (!wide) Navigator.pop(context);
    });
    // The sidebar sections are local state, not routes, so on the root /admin
    // route the system back button had nothing to pop and closed the app from
    // whichever section the admin was in. Back now unwinds to Dashboard first,
    // and only bubbles to the platform (exit / minimise) once already there.
    // An open drawer is not a special case: Scaffold registers a
    // LocalHistoryEntry for it, and local history is consulted before PopScope,
    // so back closes the drawer and leaves the section untouched.
    return PopScope(
      canPop: _sel == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _sel = 0);
      },
      child: Scaffold(
      backgroundColor: const Color(0xFFF5F5FA),
      appBar: wide ? null : AppBar(
        title: Text(_sel == 0 ? 'Admin Console' : _nav[_sel].$3,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.white,
        foregroundColor: PgColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        // The leading slot stays the drawer hamburger — it is the only tap
        // affordance for switching sections on mobile. Back to Dashboard is the
        // system back button (see PopScope above).
        bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1)),
      ),
      drawer: wide ? null : Drawer(child: sidebar),
      body: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              sidebar,
              Expanded(child: _body),
            ])
          : _body,
      ),
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
            // Expanded + ellipsis: the sidebar is a fixed 220px, so an
            // unconstrained Column here overflows as soon as the text gets wider
            // than the leftover space — which it does under a large system font
            // scale (and in widget tests, where the test font is wider).
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Admin Console',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: PgColors.ink)),
              Text('Super Admin',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ])),
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
                      // Same reason as the header above: fixed-width sidebar, so
                      // the longest label ('System Settings') must be allowed to
                      // ellipsize rather than overflow the row.
                      Expanded(child: Text(label,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                          color: active ? PgColors.primary : PgColors.ink,
                        ))),
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
                      Text(inr(d['monthlyRevenue'] ?? 0),
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
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      AppToast.successOf(messenger,
          'Announcement sent to ${res['sentToOrgs'] ?? 0} organization(s)',
          title: 'Broadcast Sent');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.toString().replaceFirst('Exception: ', ''));
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
          child: SingleChildScrollView(
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
    final api = context.read<AppState>().apiClient;
    setState(() { _loading = true; _error = null; });
    try {
      final data = await api.get('/super-admin/organizations');
      if (!mounted) return;
      setState(() { _orgs = (data['items'] as List? ?? []).cast<Map<String, dynamic>>();  _loading = false; });
    } catch (e) {
      if (!mounted) return;
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
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
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final f in ['ALL', 'ACTIVE', 'INACTIVE', 'SUSPENDED'])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
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

// ─── Messaging Channels ───────────────────────────────────────────────────────

/// Per-organization on/off control for outbound messaging channels
/// (EMAIL / WHATSAPP). Channels are opt-in — off until enabled here.
/// Backed by `GET/PATCH /super-admin/organizations/{id}/channels`.
class _AdminMessaging extends StatefulWidget {
  const _AdminMessaging();
  @override
  State<_AdminMessaging> createState() => _AdminMessagingState();
}

class _AdminMessagingState extends State<_AdminMessaging> {
  List<Map<String, dynamic>> _orgs = [];
  bool _loading = true;
  Object? _error;
  String _query = '';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final api = context.read<AppState>().apiClient;
    setState(() { _loading = true; _error = null; });
    try {
      final data = await api.get('/super-admin/organizations');
      if (!mounted) return;
      setState(() { _orgs = (data['items'] as List? ?? []).cast<Map<String, dynamic>>(); _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e; _loading = false; });
    }
  }

  List<Map<String, dynamic>> get _filtered => _orgs.where((o) =>
      _query.isEmpty || '${o['facility_name']}'.toLowerCase().contains(_query.toLowerCase())).toList();

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _PageHeader(
        title: 'Messaging',
        subtitle: 'Email / WhatsApp per organization',
        action: IconButton(icon: const Icon(Icons.refresh, size: 20), tooltip: 'Refresh', onPressed: _load),
      ),
      const Divider(height: 1),
      if (_loading) const Expanded(child: Center(child: CircularProgressIndicator()))
      else if (_error != null) Expanded(child: ErrorRetryView(error: _error!, onRetry: _load))
      else ...[
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 14),
          child: TextField(
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
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _filtered.isEmpty
            ? _EmptyState(icon: Icons.forum_outlined, message: 'No organizations match your search')
            : ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: _filtered.length,
                itemBuilder: (_, i) => FadeSlideIn(
                  delay: Duration(milliseconds: 40 * (i.clamp(0, 8))),
                  child: _OrgCard(org: _filtered[i], onTap: () => _openChannels(_filtered[i])),
                ),
              )),
      ],
    ]);
  }

  void _openChannels(Map<String, dynamic> org) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _OrgChannelsSheet(org: org),
    );
  }
}

/// Bottom sheet with EMAIL / WHATSAPP switches for one organization.
class _OrgChannelsSheet extends StatefulWidget {
  const _OrgChannelsSheet({required this.org});
  final Map<String, dynamic> org;
  @override
  State<_OrgChannelsSheet> createState() => _OrgChannelsSheetState();
}

class _OrgChannelsSheetState extends State<_OrgChannelsSheet> {
  static const _channels = [
    ('EMAIL', 'Email', 'Tenant emails via the platform relay', Icons.mail_outline_rounded),
    ('WHATSAPP', 'WhatsApp', 'WhatsApp messages (coming soon)', Icons.chat_outlined),
  ];

  Map<String, bool> _state = {};
  bool _tenantLogin = false;
  bool _loading = true;
  Object? _error;
  String? _busy; // channel currently being toggled

  int get _orgId => (widget.org['organization_id'] as num).toInt();

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final api = context.read<AppState>().apiClient;
    setState(() { _loading = true; _error = null; });
    try {
      final data = await api.get('/super-admin/organizations/$_orgId/channels');
      final tl = await api.get('/super-admin/organizations/$_orgId/tenant-login');
      if (!mounted) return;
      setState(() { _state = _asBoolMap(data); _tenantLogin = tl['enabled'] == true; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e; _loading = false; });
    }
  }

  Future<void> _toggleTenantLogin(bool enabled) async {
    final api = context.read<AppState>().apiClient;
    setState(() => _busy = 'TENANT_LOGIN');
    try {
      final data = await api.patch('/super-admin/organizations/$_orgId/tenant-login', {'enabled': enabled});
      if (!mounted) return;
      setState(() { _tenantLogin = data['enabled'] == true; _busy = null; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = null);
      AppToast.error(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Map<String, bool> _asBoolMap(dynamic data) {
    final map = <String, bool>{};
    if (data is Map) data.forEach((k, v) => map['$k'] = v == true);
    return map;
  }

  Future<void> _toggle(String channel, bool enabled) async {
    final api = context.read<AppState>().apiClient;
    setState(() => _busy = channel);
    try {
      final data = await api
          .patch('/super-admin/organizations/$_orgId/channels', {'channel': channel, 'enabled': enabled});
      if (!mounted) return;
      setState(() { _state = _asBoolMap(data); _busy = null; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = null);
      AppToast.error(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
            child: Row(children: [
              Expanded(child: Text('${widget.org['facility_name'] ?? 'Organization'}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: PgColors.ink))),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
              ),
            ]),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Enable the channels this organization can use.',
                style: TextStyle(color: PgColors.textSecondary, fontSize: 13)),
          ),
          const Divider(height: 1),
          if (_loading)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Padding(padding: const EdgeInsets.all(24), child: ErrorRetryView(error: _error!, onRetry: _load))
          else
            ...[
              ..._channels.map((c) {
                final code = c.$1;
                final on = _state[code] ?? false;
                return SwitchListTile(
                  value: on,
                  onChanged: _busy != null ? null : (v) => _toggle(code, v),
                  activeThumbColor: PgColors.primary,
                  secondary: Icon(c.$4, color: on ? PgColors.primary : PgColors.textSecondary),
                  title: Text(c.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(c.$3, style: const TextStyle(fontSize: 12.5)),
                );
              }),
              const Divider(height: 1),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 2),
                child: Text('TENANT ACCESS',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: PgColors.textTertiary, letterSpacing: 0.5)),
              ),
              SwitchListTile(
                value: _tenantLogin,
                onChanged: _busy != null ? null : _toggleTenantLogin,
                activeThumbColor: PgColors.primary,
                secondary: Icon(Icons.person_pin_circle_outlined,
                    color: _tenantLogin ? PgColors.primary : PgColors.textSecondary),
                title: const Text('Tenant Login', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Let this org’s tenants log in to the mobile app', style: TextStyle(fontSize: 12.5)),
              ),
            ],
          const SizedBox(height: 12),
        ],
      ),
    );
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
  final _orgEmail = TextEditingController();
  final _fullName = TextEditingController();
  final _mobile = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _saving = false;

  @override
  void dispose() {
    _orgName.dispose();
    _orgEmail.dispose();
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
        'organizationEmail': _orgEmail.text.trim(),
        'fullName': _fullName.text.trim(),
        'mobileNumber': _mobile.text.trim(),
        'username': _username.text.trim(),
        'password': _password.text,
      });
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      widget.onCreated();
      AppToast.successOf(messenger,
          'Organization "${res['organizationName']}" created with owner @${res['ownerUsername']}',
          title: 'Organization Created');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.toString().replaceFirst('Exception: ', ''));
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
                controller: _orgEmail,
                decoration: _deco('Organization Email', Icons.email_outlined),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                validator: Validators.email,
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

/// Super-admin password reset, shared by the organization sheet's Users and Tenants tabs.
/// There is no cross-organization user list any more — a reset always starts from the org
/// that owns the login, so both callers hand this the `user_login_id` they already have.
void _showResetPasswordDialog(
  BuildContext context, {
  required Object userLoginId,
  required String name,
  required String username,
}) {
  final api = context.read<AppState>().apiClient;
  final pwdCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();
  final formKey = GlobalKey<FormState>();
  bool busy = false;
  showDialog(context: context, builder: (ctx) => StatefulBuilder(
    builder: (ctx, setDialog) => AlertDialog(
      title: const Text('Reset Password', style: TextStyle(fontWeight: FontWeight.w700)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Form(
        key: formKey,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$name • @$username',
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          const SizedBox(height: 16),
          TextFormField(
            controller: pwdCtrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'New password', isDense: true),
            validator: (v) => (v == null || v.length < 8) ? 'At least 8 characters' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: confirmCtrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Confirm password', isDense: true),
            validator: (v) => v != pwdCtrl.text ? 'Passwords do not match' : null,
          ),
          const SizedBox(height: 8),
          const Text('The user will be signed out of all active sessions.',
              style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
        ]),
      ),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: busy ? null : () async {
            if (!formKey.currentState!.validate()) return;
            setDialog(() => busy = true);
            try {
              await api.post(
                '/super-admin/users/$userLoginId/reset-password',
                {'newPassword': pwdCtrl.text},
              );
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) AppToast.success(context, 'Password reset for @$username');
            } catch (e) {
              setDialog(() => busy = false);
              if (ctx.mounted) AppToast.error(ctx, e.toString().replaceFirst('Exception: ', ''));
            }
          },
          child: busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Reset'),
        ),
      ],
    ),
  ));
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
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _tenants = [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() { super.initState(); _tabs = TabController(length: 3, vsync: this); _load(); }
  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _load() async {
    final orgId = widget.org['organization_id'];
    // Capture the client before any await so we never touch a defunct context
    // if the sheet is dismissed mid-load.
    final api = context.read<AppState>().apiClient;
    setState(() { _loading = true; _error = null; });
    try {
      final detail = await api.get('/super-admin/organizations/$orgId');
      final users = await api.get('/super-admin/organizations/$orgId/users');
      final tenants = await api.get('/super-admin/organizations/$orgId/tenants');
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _users = (users['items'] as List? ?? []).cast<Map<String, dynamic>>();
        _tenants = (tenants['items'] as List? ?? []).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e; _loading = false; });
    }
  }

  Future<void> _toggleStatus() async {
    final orgId = widget.org['organization_id'];
    final current = '${_detail?['status'] ?? widget.org['status'] ?? 'ACTIVE'}';
    final next = current == 'ACTIVE' ? 'INACTIVE' : 'ACTIVE';
    final api = context.read<AppState>().apiClient;
    try {
      await api.patch('/super-admin/organizations/$orgId/status', {'status': next});
      widget.onStatusChanged();
      await _load();
    } catch (e) {
      if (mounted) {
        AppToast.error(context, e.toString().replaceFirst('Exception: ', ''));
      }
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
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              tooltip: 'Close',
              onPressed: () => Navigator.pop(context),
            ),
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
            tabs: [
              const Tab(text: 'Overview'),
              Tab(text: 'Users (${_users.length})'),
              Tab(text: 'Tenants (${_tenants.length})'),
            ],
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
            _users.isEmpty
                ? _EmptyState(icon: Icons.badge_outlined, message: 'No logins in this organization')
                : ListView.separated(
                    itemCount: _users.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
                    itemBuilder: (_, i) {
                      final u = _users[i];
                      final name = '${u['full_name'] ?? u['username'] ?? '—'}';
                      final role = '${u['role_type_id'] ?? ''}';
                      final roleColor = role == 'OWNER' ? PgColors.primary : PgColors.warning;
                      return ListTile(
                        leading: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(color: PgColors.lavender, borderRadius: BorderRadius.circular(10)),
                          child: Center(child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(color: PgColors.primary, fontWeight: FontWeight.w700, fontSize: 14),
                          )),
                        ),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Text('@${u['username']}  •  ${u['mobile_number'] ?? '—'}',
                            style: const TextStyle(fontSize: 12)),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          _RolePill(role, roleColor),
                          if (role != 'SUPER_ADMIN')
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, size: 18, color: Color(0xFF9CA3AF)),
                              tooltip: 'User actions',
                              padding: EdgeInsets.zero,
                              onSelected: (v) {
                                if (v == 'reset') {
                                  _showResetPasswordDialog(context,
                                      userLoginId: u['user_login_id'] as Object,
                                      name: name,
                                      username: '${u['username']}');
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'reset', child: Text('Reset password')),
                              ],
                            ),
                        ]),
                      );
                    }),
            _tenants.isEmpty
                ? _EmptyState(icon: Icons.people_outline, message: 'No active tenants')
                : ListView.separated(
                    itemCount: _tenants.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
                    itemBuilder: (_, i) {
                      final t = _tenants[i];
                      final loginId = t['user_login_id'];
                      return ListTile(
                        leading: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(color: PgColors.lavender, borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.person, size: 18, color: PgColors.primary),
                        ),
                        title: Text('${t['full_name'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Text('${t['mobile_number'] ?? '—'}  •  Bed: ${t['bed_name'] ?? 'Unassigned'}',
                            style: const TextStyle(fontSize: 12)),
                        // A tenant only has a login when the org has Tenant Login enabled, so the
                        // item is disabled rather than hidden — otherwise the missing menu reads
                        // as a bug instead of "this org has no tenant portal".
                        trailing: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, size: 18, color: Color(0xFF9CA3AF)),
                          tooltip: 'Tenant actions',
                          padding: EdgeInsets.zero,
                          onSelected: (v) {
                            if (v == 'reset' && loginId != null) {
                              _showResetPasswordDialog(context,
                                  userLoginId: loginId as Object,
                                  name: '${t['full_name'] ?? t['username'] ?? '—'}',
                                  username: '${t['username']}');
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'reset',
                              enabled: loginId != null,
                              child: Text(loginId != null ? 'Reset password' : 'No portal login'),
                            ),
                          ],
                        ),
                      );
                    }),
          ])),
        ],
      ]),
    );
  }
}

class _RolePill extends StatelessWidget {
  const _RolePill(this.role, this.color);
  final String role;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Text(role, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
  );
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
  bool _pasteMode = false;
  final _pasteCtrl = TextEditingController();
  Map<String, dynamic>? _result;
  bool _uploading = false;
  Object? _uploadError;

  // Column → human description. Keys match the backend BulkUploadController parser.
  static const _facilityColDesc = {
    'property_name': 'Property name — created if it does not exist',
    'property_code': 'Property code — match or set on create — optional',
    'floor_name': 'Floor label, e.g. Ground Floor',
    'floor_number': 'Numeric floor, e.g. 0, 1, 2',
    'floor_code': 'Custom code for the floor — optional',
    'room_name': 'Room label, e.g. Room 101',
    'room_number': 'Short room code, e.g. 101',
    'room_code': 'Custom code for the room — optional',
    'sharing_type': 'SINGLE, DOUBLE, TRIPLE, …',
    'monthly_rent': 'Rent per bed for the room',
    'security_deposit': 'Default deposit for the room — optional',
    'is_ac': 'AC room? true / false — optional',
    'capacity': 'Beds the room holds — optional',
    'bed_name': 'Bed label, e.g. Bed A',
    'bed_code': 'Custom unique code for the bed — optional',
  };
  static const _tenantColDesc = {
    'full_name': 'Tenant full name — required',
    'mobile_number': '10-digit mobile — required, unique',
    'email': 'Email address — optional',
    'gender': 'MALE, FEMALE or OTHER',
    'date_of_birth': 'Format YYYY-MM-DD',
    'aadhaar_number': '12-digit Aadhaar — optional',
    'occupation': 'Job / occupation',
    'permanent_address': 'Home address',
    'employer_name': 'Employer / company — optional',
    'designation': 'Job title — optional',
    'work_address': 'Office address — optional',
    'has_vehicle': 'Owns a vehicle? true / false — optional',
    'emergency_contact_name': 'Emergency contact name',
    'emergency_contact_mobile': 'Emergency contact mobile',
    'emergency_contact_relation': 'e.g. Father, Mother',
    'property_name': 'Property to assign a bed in — optional',
    'property_code': 'Property by code instead of name — optional',
    'floor_name': 'Floor of the bed — optional',
    'floor_code': 'Floor by code instead of name — optional',
    'room_name': 'Room of the bed — optional',
    'room_code': 'Room by code instead of name — optional',
    'bed_name': 'Bed to assign — optional',
    'bed_code': 'Assign by bed code (resolves directly) — optional',
    'move_in_date': 'Format YYYY-MM-DD',
    'monthly_rent': 'Override all-in rent — optional',
    'ac_charges': 'AC part of the rent (breakdown) — optional',
    'security_deposit': 'Security deposit — optional',
    'expected_checkout_date': 'Planned checkout YYYY-MM-DD — optional',
    'paid_up_to_month': 'Backfill paid rent up to YYYY-MM — optional',
    'payment_method': 'CASH / UPI / BANK for backfill — optional',
  };

  // Ready-made example CSV — mirrors the backend template endpoints exactly.
  static const _facilitiesExample =
      'property_name,property_code,floor_name,floor_number,floor_code,room_name,room_number,room_code,'
      'sharing_type,monthly_rent,security_deposit,is_ac,capacity,bed_name,bed_code\n'
      'My PG Property,PROP-A,Ground Floor,0,FL-G,Room G01,G01,RM-G01,DOUBLE,5000,10000,false,2,Bed A,BED-G01-A\n'
      'My PG Property,PROP-A,Ground Floor,0,FL-G,Room G01,G01,RM-G01,DOUBLE,5000,10000,false,2,Bed B,BED-G01-B\n'
      'My PG Property,PROP-A,First Floor,1,FL-1,Room 101,101,RM-101,SINGLE,7000,14000,true,1,Bed 1,BED-101-1\n';
  static const _tenantsExample =
      'full_name,mobile_number,email,gender,date_of_birth,aadhaar_number,occupation,permanent_address,'
      'employer_name,designation,work_address,has_vehicle,'
      'emergency_contact_name,emergency_contact_mobile,emergency_contact_relation,'
      'property_name,property_code,floor_name,floor_code,room_name,room_code,bed_name,bed_code,'
      'move_in_date,monthly_rent,ac_charges,security_deposit,expected_checkout_date,paid_up_to_month,payment_method\n'
      'Ravi Kumar,9876543210,ravi@example.com,MALE,1998-05-20,123456789012,Software Engineer,Hyderabad,'
      'Infosys,Senior Engineer,Hitech City,true,Suresh Kumar,9876543211,Father,'
      'My PG Property,,Ground Floor,,Room G01,,Bed A,,2024-01-15,5000,0,10000,,2024-04,CASH\n'
      'Bharat Rao,9876543299,,MALE,,,,Hyderabad,,,,false,,,,,,,,,,,BED-101-1,2024-03-01,7000,,14000,,2024-05,UPI\n'
      'Cathy Iyer,9876543288,,FEMALE,,,,Pune,,,,false,,,,,PROP-A,,,,RM-101,Bed 1,,2024-04-01,7000,,14000,,2024-06,BANK\n'
      'Priya Sharma,9887654321,,,,,,,,,,,,,,,,,,,,,,,,,,,,\n';

  Map<String, String> get _colDesc =>
      _uploadType == 'FACILITIES' ? _facilityColDesc : _tenantColDesc;
  String get _exampleCsv =>
      _uploadType == 'FACILITIES' ? _facilitiesExample : _tenantsExample;
  List<String> get _cols => _colDesc.keys.toList();

  @override
  void initState() { super.initState(); _loadOrgs(); }

  @override
  void dispose() { _pasteCtrl.dispose(); super.dispose(); }

  Future<void> _loadOrgs() async {
    final api = context.read<AppState>().apiClient;
    try {
      final data = await api.get('/super-admin/organizations');
      if (!mounted) return;
      setState(() { _orgs = (data['items'] as List? ?? []).cast<Map<String, dynamic>>(); });
    } catch (_) {}
  }

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
                AppToast.success(context, 'Header copied to clipboard',
                    title: 'Header Copied');
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

  bool get _canUpload =>
      _pasteMode ? _pasteCtrl.text.trim().isNotEmpty : _pickedFile != null;

  Widget _buildStep3() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    // ── Step marker: download the template ──
    Card(child: Padding(padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _StepBadge(1),
          const SizedBox(width: 10),
          const Text('Download the Template',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: PgColors.ink)),
        ]),
        const SizedBox(height: 10),
        const Text(
          'Get our ready-made CSV template. Fill it with your data, then come back here to upload.',
          style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.download_outlined, size: 18),
            label: const Text('Copy Template (.csv)'),
            style: OutlinedButton.styleFrom(
              foregroundColor: PgColors.primary,
              side: const BorderSide(color: PgColors.primary),
              backgroundColor: PgColors.lavender,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _exampleCsv));
              AppToast.success(context,
                  'Template copied — paste it into a spreadsheet, fill it, and save as .csv',
                  title: 'Template Copied');
            },
          ),
        ),
      ]),
    )),
    const SizedBox(height: 12),
    // ── Column reference (expandable) ──
    Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: const Icon(Icons.list_alt_outlined, color: PgColors.primary),
          title: const Text('View all column names & descriptions',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: PgColors.primary)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: _colDesc.entries.map((e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: PgColors.lavender, borderRadius: BorderRadius.circular(4)),
                child: Text(e.key,
                    style: const TextStyle(fontSize: 11, color: PgColors.primary, fontFamily: 'monospace')),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(e.value,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)))),
            ]),
          )).toList(),
        ),
      ),
    ),
    const SizedBox(height: 12),
    // ── Step marker: upload ──
    Card(child: Padding(padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _StepBadge(2),
          const SizedBox(width: 10),
          const Text('Upload Your CSV',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: PgColors.ink)),
        ]),
        const SizedBox(height: 6),
        Text('Importing ${_uploadType.toLowerCase()} for: ${_selectedOrg?['facility_name'] ?? '—'}',
            style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
        const SizedBox(height: 14),
        // Pick File / Paste CSV toggle
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(children: [
            _ModeTab(label: 'Pick File', icon: Icons.folder_open,
                selected: !_pasteMode, onTap: () => setState(() => _pasteMode = false)),
            _ModeTab(label: 'Paste CSV', icon: Icons.content_paste,
                selected: _pasteMode, onTap: () => setState(() => _pasteMode = true)),
          ]),
        ),
        const SizedBox(height: 14),
        if (!_pasteMode) _buildPickFile() else _buildPasteCsv(),
        if (_uploadError != null) ...[
          const SizedBox(height: 12),
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
        const SizedBox(height: 18),
        if (_uploading)
          const LinearProgressIndicator()
        else
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            OutlinedButton(onPressed: () => setState(() => _step = 1), child: const Text('Back')),
            FilledButton.icon(
              icon: const Icon(Icons.upload, size: 18),
              label: const Text('Import'),
              onPressed: _canUpload ? _upload : null,
            ),
          ]),
      ]),
    )),
  ]);

  Widget _buildPickFile() => InkWell(
    onTap: _pickFile,
    borderRadius: BorderRadius.circular(10),
    child: DottedBorderBox(
      active: _pickedFile != null,
      child: Column(children: [
        Container(
          width: 56, height: 56,
          decoration: const BoxDecoration(color: Color(0xFFF3F4F6), shape: BoxShape.circle),
          child: Icon(
            _pickedFile != null ? Icons.check_circle : Icons.cloud_upload_outlined,
            size: 30,
            color: _pickedFile != null ? PgColors.success : const Color(0xFF9CA3AF),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _pickedFile?.name ?? 'Tap to select your CSV file',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: _pickedFile != null ? PgColors.ink : PgColors.ink,
          ),
        ),
        if (_pickedFile == null)
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text('Supports .csv and .txt files',
                style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
          ),
      ]),
    ),
  );

  Widget _buildPasteCsv() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      const Text('Paste your CSV data below',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      const Spacer(),
      TextButton(
        onPressed: () => setState(() {
          _pasteCtrl.text = _exampleCsv;
          _uploadError = null;
        }),
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: Size.zero),
        child: const Text('Use example', style: TextStyle(fontSize: 13)),
      ),
    ]),
    const SizedBox(height: 6),
    TextField(
      controller: _pasteCtrl,
      onChanged: (_) => setState(() => _uploadError = null),
      maxLines: 8,
      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
      decoration: InputDecoration(
        hintText: '${_cols.take(3).join(',')},…\n${_exampleCsv.split('\n').length > 1 ? _exampleCsv.split('\n')[1].split(',').take(3).join(',') : ''},…',
        hintStyle: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Color(0xFF9CA3AF)),
        alignLabelWithHint: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.all(12),
      ),
    ),
  ]);

  Future<void> _pickFile() async {
    const typeGroup = XTypeGroup(label: 'CSV', extensions: ['csv', 'txt']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file != null) setState(() { _pickedFile = file; _uploadError = null; });
  }

  Future<void> _upload() async {
    if (_selectedOrg == null || !_canUpload) return;
    final api = context.read<AppState>().apiClient;
    setState(() { _uploading = true; _uploadError = null; });
    try {
      final Uint8List bytes;
      final String filename;
      if (_pasteMode) {
        bytes = Uint8List.fromList(utf8.encode(_pasteCtrl.text.trim()));
        filename = '${_uploadType.toLowerCase()}.csv';
      } else {
        bytes = await _pickedFile!.readAsBytes();
        filename = _pickedFile!.name;
      }
      final orgId = _selectedOrg!['organization_id'];
      final type = _uploadType.toLowerCase();
      final data = await api.postFile('/super-admin/upload/$type/$orgId', bytes, filename);
      if (!mounted) return;
      setState(() { _result = data; _uploading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _uploadError = e; _uploading = false; });
    }
  }

  void _reset() => setState(() {
    _step = 0; _selectedOrg = null; _pickedFile = null;
    _pasteMode = false; _pasteCtrl.clear();
    _result = null; _uploadError = null; _uploading = false;
  });
}

class _StepBadge extends StatelessWidget {
  const _StepBadge(this.n);
  final int n;
  @override
  Widget build(BuildContext context) => Container(
    width: 26, height: 26,
    decoration: const BoxDecoration(color: PgColors.primary, shape: BoxShape.circle),
    alignment: Alignment.center,
    child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
  );
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({required this.label, required this.icon, required this.selected, required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? PgColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 16, color: selected ? Colors.white : const Color(0xFF6B7280)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w600,
            color: selected ? Colors.white : const Color(0xFF6B7280),
          )),
        ]),
      ),
    ),
  );
}

/// Dashed-border drop zone used by the CSV file picker.
class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({required this.child, this.active = false, super.key});
  final Widget child;
  final bool active;
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DashedRectPainter(color: active ? PgColors.primary : const Color(0xFFCBD2DE)),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
      child: child,
    ),
  );
}

class _DashedRectPainter extends CustomPainter {
  _DashedRectPainter({required this.color});
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
        Offset.zero & size, const Radius.circular(12));
    final path = Path()..addRRect(rrect);
    const dash = 6.0, gap = 4.0;
    for (final metric in path.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        canvas.drawPath(metric.extractPath(dist, dist + dash), paint);
        dist += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRectPainter old) => old.color != color;
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

// ─── Reports ──────────────────────────────────────────────────────────────────

class _AdminReports extends StatefulWidget {
  const _AdminReports();
  @override
  State<_AdminReports> createState() => _AdminReportsState();
}

/// Download-only, like the owner-side Reports tab: nothing is fetched until a
/// download is requested. The read-only revenue `DataTable` that used to live
/// here is gone — an on-screen table nobody could export was the wrong shape for
/// a screen whose job is producing the monthly billing sheet.
class _AdminReportsState extends State<_AdminReports> {
  DateTime _month = reportThisMonth();
  bool _busy = false;

  Future<void> _download() async {
    await runReportDownload(
      context,
      setBusy: (v) => setState(() => _busy = v),
      run: () => downloadReport(
        context,
        path: '/super-admin/reports/active-tenants?month=${reportMonthParam(_month)}',
        build: buildActiveTenantsPdf,
        filename: 'active-tenants-${reportFileMonth(_month)}.pdf',
      ),
      emptyMessage: 'No organizations for ${reportMonthLabel(_month)}',
      okMessage: (n) => 'Active Tenants Report ready · $n organisation${n == 1 ? '' : 's'}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const _PageHeader(
        title: 'Reports',
        subtitle: 'Downloadable platform reports',
      ),
      const Divider(height: 1),
      Expanded(child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          FadeSlideIn(child: ReportCard(
            icon: Icons.groups_rounded,
            iconBg: const Color(0xFFEDE9FE),
            iconColor: const Color(0xFF6D28D9),
            title: 'Active Tenants Report',
            subtitle: 'Per-organization active tenants, properties and billable amount',
            busy: _busy,
            onDownload: _busy ? null : _download,
            filters: [
              ReportMonthField(
                label: 'Month',
                value: _month,
                enabled: !_busy,
                onChanged: (m) => setState(() => _month = m),
              ),
            ],
          )),
          const SizedBox(height: 12),
          // The rate is set elsewhere, so say so here rather than letting an
          // unexpected total send the admin hunting for the pricing screen.
          Row(children: [
            const Icon(Icons.info_outline, size: 14, color: Color(0xFF9CA3AF)),
            const SizedBox(width: 6),
            Expanded(child: Text(
              'Amounts use the per-tenant price from System Settings → Per-Tenant Pricing.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            )),
          ]),
        ],
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
    final api = context.read<AppState>().apiClient;
    setState(() { _loading = true; _error = null; });
    try {
      final data = await api.get('/super-admin/system-settings');
      if (!mounted) return;
      final items = (data['items'] as List? ?? []).cast<Map<String, dynamic>>();
      for (final c in _ctrls.values) c.dispose();
      _ctrls.clear();
      for (final s in items) {
        _ctrls[s['setting_key'] as String] = TextEditingController(text: s['setting_value'] as String? ?? '');
      }
      setState(() { _settings = items; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e; _loading = false; });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      // Never send back encrypted settings — the GET returns them masked as
      // '********', so including them would overwrite the real secret (and the
      // backend upsert would clear the encrypted flag). Only save editable values.
      final encryptedKeys = <String>{
        for (final s in _settings) if (s['encrypted'] == true) s['setting_key'] as String,
      };
      final payload = {
        for (final e in _ctrls.entries)
          if (!encryptedKeys.contains(e.key)) e.key: e.value.text,
      };
      await context.read<AppState>().apiClient.patch('/super-admin/system-settings', payload);
      if (mounted) {
        AppToast.success(context, 'Settings saved successfully',
            title: 'Settings Saved');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, e.toString().replaceFirst('Exception: ', ''));
      }
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
      else Expanded(child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Pricing first: it is the setting an admin actually comes here to
            // change, and it drives the Active Tenants report's totals.
            const _TenantPricingSection(),
            const SizedBox(height: 24),
            const Text('Platform Settings',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: PgColors.ink)),
            const SizedBox(height: 10),
            if (_settings.isEmpty)
              _EmptyState(icon: Icons.settings, message: 'No system settings configured')
            else
              for (int i = 0; i < _settings.length; i++)
                _settingCard(_settings[i], i),
          ],
        )),
    ]);
  }

  Widget _settingCard(Map<String, dynamic> s, int i) {
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
  }
}

// ─── Per-tenant pricing ───────────────────────────────────────────────────────

/// What the platform charges per active tenant per month: one default plus
/// per-organization overrides.
///
/// Separate from the generic system-settings list above because the default is a
/// typed money value with per-org exceptions, not one more untyped string — and
/// because saving here is per row (immediate `PUT`), not part of the screen's
/// bulk Save button. Backed by `GET/PUT /super-admin/tenant-rates`.
class _TenantPricingSection extends StatefulWidget {
  const _TenantPricingSection();
  @override
  State<_TenantPricingSection> createState() => _TenantPricingSectionState();
}

class _TenantPricingSectionState extends State<_TenantPricingSection> {
  List<Map<String, dynamic>> _orgs = [];
  num _defaultPrice = 0;
  bool _loading = true;
  Object? _error;
  String _query = '';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final api = context.read<AppState>().apiClient;
    setState(() { _loading = true; _error = null; });
    try {
      final data = await api.get('/super-admin/tenant-rates');
      if (!mounted) return;
      setState(() {
        _defaultPrice = (data['defaultPricePerTenant'] as num?) ?? 0;
        _orgs = (data['items'] as List? ?? []).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e; _loading = false; });
    }
  }

  /// `organizationId: 0` is the sentinel the backend reads as "the default itself".
  Future<void> _edit({required int organizationId, required String name, required num current, required bool isDefault}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _RateDialog(
        organizationId: organizationId,
        title: isDefault ? 'Default Price' : name,
        current: current,
        // Clearing only makes sense for an override — the default has no fallback
        // of its own to fall back to.
        allowReset: !isDefault && current != _defaultPrice,
        defaultPrice: _defaultPrice,
      ),
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Card(child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          const Icon(Icons.error_outline, size: 18, color: PgColors.danger),
          const SizedBox(width: 8),
          Expanded(child: Text('Could not load pricing: ${_error.toString().replaceFirst('Exception: ', '')}',
              style: const TextStyle(fontSize: 12))),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ]),
      ));
    }

    final filtered = _orgs.where((o) {
      final name = '${o['facility_name'] ?? ''}'.toLowerCase();
      return _query.isEmpty || name.contains(_query.toLowerCase());
    }).toList();
    final overrides = _orgs.where((o) => o['customRate'] == true).length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Per-Tenant Pricing',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: PgColors.ink)),
      const SizedBox(height: 4),
      Text('Charged per active tenant per month. Drives the Active Tenants report.',
          style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      const SizedBox(height: 10),

      Card(child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: PgColors.lavender, borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.sell_outlined, size: 19, color: PgColors.primary),
        ),
        title: const Text('Default price', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
          overrides == 0
              ? 'Applies to every organization'
              : 'Applies to all but $overrides organization${overrides == 1 ? '' : 's'} on a custom rate',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('${inr(_defaultPrice)} / tenant',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: PgColors.primary)),
          const SizedBox(width: 4),
          const Icon(Icons.edit_outlined, size: 16, color: Color(0xFF9CA3AF)),
        ]),
        onTap: () => _edit(organizationId: 0, name: 'Default Price', current: _defaultPrice, isDefault: true),
      )),

      const SizedBox(height: 14),
      Row(children: [
        Text('Organization overrides', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey[700])),
        const Spacer(),
        SizedBox(width: 220, child: TextField(
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, size: 17),
            hintText: 'Search organizations…',
            isDense: true,
            filled: true, fillColor: const Color(0xFFF9F9FD),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: PgColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: PgColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: PgColors.primary)),
          ),
          onChanged: (v) => setState(() => _query = v),
        )),
      ]),
      const SizedBox(height: 8),

      if (filtered.isEmpty)
        _EmptyState(icon: Icons.business_outlined, message: 'No organizations found')
      else
        Card(child: Column(children: [
          for (int i = 0; i < filtered.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 14, endIndent: 14),
            _rateRow(filtered[i]),
          ],
        ])),
    ]);
  }

  Widget _rateRow(Map<String, dynamic> org) {
    final id = (org['organization_id'] as num).toInt();
    final name = '${org['facility_name'] ?? 'Org #$id'}';
    final price = (org['pricePerTenant'] as num?) ?? 0;
    final custom = org['customRate'] == true;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      subtitle: Text(custom ? 'Custom rate' : 'Default rate',
          style: TextStyle(fontSize: 11, color: custom ? PgColors.primary : const Color(0xFF9CA3AF))),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(inr(price), style: TextStyle(
          fontWeight: custom ? FontWeight.w700 : FontWeight.w500,
          fontSize: 13,
          color: custom ? PgColors.primary : const Color(0xFF6B7280),
        )),
        const SizedBox(width: 4),
        const Icon(Icons.edit_outlined, size: 15, color: Color(0xFF9CA3AF)),
      ]),
      onTap: () => _edit(organizationId: id, name: name, current: price, isDefault: false),
    );
  }
}

/// Edits one rate. Pops `true` when something was saved, so the caller reloads.
class _RateDialog extends StatefulWidget {
  const _RateDialog({
    required this.organizationId,
    required this.title,
    required this.current,
    required this.allowReset,
    required this.defaultPrice,
  });

  final int organizationId;
  final String title;
  final num current;
  final bool allowReset;
  final num defaultPrice;

  @override
  State<_RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends State<_RateDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.current.toStringAsFixed(2));
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  /// A null body value clears the override; the backend reads that as "back to default".
  Future<void> _submit({required bool reset}) async {
    if (!reset && !_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<AppState>().apiClient.put(
        '/super-admin/tenant-rates/${widget.organizationId}',
        {'pricePerTenant': reset ? null : num.parse(_ctrl.text.trim())},
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      AppToast.success(context, reset ? 'Reset to the default price' : 'Price updated');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppToast.error(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      content: Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Price per active tenant, per month',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          const SizedBox(height: 14),
          TextFormField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(prefixText: '₹ ', isDense: true),
            validator: (v) {
              final n = num.tryParse((v ?? '').trim());
              if (n == null) return 'Enter a valid amount';
              if (n < 0) return 'Cannot be negative';
              if (n > 100000) return 'Cannot exceed 100000';
              return null;
            },
          ),
          if (widget.organizationId != 0) ...[
            const SizedBox(height: 8),
            Text('Platform default is ${inr(widget.defaultPrice)}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
          ],
        ]),
      ),
      actions: [
        if (widget.allowReset)
          TextButton(
            onPressed: _busy ? null : () => _submit(reset: true),
            child: const Text('Use default', style: TextStyle(color: PgColors.danger)),
          ),
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy ? null : () => _submit(reset: false),
          child: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save'),
        ),
      ],
    );
  }
}
