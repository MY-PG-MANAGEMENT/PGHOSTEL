import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../theme/tenant_theme.dart';
import '../../utils/app_exception.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/skeleton.dart';

// ══════════════════════════════════════════════════════════════════════════
//  Tenant self-service module (Material 3, Purple + White).
//  Navigation is via Quick-Action cards only — no bottom nav, no FAB.
// ══════════════════════════════════════════════════════════════════════════

String _money(dynamic v) {
  final n = v is num ? v : num.tryParse('$v') ?? 0;
  final s = n.toStringAsFixed(n == n.roundToDouble() ? 0 : 2);
  final parts = s.split('.');
  final intPart = parts[0];
  final buf = StringBuffer();
  for (int i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
    buf.write(intPart[i]);
  }
  return '₹${buf.toString()}${parts.length > 1 ? '.${parts[1]}' : ''}';
}

String _date(dynamic iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse('$iso');
  if (d == null) return '$iso';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
}

Color _statusColor(String s) {
  switch (s.toUpperCase()) {
    case 'OPEN':
      return TenantColors.info;
    case 'IN_PROGRESS':
      return TenantColors.warning;
    case 'RESOLVED':
    case 'CLEAR':
      return TenantColors.success;
    case 'CLOSED':
      return TenantColors.textTertiary;
    case 'DUE':
    case 'OVERDUE':
      return TenantColors.danger;
    default:
      return TenantColors.primary;
  }
}

String _pretty(String s) => s.replaceAll('_', ' ').toLowerCase().split(' ')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

// ─── Shared building blocks ─────────────────────────────────────────────────

/// FutureBuilder wrapper with loading / no-internet / error-retry / builder.
class TenantData<T> extends StatelessWidget {
  const TenantData({super.key, required this.future, required this.builder, this.onRetry});
  final Future<T> future;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SkeletonList();
        }
        if (snap.hasError) {
          return _ErrorView(error: snap.error!, onRetry: onRetry);
        }
        return builder(snap.data as T);
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final network = isNetworkError(error);
    final msg = error.toString().replaceFirst('Exception: ', '');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(network ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
              size: 56, color: TenantColors.textTertiary),
          const SizedBox(height: 16),
          Text(network ? 'No internet connection' : 'Something went wrong',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: TenantColors.ink)),
          const SizedBox(height: 6),
          Text(network ? 'Check your connection and try again.' : msg,
              textAlign: TextAlign.center,
              style: const TextStyle(color: TenantColors.textSecondary, fontSize: 13)),
          if (onRetry != null) ...[
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
          ],
        ]),
      ),
    );
  }
}

class TenantEmpty extends StatelessWidget {
  const TenantEmpty({super.key, required this.icon, required this.message, this.hint});
  final IconData icon;
  final String message;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 84, height: 84,
            decoration: const BoxDecoration(color: TenantColors.primarySoft, shape: BoxShape.circle),
            child: Icon(icon, size: 38, color: TenantColors.primary),
          ),
          const SizedBox(height: 18),
          Text(message, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: TenantColors.ink)),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(hint!, textAlign: TextAlign.center, style: const TextStyle(color: TenantColors.textSecondary, fontSize: 13)),
          ],
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, {this.color});
  final String label;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final c = color ?? _statusColor(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Text(_pretty(label), style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 11)),
    );
  }
}

// ═══════════════════════════ Change password (forced) ═══════════════════════

class TenantChangePasswordScreen extends StatefulWidget {
  const TenantChangePasswordScreen({super.key});
  @override
  State<TenantChangePasswordScreen> createState() => _TenantChangePasswordScreenState();
}

class _TenantChangePasswordScreenState extends State<TenantChangePasswordScreen> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final state = context.read<AppState>();
    try {
      await state.apiClient.post('/tenant/change-password', {
        'oldPassword': _old.text,
        'newPassword': _new.text,
      });
      await state.clearMustChangePassword();
      if (mounted) {
        AppToast.success(context, 'Password updated');
        context.go('/tenant');
      }
    } catch (e) {
      setState(() => _busy = false);
      if (mounted) AppToast.error(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final forced = context.read<AppState>().mustChangePassword;
    return Scaffold(
      backgroundColor: TenantColors.scaffold,
      body: Column(
        children: [
          // ── Branded gradient header ──────────────────────────────────
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 20, 24, 32),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [TenantColors.primary, TenantColors.primaryDark],
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (!forced)
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => context.pop(),
                  ),
                ),
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.lock_reset_rounded, color: Colors.white, size: 30),
              ),
              const SizedBox(height: 16),
              Text(forced ? 'Secure your account' : 'Change password',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 23)),
              const SizedBox(height: 6),
              Text(
                forced
                    ? 'Set a new password to replace the temporary one before you continue.'
                    : 'Update the password you use to sign in.',
                style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.35),
              ),
            ]),
          ),
          // ── Form card ────────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: Form(
                key: _formKey,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 20, 18, 22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: TenantColors.border),
                      boxShadow: [
                        BoxShadow(color: TenantColors.primary.withValues(alpha: 0.06), blurRadius: 18, offset: const Offset(0, 8)),
                      ],
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _passwordField(
                        controller: _old,
                        label: 'Current password',
                        obscure: _obscureOld,
                        onToggle: () => setState(() => _obscureOld = !_obscureOld),
                        validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      _passwordField(
                        controller: _new,
                        label: 'New password',
                        obscure: _obscureNew,
                        onToggle: () => setState(() => _obscureNew = !_obscureNew),
                        validator: (v) => (v == null || v.length < 6) ? 'At least 6 characters' : null,
                      ),
                      const SizedBox(height: 16),
                      _passwordField(
                        controller: _confirm,
                        label: 'Confirm new password',
                        obscure: _obscureConfirm,
                        onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
                        validator: (v) => v != _new.text ? 'Passwords do not match' : null,
                      ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  const Row(children: [
                    Icon(Icons.info_outline_rounded, size: 15, color: TenantColors.textTertiary),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text('Use at least 6 characters.',
                          style: TextStyle(fontSize: 12, color: TenantColors.textTertiary)),
                    ),
                  ]),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 54,
                    child: FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Update password'),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline_rounded, color: TenantColors.primary, size: 20),
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: TenantColors.textTertiary, size: 20),
          onPressed: onToggle,
        ),
      ),
      validator: validator,
    );
  }
}

// ═══════════════════════════════ Dashboard ══════════════════════════════════

class TenantDashboardScreen extends StatefulWidget {
  const TenantDashboardScreen({super.key});
  @override
  State<TenantDashboardScreen> createState() => _TenantDashboardScreenState();
}

class _TenantDashboardScreenState extends State<TenantDashboardScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _future = context.read<AppState>().apiClient.get('/tenant/dashboard');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: TenantColors.primary,
          onRefresh: () async => _load(),
          child: TenantData<Map<String, dynamic>>(
            future: _future,
            onRetry: _load,
            builder: (d) {
              final property = (d['property'] as Map?)?.cast<String, dynamic>() ?? {};
              final due = (d['outstanding'] as Map?)?.cast<String, dynamic>() ?? {};
              final recent = (d['recentPayment'] as Map?)?.cast<String, dynamic>();
              final complaint = (d['latestComplaint'] as Map?)?.cast<String, dynamic>();
              final notice = (d['latestNotice'] as Map?)?.cast<String, dynamic>();
              final unread = (d['unreadNotifications'] as num?)?.toInt() ?? 0;
              return ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                children: [
                  _header(context, '${d['greetingName'] ?? 'there'}', unread),
                  const SizedBox(height: 18),
                  _PropertyCard(property: property),
                  const SizedBox(height: 14),
                  _DueCard(due: due, recent: recent),
                  const SizedBox(height: 22),
                  const Text('Quick Actions',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: TenantColors.ink)),
                  const SizedBox(height: 14),
                  _quickActions(context),
                  const SizedBox(height: 22),
                  if (complaint != null) _LatestComplaintTile(complaint: complaint),
                  if (notice != null) ...[
                    const SizedBox(height: 12),
                    _LatestNoticeTile(notice: notice),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, String name, int unread) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(greeting, style: const TextStyle(color: TenantColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 2),
          Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: TenantColors.ink)),
        ]),
      ),
      _NotificationBell(unread: unread, onTap: () => context.push('/tenant/notifications')),
      const SizedBox(width: 6),
      IconButton(
        tooltip: 'Logout',
        icon: const Icon(Icons.logout_rounded, color: TenantColors.textSecondary),
        onPressed: () async {
          await context.read<AppState>().logout();
          if (context.mounted) context.go('/login');
        },
      ),
    ]);
  }

  Widget _quickActions(BuildContext context) {
    final actions = [
      (Icons.person_outline_rounded, 'My Profile', '/tenant/profile'),
      (Icons.receipt_long_rounded, 'Payments', '/tenant/payments'),
      (Icons.support_agent_rounded, 'Complaints', '/tenant/complaints'),
      (Icons.campaign_outlined, 'Notices', '/tenant/notices'),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      childAspectRatio: 1.5,
      children: actions
          .map((a) => _QuickActionCard(icon: a.$1, label: a.$2, onTap: () => context.push(a.$3)))
          .toList(),
    );
  }
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell({required this.unread, required this.onTap});
  final int unread;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      IconButton(
        onPressed: onTap,
        icon: const Icon(Icons.notifications_none_rounded, color: TenantColors.ink, size: 26),
      ),
      if (unread > 0)
        Positioned(
          right: 6, top: 6,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(color: TenantColors.danger, shape: BoxShape.circle),
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            child: Text('${unread > 9 ? '9+' : unread}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ),
    ]);
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: TenantColors.border),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: TenantColors.primarySoft, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: TenantColors.primary, size: 23),
            ),
            const Spacer(),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: TenantColors.ink)),
          ]),
        ),
      ),
    );
  }
}

class _PropertyCard extends StatelessWidget {
  const _PropertyCard({required this.property});
  final Map<String, dynamic> property;
  @override
  Widget build(BuildContext context) {
    final active = property['hasActiveAdmission'] == true;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [TenantColors.primary, TenantColors.primaryDark],
        ),
        boxShadow: [BoxShadow(color: TenantColors.primary.withValues(alpha: 0.30), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.home_work_rounded, color: Colors.white, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${property['propertyName'] ?? 'My Stay'}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
          ),
        ]),
        const SizedBox(height: 16),
        if (active)
          Row(children: [
            _stat('Room', '${property['roomName'] ?? '—'}'),
            _stat('Bed', '${property['bedName'] ?? '—'}'),
            _stat('Since', _date(property['staySince'])),
          ])
        else
          const Text('Awaiting room allocation',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
      ]),
    );
  }

  Widget _stat(String label, String value) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
        ]),
      );
}

class _DueCard extends StatelessWidget {
  const _DueCard({required this.due, required this.recent});
  final Map<String, dynamic> due;
  final Map<String, dynamic>? recent;
  @override
  Widget build(BuildContext context) {
    final amount = due['amount'];
    final hasDue = (amount is num ? amount : num.tryParse('$amount') ?? 0) > 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('Outstanding due', style: TextStyle(color: TenantColors.textSecondary, fontSize: 13)),
            const Spacer(),
            _Chip(hasDue ? 'DUE' : 'CLEAR'),
          ]),
          const SizedBox(height: 8),
          Text(_money(amount ?? 0),
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 26, color: hasDue ? TenantColors.danger : TenantColors.success)),
          if (hasDue && due['dueDate'] != null) ...[
            const SizedBox(height: 4),
            Text('Due by ${_date(due['dueDate'])}', style: const TextStyle(color: TenantColors.textSecondary, fontSize: 12.5)),
          ],
          if (recent != null) ...[
            const Divider(height: 24),
            Row(children: [
              const Icon(Icons.check_circle_rounded, color: TenantColors.success, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text('Last payment ${_money(recent!['amount'])} on ${_date(recent!['payment_date'])}',
                  style: const TextStyle(fontSize: 12.5, color: TenantColors.ink))),
            ]),
          ],
        ]),
      ),
    );
  }
}

class _LatestComplaintTile extends StatelessWidget {
  const _LatestComplaintTile({required this.complaint});
  final Map<String, dynamic> complaint;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: () => context.push('/tenant/complaints/${complaint['complaint_id']}'),
        leading: const CircleAvatar(backgroundColor: TenantColors.primarySoft, child: Icon(Icons.support_agent_rounded, color: TenantColors.primary)),
        title: Text('${complaint['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text('Latest complaint', style: TextStyle(fontSize: 12)),
        trailing: _Chip('${complaint['status']}'),
      ),
    );
  }
}

class _LatestNoticeTile extends StatelessWidget {
  const _LatestNoticeTile({required this.notice});
  final Map<String, dynamic> notice;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: () => context.push('/tenant/notices/${notice['notice_id']}'),
        leading: const CircleAvatar(backgroundColor: TenantColors.primarySoft, child: Icon(Icons.campaign_outlined, color: TenantColors.primary)),
        title: Text('${notice['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text('Latest notice', style: TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right_rounded, color: TenantColors.textTertiary),
      ),
    );
  }
}

// ═══════════════════════════════ Profile ════════════════════════════════════

class TenantProfileScreen extends StatefulWidget {
  const TenantProfileScreen({super.key});
  @override
  State<TenantProfileScreen> createState() => _TenantProfileScreenState();
}

class _TenantProfileScreenState extends State<TenantProfileScreen> {
  late Future<Map<String, dynamic>> _future;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _future = context.read<AppState>().apiClient.get('/tenant/profile');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Profile', style: TextStyle(fontWeight: FontWeight.w700))),
      body: TenantData<Map<String, dynamic>>(
        future: _future,
        onRetry: _load,
        builder: (p) {
          final name = '${p['fullName'] ?? ''}';
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
            children: [
              Center(
                child: Column(children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: TenantColors.primarySoft,
                    child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                        style: const TextStyle(color: TenantColors.primary, fontWeight: FontWeight.w800, fontSize: 30)),
                  ),
                  const SizedBox(height: 12),
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: TenantColors.ink)),
                  const SizedBox(height: 4),
                  Text('Tenant ID: ${p['tenantId'] ?? '—'}', style: const TextStyle(color: TenantColors.textSecondary, fontSize: 12.5)),
                  const SizedBox(height: 8),
                  _Chip('${p['status'] ?? 'ACTIVE'}'),
                ]),
              ),
              const SizedBox(height: 22),
              _group('Contact', [
                _row(Icons.phone_outlined, 'Mobile', '${p['mobileNumber'] ?? '—'}'),
                _row(Icons.email_outlined, 'Email', '${p['email'] ?? '—'}'),
                _row(Icons.wc_outlined, 'Gender', '${p['gender'] ?? '—'}'),
                _row(Icons.contact_emergency_outlined, 'Emergency contact',
                    '${p['emergencyContactName'] ?? '—'}${p['emergencyContactMobile'] != null ? ' • ${p['emergencyContactMobile']}' : ''}'),
              ]),
              const SizedBox(height: 14),
              _group('Stay', [
                _row(Icons.home_work_outlined, 'Property', '${p['propertyName'] ?? '—'}'),
                _row(Icons.meeting_room_outlined, 'Room', '${p['roomName'] ?? '—'}'),
                _row(Icons.bed_outlined, 'Bed', '${p['bedName'] ?? '—'}'),
                _row(Icons.login_outlined, 'Joining date', _date(p['joiningDate'])),
                _row(Icons.event_available_outlined, 'Agreement', '${_date(p['agreementStart'])} → ${_date(p['agreementEnd'])}'),
              ]),
              const SizedBox(height: 14),
              _group('Financials', [
                _row(Icons.payments_outlined, 'Monthly rent', _money(p['monthlyRent'] ?? 0)),
                _row(Icons.savings_outlined, 'Security deposit', _money(p['securityDeposit'] ?? 0)),
              ]),
              const SizedBox(height: 22),
              OutlinedButton.icon(
                onPressed: () => context.push('/tenant/change-password'),
                icon: const Icon(Icons.lock_outline_rounded),
                label: const Text('Change password'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: TenantColors.primary,
                  minimumSize: const Size(double.infinity, 50),
                  side: const BorderSide(color: TenantColors.primary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _group(String title, List<Widget> rows) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: TenantColors.primary)),
            ),
            ...rows,
          ]),
        ),
      );

  Widget _row(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 19, color: TenantColors.textTertiary),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: TenantColors.textSecondary, fontSize: 13)),
          const Spacer(),
          Flexible(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: TenantColors.ink))),
        ]),
      );
}

// ═══════════════════════════════ Payments ═══════════════════════════════════

class TenantPaymentsScreen extends StatefulWidget {
  const TenantPaymentsScreen({super.key});
  @override
  State<TenantPaymentsScreen> createState() => _TenantPaymentsScreenState();
}

class _TenantPaymentsScreenState extends State<TenantPaymentsScreen> {
  late Future<Map<String, dynamic>> _future;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _future = context.read<AppState>().apiClient.get('/tenant/payments');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payments', style: TextStyle(fontWeight: FontWeight.w700))),
      body: TenantData<Map<String, dynamic>>(
        future: _future,
        onRetry: _load,
        builder: (d) {
          final history = ((d['history'] as List?) ?? []).cast<Map<String, dynamic>>();
          final invoices = ((d['invoices'] as List?) ?? []).cast<Map<String, dynamic>>();
          final due = d['outstandingAmount'];
          final hasDue = (due is num ? due : num.tryParse('$due') ?? 0) > 0;
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
            children: [
              Row(children: [
                Expanded(child: _tile('Monthly Rent', _money(d['monthlyRent'] ?? 0), TenantColors.primary)),
                const SizedBox(width: 12),
                Expanded(child: _tile('Deposit', _money(d['securityDeposit'] ?? 0), TenantColors.info)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _tile('Outstanding', _money(due ?? 0), hasDue ? TenantColors.danger : TenantColors.success)),
                const SizedBox(width: 12),
                Expanded(child: _tile('Paid to date', _money(d['paidAmount'] ?? 0), TenantColors.success)),
              ]),
              if (hasDue && d['dueDate'] != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: TenantColors.danger.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: TenantColors.danger.withValues(alpha: 0.2)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.event_busy_outlined, color: TenantColors.danger, size: 18),
                    const SizedBox(width: 10),
                    Text('Payment due by ${_date(d['dueDate'])}',
                        style: const TextStyle(color: TenantColors.danger, fontWeight: FontWeight.w600, fontSize: 13)),
                  ]),
                ),
              ],
              const SizedBox(height: 22),
              Row(children: [
                const Text('Payment History', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: TenantColors.ink)),
                const Spacer(),
                if (history.isNotEmpty)
                  TextButton(onPressed: () => context.push('/tenant/payments/history', extra: history), child: const Text('View all')),
              ]),
              const SizedBox(height: 8),
              if (history.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: TenantEmpty(icon: Icons.receipt_long_outlined, message: 'No payments yet'))
              else
                ...history.take(4).map((p) => _PaymentTile(payment: p)),
              const SizedBox(height: 16),
              _futureNote(invoices),
            ],
          );
        },
      ),
    );
  }

  Widget _futureNote(List<Map<String, dynamic>> invoices) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: TenantColors.primarySoft, borderRadius: BorderRadius.circular(12)),
        child: const Row(children: [
          Icon(Icons.info_outline_rounded, size: 18, color: TenantColors.primary),
          SizedBox(width: 10),
          Expanded(child: Text('Online payment & receipt download are coming soon.',
              style: TextStyle(fontSize: 12.5, color: TenantColors.ink))),
        ]),
      );

  Widget _tile(String label, String value, Color color) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: TenantColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: TenantColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: color)),
        ]),
      );
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.payment});
  final Map<String, dynamic> payment;
  @override
  Widget build(BuildContext context) {
    final status = '${payment['status'] ?? 'RECEIVED'}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const CircleAvatar(backgroundColor: TenantColors.primarySoft, child: Icon(Icons.payments_outlined, color: TenantColors.primary, size: 20)),
        title: Text(_money(payment['amount']), style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${_date(payment['payment_date'])} • ${payment['payment_mode'] ?? '—'}', style: const TextStyle(fontSize: 12)),
        trailing: _Chip(status, color: status == 'RECEIVED' ? TenantColors.success : null),
      ),
    );
  }
}

class TenantPaymentHistoryScreen extends StatelessWidget {
  const TenantPaymentHistoryScreen({super.key, required this.history});
  final List<Map<String, dynamic>> history;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payment History', style: TextStyle(fontWeight: FontWeight.w700))),
      body: history.isEmpty
          ? const TenantEmpty(icon: Icons.receipt_long_outlined, message: 'No payments yet')
          : ListView(
              padding: const EdgeInsets.all(18),
              children: history.map((p) => _PaymentTile(payment: p)).toList(),
            ),
    );
  }
}

// ═══════════════════════════════ Complaints ═════════════════════════════════

class TenantComplaintsScreen extends StatefulWidget {
  const TenantComplaintsScreen({super.key});
  @override
  State<TenantComplaintsScreen> createState() => _TenantComplaintsScreenState();
}

class _TenantComplaintsScreenState extends State<TenantComplaintsScreen> {
  late Future<Map<String, dynamic>> _future;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _future = context.read<AppState>().apiClient.get('/tenant/complaints');
    });
  }

  Future<void> _raise() async {
    final created = await context.push<bool>('/tenant/complaints/new');
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complaints', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          TextButton.icon(onPressed: _raise, icon: const Icon(Icons.add_rounded), label: const Text('Raise')),
        ],
      ),
      body: TenantData<Map<String, dynamic>>(
        future: _future,
        onRetry: _load,
        builder: (d) {
          final items = ((d['items'] as List?) ?? []).cast<Map<String, dynamic>>();
          if (items.isEmpty) {
            return TenantEmpty(
              icon: Icons.support_agent_rounded,
              message: 'No complaints yet',
              hint: 'Tap "Raise" to report an issue.',
            );
          }
          return RefreshIndicator(
            color: TenantColors.primary,
            onRefresh: () async => _load(),
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: items.map((c) => Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      onTap: () => context.push('/tenant/complaints/${c['complaintId']}'),
                      title: Text('${c['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${_pretty('${c['category']}')} • ${_date(c['createdAt'])}', style: const TextStyle(fontSize: 12)),
                      trailing: _Chip('${c['status']}'),
                    ),
                  )).toList(),
            ),
          );
        },
      ),
    );
  }
}

class TenantRaiseComplaintScreen extends StatefulWidget {
  const TenantRaiseComplaintScreen({super.key});
  @override
  State<TenantRaiseComplaintScreen> createState() => _TenantRaiseComplaintScreenState();
}

class _TenantRaiseComplaintScreenState extends State<TenantRaiseComplaintScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String _category = 'ELECTRICAL';
  String _priority = 'MEDIUM';
  bool _busy = false;

  static const _categories = ['ELECTRICAL', 'PLUMBING', 'CLEANING', 'FURNITURE', 'INTERNET', 'FOOD', 'SECURITY', 'OTHER'];
  static const _priorities = ['LOW', 'MEDIUM', 'HIGH'];

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<AppState>().apiClient.post('/tenant/complaints', {
        'category': _category,
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        'priority': _priority,
      });
      if (mounted) {
        AppToast.success(context, 'Complaint submitted');
        context.pop(true);
      }
    } catch (e) {
      setState(() => _busy = false);
      if (mounted) AppToast.error(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Raise Complaint', style: TextStyle(fontWeight: FontWeight.w700))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Category', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: TenantColors.ink)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _category,
              items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(_pretty(c)))).toList(),
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            const SizedBox(height: 16),
            const Text('Title', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: TenantColors.ink)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(hintText: 'Short summary'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            const Text('Priority', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: TenantColors.ink)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: _priorities.map((p) => ButtonSegment(value: p, label: Text(_pretty(p)))).toList(),
              selected: {_priority},
              onSelectionChanged: (s) => setState(() => _priority = s.first),
            ),
            const SizedBox(height: 16),
            const Text('Description', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: TenantColors.ink)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _description,
              maxLines: 5,
              decoration: const InputDecoration(hintText: 'Describe the issue in detail'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Submit complaint'),
            ),
          ]),
        ),
      ),
    );
  }
}

class TenantComplaintDetailScreen extends StatefulWidget {
  const TenantComplaintDetailScreen({super.key, required this.complaintId});
  final String complaintId;
  @override
  State<TenantComplaintDetailScreen> createState() => _TenantComplaintDetailScreenState();
}

class _TenantComplaintDetailScreenState extends State<TenantComplaintDetailScreen> {
  late Future<Map<String, dynamic>> _future;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _future = context.read<AppState>().apiClient.get('/tenant/complaints/${widget.complaintId}');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Complaint', style: TextStyle(fontWeight: FontWeight.w700))),
      body: TenantData<Map<String, dynamic>>(
        future: _future,
        onRetry: _load,
        builder: (c) {
          final historyList = ((c['history'] as List?) ?? []).cast<Map<String, dynamic>>();
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Row(children: [
                Expanded(child: Text('${c['title']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: TenantColors.ink))),
                _Chip('${c['status']}'),
              ]),
              const SizedBox(height: 6),
              Text('${_pretty('${c['category']}')} • ${_pretty('${c['priority']}')} priority', style: const TextStyle(color: TenantColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 16),
              Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('${c['description']}', style: const TextStyle(fontSize: 14, height: 1.4)))),
              const SizedBox(height: 22),
              const Text('Status Timeline', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: TenantColors.ink)),
              const SizedBox(height: 12),
              ...historyList.asMap().entries.map((e) => _TimelineItem(
                    entry: e.value,
                    isLast: e.key == historyList.length - 1,
                  )),
            ],
          );
        },
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({required this.entry, required this.isLast});
  final Map<String, dynamic> entry;
  final bool isLast;
  @override
  Widget build(BuildContext context) {
    final to = '${entry['toStatus']}';
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [
          Container(width: 14, height: 14, decoration: BoxDecoration(color: _statusColor(to), shape: BoxShape.circle)),
          if (!isLast) Expanded(child: Container(width: 2, color: TenantColors.border)),
        ]),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_pretty(to), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: TenantColors.ink)),
              const SizedBox(height: 2),
              Text(_date(entry['createdAt']), style: const TextStyle(color: TenantColors.textTertiary, fontSize: 12)),
              if (entry['note'] != null && '${entry['note']}'.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('${entry['note']}', style: const TextStyle(color: TenantColors.textSecondary, fontSize: 13)),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════ Notices ════════════════════════════════════

class TenantNoticesScreen extends StatefulWidget {
  const TenantNoticesScreen({super.key});
  @override
  State<TenantNoticesScreen> createState() => _TenantNoticesScreenState();
}

class _TenantNoticesScreenState extends State<TenantNoticesScreen> {
  late Future<Map<String, dynamic>> _future;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _future = context.read<AppState>().apiClient.get('/tenant/notices');
    });
  }

  IconData _icon(String type) {
    switch (type) {
      case 'RENT_REMINDER':
        return Icons.payments_outlined;
      case 'MAINTENANCE':
        return Icons.build_outlined;
      case 'WATER_SHUTDOWN':
        return Icons.water_drop_outlined;
      case 'POWER_SHUTDOWN':
        return Icons.bolt_outlined;
      default:
        return Icons.campaign_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notices', style: TextStyle(fontWeight: FontWeight.w700))),
      body: TenantData<Map<String, dynamic>>(
        future: _future,
        onRetry: _load,
        builder: (d) {
          final items = ((d['items'] as List?) ?? []).cast<Map<String, dynamic>>();
          if (items.isEmpty) {
            return const TenantEmpty(icon: Icons.campaign_outlined, message: 'No notices');
          }
          return RefreshIndicator(
            color: TenantColors.primary,
            onRefresh: () async => _load(),
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: items.map((n) {
                final unread = n['read_flag'] != true;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    onTap: () async {
                      await context.push('/tenant/notices/${n['notice_id']}');
                      _load();
                    },
                    leading: CircleAvatar(
                      backgroundColor: TenantColors.primarySoft,
                      child: Icon(_icon('${n['notice_type']}'), color: TenantColors.primary, size: 20),
                    ),
                    title: Text('${n['title']}',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w600)),
                    subtitle: Text('${_pretty('${n['notice_type']}')} • ${_date(n['published_at'])}', style: const TextStyle(fontSize: 12)),
                    trailing: unread
                        ? Container(width: 10, height: 10, decoration: const BoxDecoration(color: TenantColors.primary, shape: BoxShape.circle))
                        : const Icon(Icons.chevron_right_rounded, color: TenantColors.textTertiary),
                  ),
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }
}

class TenantNoticeDetailScreen extends StatefulWidget {
  const TenantNoticeDetailScreen({super.key, required this.noticeId});
  final String noticeId;
  @override
  State<TenantNoticeDetailScreen> createState() => _TenantNoticeDetailScreenState();
}

class _TenantNoticeDetailScreenState extends State<TenantNoticeDetailScreen> {
  late Future<Map<String, dynamic>> _future;
  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().apiClient.get('/tenant/notices/${widget.noticeId}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notice', style: TextStyle(fontWeight: FontWeight.w700))),
      body: TenantData<Map<String, dynamic>>(
        future: _future,
        builder: (n) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _Chip('${n['noticeType']}'),
            const SizedBox(height: 12),
            Text('${n['title']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: TenantColors.ink)),
            const SizedBox(height: 6),
            Text(_date(n['publishedAt']), style: const TextStyle(color: TenantColors.textTertiary, fontSize: 12.5)),
            const SizedBox(height: 20),
            Text('${n['body']}', style: const TextStyle(fontSize: 15, height: 1.5, color: TenantColors.ink)),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════ Notifications ══════════════════════════════

class TenantNotificationsScreen extends StatefulWidget {
  const TenantNotificationsScreen({super.key});
  @override
  State<TenantNotificationsScreen> createState() => _TenantNotificationsScreenState();
}

class _TenantNotificationsScreenState extends State<TenantNotificationsScreen> {
  late Future<Map<String, dynamic>> _future;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _future = context.read<AppState>().apiClient.get('/tenant/notifications');
    });
  }

  IconData _icon(String category) {
    switch (category) {
      case 'RENT_REMINDER':
        return Icons.payments_outlined;
      case 'COMPLAINT':
        return Icons.support_agent_rounded;
      case 'NOTICE':
        return Icons.campaign_outlined;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.w700))),
      body: TenantData<Map<String, dynamic>>(
        future: _future,
        onRetry: _load,
        builder: (d) {
          final items = ((d['items'] as List?) ?? []).cast<Map<String, dynamic>>();
          if (items.isEmpty) {
            return const TenantEmpty(icon: Icons.notifications_none_rounded, message: 'No notifications');
          }
          return ListView(
            padding: const EdgeInsets.all(18),
            children: items.map((n) {
              final unread = n['read_at'] == null;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                color: unread ? TenantColors.primarySoft.withValues(alpha: 0.5) : Colors.white,
                child: ListTile(
                  onTap: () async {
                    if (unread) {
                      await context.read<AppState>().apiClient.post('/tenant/notifications/${n['notification_id']}/read', {});
                      _load();
                    }
                  },
                  leading: CircleAvatar(backgroundColor: TenantColors.primarySoft, child: Icon(_icon('${n['category_id']}'), color: TenantColors.primary, size: 20)),
                  title: Text('${n['title']}', style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w600, fontSize: 14)),
                  subtitle: Text('${n['message']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
                  trailing: Text(_date(n['created_at']), style: const TextStyle(fontSize: 11, color: TenantColors.textTertiary)),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

// ═══════════════════ Standalone status screens ══════════════════════════════

class SessionExpiredScreen extends StatelessWidget {
  const SessionExpiredScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.timer_off_outlined, size: 64, color: TenantColors.textTertiary),
            const SizedBox(height: 18),
            const Text('Session expired', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: TenantColors.ink)),
            const SizedBox(height: 6),
            const Text('Please sign in again to continue.', style: TextStyle(color: TenantColors.textSecondary)),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () async {
                await context.read<AppState>().logout();
                if (context.mounted) context.go('/login');
              },
              child: const Text('Sign in'),
            ),
          ]),
        ),
      ),
    );
  }
}
