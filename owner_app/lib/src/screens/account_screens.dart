export 'admin_screen.dart' show SuperAdminScreen;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/animations.dart';
import '../widgets/app_toast.dart';
import '../widgets/async_action_button.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _usernameCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _sent = false;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: FadeSlideIn(
                child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    IconButton(
                      alignment: Alignment.centerLeft,
                      onPressed: () => context.go('/login'),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    Text(
                      'Forgot Password',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Enter your registered username or mobile number.',
                    ),
                    const SizedBox(height: 24),
                    if (!_sent) ...[
                      TextFormField(
                        controller: _usernameCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Username or mobile number',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      AsyncActionButton(
                        label: 'Send Reset Instructions',
                        onPressed: () async {
                          if (!_formKey.currentState!.validate()) return;
                          try {
                            await context.read<AppState>().apiClient.post(
                              '/auth/password/forgot',
                              {'username': _usernameCtrl.text.trim()},
                            );
                            if (mounted) setState(() => _sent = true);
                          } catch (e) {
                            if (mounted) {
                              AppToast.error(context,
                                  e.toString().replaceFirst('Exception: ', ''));
                            }
                          }
                        },
                      ),
                    ],
                    if (_sent)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Request recorded. Reset instructions will be sent when a delivery provider is configured.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<Map<String, dynamic>> future;
  final name = TextEditingController();
  final mobile = TextEditingController();
  bool seeded = false;

  @override
  void initState() {
    super.initState();
    future = context.read<AppState>().apiClient.get('/account/profile');
  }

  @override
  void dispose() {
    name.dispose();
    mobile.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/settings'),
        ),
        title: const Text('Profile', style: TextStyle(fontWeight: FontWeight.w700)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE5E7EB)),
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!;
          if (!seeded) {
            name.text = '${data['fullName'] ?? ''}';
            mobile.text = '${data['mobileNumber'] ?? ''}';
            seeded = true;
          }
          return FadeSlideIn(
            child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Center(child: CircleAvatar(radius: 42, child: Icon(Icons.person, size: 42))),
              const SizedBox(height: 20),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Full Name')),
              const SizedBox(height: 12),
              TextField(controller: mobile, decoration: const InputDecoration(labelText: 'Mobile Number')),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: '${data['email'] ?? ''}',
                enabled: false,
                decoration: const InputDecoration(labelText: 'Email Address'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: '${data['roleTypeId'] ?? ''}',
                enabled: false,
                decoration: const InputDecoration(labelText: 'Role'),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () async {
                  try {
                    await context.read<AppState>().apiClient.patch(
                      '/account/profile',
                      {'fullName': name.text, 'mobileNumber': mobile.text},
                    );
                    if (context.mounted) {
                      AppToast.success(context, 'Profile updated',
                          title: 'Profile Updated');
                    }
                  } catch (e) {
                    if (context.mounted) {
                      AppToast.error(context,
                          e.toString().replaceFirst('Exception: ', ''));
                    }
                  }
                },
                child: const Text('Save Changes'),
              ),
            ],
          ),
          );
        },
      ),
    );
  }
}

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscureCurrent = true;
  bool _obscureNext = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/settings'),
        ),
        title: const Text('Change Password', style: TextStyle(fontWeight: FontWeight.w700)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE5E7EB)),
        ),
      ),
      body: Form(
        key: _formKey,
        child: FadeSlideIn(
          child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Center(child: Icon(Icons.shield_outlined, size: 72)),
            const SizedBox(height: 18),
            _passwordField(
              _current,
              'Current Password',
              _obscureCurrent,
              () => setState(() => _obscureCurrent = !_obscureCurrent),
              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
            ),
            _passwordField(
              _next,
              'New Password',
              _obscureNext,
              () => setState(() => _obscureNext = !_obscureNext),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Required';
                if (v.length < 8) return 'Minimum 8 characters';
                return null;
              },
            ),
            _passwordField(
              _confirm,
              'Confirm New Password',
              _obscureConfirm,
              () => setState(() => _obscureConfirm = !_obscureConfirm),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Required';
                if (v != _next.text) return 'Passwords do not match';
                return null;
              },
            ),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Use at least 8 characters with uppercase, lowercase, number, and special character.',
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                if (!_formKey.currentState!.validate()) return;
                try {
                  await context.read<AppState>().apiClient.post(
                    '/account/change-password',
                    {
                      'currentPassword': _current.text,
                      'newPassword': _next.text,
                      'confirmPassword': _confirm.text,
                    },
                  );
                  if (context.mounted) {
                    await context.read<AppState>().logout();
                    context.go('/login');
                  }
                } catch (e) {
                  if (context.mounted) {
                    AppToast.error(context,
                        e.toString().replaceFirst('Exception: ', ''));
                  }
                }
              },
              child: const Text('Update Password'),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _passwordField(
    TextEditingController ctrl,
    String label,
    bool obscure,
    VoidCallback onToggle, {
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            onPressed: onToggle,
          ),
        ),
        validator: validator,
      ),
    );
  }
}

// ─── Settings Screen ─────────────────────────────────────────────────────────

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<Map<String, dynamic>> _prefFuture;

  @override
  void initState() {
    super.initState();
    _prefFuture = context.read<AppState>().apiClient.get('/account/preferences');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/dashboard'),
        ),
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w700)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE5E7EB)),
        ),
      ),
      body: FadeSlideIn(
        child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: ListTile(
              leading: const CircleAvatar(
                  backgroundColor: PgColors.lavender,
                  child: Icon(Icons.person, color: PgColors.primary)),
              title: const Text('Profile Information',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Personal and work information'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/settings/profile'),
            ),
          ),
          const SizedBox(height: 8),
          _SettingsGroup(title: 'Account', children: [
            _SettingTile(
                icon: Icons.lock_outline,
                title: 'Change Password',
                onTap: () => context.go('/settings/password')),
            FutureBuilder<String?>(
              future: context.read<AppState>().storage.read(key: 'biometricEnabled'),
              builder: (context, snapshot) => SwitchListTile(
                secondary: const Icon(Icons.fingerprint),
                title: const Text('Biometric & Security'),
                subtitle: const Text('Unlock using device security'),
                value: snapshot.data == 'true',
                onChanged: (value) async {
                  final messenger = ScaffoldMessenger.of(context);
                  final appState = context.read<AppState>();
                  try {
                    await appState.setBiometricEnabled(value);
                    if (!mounted) return;
                    setState(() {});
                    AppToast.successOf(
                        messenger,
                        value
                            ? 'Biometric unlock enabled'
                            : 'Biometric unlock disabled',
                        title: 'Biometric Updated');
                  } catch (e) {
                    AppToast.errorOf(
                        messenger, e.toString().replaceFirst('Exception: ', ''));
                  }
                },
              ),
            ),
          ]),
          _SettingsGroup(title: 'Preferences', children: [
            _SettingTile(
                icon: Icons.notifications_outlined,
                title: 'Notification Settings',
                onTap: () => context.push('/notifications/settings')),
            FutureBuilder<Map<String, dynamic>>(
              future: _prefFuture,
              builder: (context, snapshot) => _SettingTile(
                icon: Icons.palette_outlined,
                title: 'Theme & Appearance',
                subtitle: '${snapshot.data?['theme'] ?? 'LIGHT'}',
              ),
            ),
            const _SettingTile(
                icon: Icons.language, title: 'Language', subtitle: 'English'),
          ]),
          _SettingsGroup(title: 'Billing', children: [
            _SettingTile(
                icon: Icons.receipt_long_outlined,
                title: 'Invoice Automation',
                subtitle: 'Auto-generate monthly invoices',
                onTap: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                      builder: (_) => const _InvoiceAutomationSheet(),
                    )),
          ]),
          // Renders nothing unless the org has Tenant Login switched on.
          const _TenantPortalSettingsGroup(),
          _SettingsGroup(title: 'Data & Storage', children: [
            _SettingTile(
              icon: Icons.delete_outline,
              title: 'Clear Cache',
              onTap: () async {
                final cache = await SharedPreferences.getInstance();
                await cache.clear();
                if (context.mounted) {
                  AppToast.success(context, 'Local cache cleared.',
                      title: 'Cache Cleared');
                }
              },
            ),
          ]),
          const SizedBox(height: 24),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: ListTile(
              leading: const Icon(Icons.logout, color: PgColors.danger),
              title: const Text('Sign Out',
                  style: TextStyle(color: PgColors.danger, fontWeight: FontWeight.w600)),
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Sign Out'),
                    content: const Text('Are you sure you want to sign out?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: PgColors.danger),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Sign Out'),
                      ),
                    ],
                  ),
                );
                if (confirm == true && context.mounted) {
                  await context.read<AppState>().logout();
                  if (context.mounted) context.go('/login');
                }
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
      ),
    );
  }
}

// ─── Notifications Screen ─────────────────────────────────────────────────────

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

  static (IconData, Color) _notifStyle(String category) => switch (category) {
    'RENT_REMINDER'    => (Icons.schedule, Color(0xFFF97316)),
    'CHECKOUT_REMINDER'=> (Icons.logout_outlined, Color(0xFF2563EB)),
    'PAYMENT_RECEIPT'  => (Icons.receipt_long_outlined, Color(0xFF16A34A)),
    'CHECK_IN'         => (Icons.person_add_outlined, Color(0xFF7C3AED)),
    _                  => (Icons.notifications_outlined, PgColors.primary),
  };

  static String _formatTime(Object? raw) {
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw.toString().replaceAll(' ', 'T'));
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24)   return '${diff.inHours}h ago';
      if (diff.inDays < 7)     return '${diff.inDays}d ago';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) { return raw.toString(); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F6FA),
    appBar: AppBar(
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF1A1A2E),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.canPop() ? context.pop() : context.go('/properties'),
      ),
      title: Text(
        filter == 'ARCHIVED' ? 'Archived Notifications' : 'Notifications',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      actions: const [],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: const Color(0xFFE5E7EB)),
      ),
    ),
    body: Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            children: ['ACTIVE', 'UNREAD', 'IMPORTANT', 'ARCHIVED'].map((v) => ChoiceChip(
              label: Text(v.toLowerCase()), selected: filter == v,
              onSelected: (_) => setState(() { filter = v; _load(); }),
            )).toList(),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Expanded(child: FutureBuilder<Map<String, dynamic>>(future: future, builder: (context, snapshot) {
        if (!snapshot.hasData) return snapshot.hasError ? ErrorState(error: snapshot.error, retry: () => setState(_load)) : const Center(child: CircularProgressIndicator());
        final items = snapshot.data!['items'] as List? ?? [];
        if (items.isEmpty) return const EmptyState(icon: Icons.notifications_none, title: 'No notifications', message: 'Updates will appear here.');
        return ListView.separated(padding: const EdgeInsets.all(12), itemCount: items.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (context, index) {
          final item = items[index] as Map<String, dynamic>;
          final category = '${item['category_id'] ?? ''}';
          final isUnread = item['read_at'] == null;
          final isImportant = item['important'] == true || item['important'] == 1;
          final (icon, color) = _notifStyle(category);
          return FadeSlideIn(
            delay: Duration(milliseconds: 40 * (index.clamp(0, 8))),
            child: Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () async {
                if (isUnread) {
                  await context.read<AppState>().apiClient.patch('/notifications/${item['notification_id']}/read', {});
                  setState(_load);
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Stack(children: [
                    Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                      child: Icon(icon, color: color, size: 20),
                    ),
                    if (isUnread) Positioned(right: 0, top: 0, child: Container(
                      width: 10, height: 10,
                      decoration: BoxDecoration(color: PgColors.primary, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
                    )),
                  ]),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text('${item['title']}', style: TextStyle(fontWeight: isUnread ? FontWeight.w700 : FontWeight.w600, fontSize: 13, color: const Color(0xFF111827)))),
                      if (isImportant) const Icon(Icons.priority_high, size: 14, color: PgColors.danger),
                    ]),
                    const SizedBox(height: 3),
                    Text('${item['message']}', style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(_formatTime(item['created_at']), style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                  ])),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 18, color: Color(0xFF9CA3AF)),
                    onSelected: (action) async {
                      final id = item['notification_id'];
                      await context.read<AppState>().apiClient.patch('/notifications/$id/${action == 'read' ? 'read' : 'archive'}', {});
                      setState(_load);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'read', child: Text('Mark as read')),
                      PopupMenuItem(value: 'archive', child: Text('Archive')),
                    ],
                  ),
                ]),
              ),
            ),
          ),
          );
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
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F6FA),
    appBar: AppBar(
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF1A1A2E),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.canPop() ? context.pop() : context.go('/notifications'),
      ),
      title: const Text('Notification Settings', style: TextStyle(fontWeight: FontWeight.w700)),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: const Color(0xFFE5E7EB)),
      ),
    ),
    body: FutureBuilder<Map<String, dynamic>>(future: future, builder: (context, snapshot) {
      final items = snapshot.data?['items'] as List?;
      if (items == null) return const Center(child: CircularProgressIndicator());
      return FadeSlideIn(child: ListView(padding: const EdgeInsets.all(12), children: items.map((raw) {
        final item = raw as Map<String, dynamic>;
        final enabled = item['enabled'] == true || item['enabled'] == 1;
        return Card(child: SwitchListTile(value: enabled, title: Text('${item['name']}', style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text('${item['description'] ?? ''}'), onChanged: (value) async {
          await context.read<AppState>().apiClient.patch('/notifications/preferences', {'${item['category_id']}': value});
          if (!context.mounted) return;
          // Block body: an arrow closure here would return the Future and trip
          // setState's debug assert before the rebuild is scheduled.
          setState(() { future = context.read<AppState>().apiClient.get('/notifications/preferences'); });
        }));
      }).toList()));
    }),
  );
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────

class MetricCard extends StatelessWidget {
  const MetricCard({required this.label, required this.value, required this.icon, required this.color, super.key});
  final String label; final Object? value; final IconData icon; final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(width: 210, child: Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
    CircleAvatar(backgroundColor: color.withValues(alpha: .1), foregroundColor: color, child: Icon(icon)), const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 6),
      Text('${value ?? '—'}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
    ])),
  ]))));
}

class RecordList extends StatelessWidget {
  const RecordList({required this.items, super.key}); final List items;
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const EmptyState(icon: Icons.inbox_outlined, title: 'No records yet', message: 'Create your first record to get started.');
    return ListView.separated(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length, separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (_, index) {
        final raw = items[index]; final map = raw is Map ? raw : {'value': raw};
        final title = map['facilityName'] ?? map['facility_name'] ?? map['fullName'] ?? map['full_name'] ?? map['name'] ?? map['title'] ?? 'Record ${index + 1}';
        final subtitle = map.entries.where((e) => !['facilityName','facility_name','fullName','full_name','name','title'].contains(e.key)).take(3).map((e) => '${e.key}: ${e.value}').join('  •  ');
        return ListTile(
          leading: const CircleAvatar(backgroundColor: PgColors.lavender, child: Icon(Icons.business_outlined, color: PgColors.primary)),
          title: Text('$title', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
        );
      },
    );
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
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.cloud_off, size: 48, color: PgColors.danger),
    const SizedBox(height: 12),
    const Text('Could not load data', style: TextStyle(fontWeight: FontWeight.w700)),
    const SizedBox(height: 6),
    Text('$error', textAlign: TextAlign.center),
    const SizedBox(height: 12),
    OutlinedButton(onPressed: retry, child: const Text('Try again')),
  ]));
}

class EmptyState extends StatelessWidget {
  const EmptyState({required this.icon, required this.title, required this.message, super.key}); final IconData icon; final String title; final String message;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(30), child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 52, color: PgColors.primary), const SizedBox(height: 12), Text(title, style: const TextStyle(fontWeight: FontWeight.w700)), Text(message, textAlign: TextAlign.center),
  ])));
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children}); final String title; final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(color: PgColors.primary, fontWeight: FontWeight.w700, fontSize: 12)),
      const SizedBox(height: 6),
      Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), child: Column(children: children)),
    ]),
  );
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({required this.icon, required this.title, this.subtitle, this.onTap}); final IconData icon; final String title; final String? subtitle; final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListTile(leading: Icon(icon), title: Text(title), subtitle: subtitle == null ? null : Text(subtitle!), trailing: onTap == null ? null : const Icon(Icons.chevron_right), onTap: onTap);
}

/// Tenant-portal settings. Tenant Login is opt-in per organization (super-admin
/// controlled), so the whole group stays hidden until `GET /tenants/login-feature`
/// reports it enabled — that keeps a feature the org cannot use out of Settings.
class _TenantPortalSettingsGroup extends StatefulWidget {
  const _TenantPortalSettingsGroup();

  @override
  State<_TenantPortalSettingsGroup> createState() => _TenantPortalSettingsGroupState();
}

class _TenantPortalSettingsGroupState extends State<_TenantPortalSettingsGroup> {
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    _checkFeature();
  }

  Future<void> _checkFeature() async {
    try {
      final data = await context.read<AppState>().apiClient.get('/tenants/login-feature');
      if (mounted) setState(() => _enabled = data['enabled'] == true);
    } catch (_) {
      // Feature probe is best-effort — on failure the group simply stays hidden.
    }
  }

  Widget _summaryRow(String label, dynamic value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label),
          Text('${value ?? 0}', style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );

  Future<void> _generateLogins() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Generate Tenant Logins'),
        content: const Text(
            'Create login accounts for tenants who don’t have one yet. '
            'Inactive, deleted and checked-out tenants are skipped. '
            'Each new login gets the temporary password abc@123.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Generate')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      final res = await context.read<AppState>().apiClient.post('/tenants/generate-logins', {});
      if (!mounted) return;
      Navigator.pop(context); // dismiss spinner
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Generation Complete'),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _summaryRow('Created', res['created']),
                _summaryRow('Already had login', res['skippedExisting']),
                _summaryRow('Skipped (inactive)', res['skippedInactive']),
                _summaryRow('Skipped (checked out)', res['skippedCheckedOut']),
                _summaryRow('Skipped (deleted)', res['skippedArchived']),
                const Divider(),
                _summaryRow('Total tenants', res['total']),
              ]),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      AppToast.error(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return const SizedBox.shrink();
    return _SettingsGroup(title: 'Tenant Portal', children: [
      _SettingTile(
        icon: Icons.key_outlined,
        title: 'Generate Tenant Logins',
        subtitle: 'Create portal logins for tenants without one',
        onTap: _generateLogins,
      ),
    ]);
  }
}

/// Per-organization invoice automation config (backed by GET/PUT /billing/config).
/// Controls whether invoices auto-generate daily and how many days before the tenant's
/// billing anniversary (their move-in day-of-month) each invoice is raised.
class _InvoiceAutomationSheet extends StatefulWidget {
  const _InvoiceAutomationSheet();
  @override
  State<_InvoiceAutomationSheet> createState() => _InvoiceAutomationSheetState();
}

class _InvoiceAutomationSheetState extends State<_InvoiceAutomationSheet> {
  bool _loading = true;
  bool _saving = false;
  Object? _error;
  bool _autoEnabled = true;
  int _leadDays = 1;
  int _minLeadDays = 0;
  int _maxLeadDays = 28;
  int _graceDays = 2;
  int _minGraceDays = 0;
  int _maxGraceDays = 28;

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
      final data = await context.read<AppState>().apiClient.get('/billing/config');
      if (!mounted) return;
      setState(() {
        _autoEnabled = data['autoGenerateEnabled'] == true;
        _leadDays = (data['invoiceLeadDays'] as num?)?.toInt() ?? 1;
        _minLeadDays = (data['minLeadDays'] as num?)?.toInt() ?? 0;
        _maxLeadDays = (data['maxLeadDays'] as num?)?.toInt() ?? 28;
        _graceDays = (data['checkoutGraceDays'] as num?)?.toInt() ?? 2;
        _minGraceDays = (data['minGraceDays'] as num?)?.toInt() ?? 0;
        _maxGraceDays = (data['maxGraceDays'] as num?)?.toInt() ?? 28;
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

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await context.read<AppState>().apiClient.put('/billing/config', {
        'invoiceLeadDays': _leadDays,
        'checkoutGraceDays': _graceDays,
        'autoGenerateEnabled': _autoEnabled,
      });
      if (!mounted) return;
      navigator.pop();
      AppToast.successOf(messenger, 'Invoice automation settings saved',
          title: 'Billing Updated');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.errorOf(messenger, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// Labelled −/+ stepper shared by the lead-days and grace-days settings.
  Widget _dayStepper({
    required String title,
    required String description,
    required String valueLabel,
    required VoidCallback? onMinus,
    required VoidCallback? onPlus,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text(description, style: const TextStyle(color: Colors.black54, fontSize: 13)),
      const SizedBox(height: 12),
      Row(children: [
        IconButton.filledTonal(onPressed: onMinus, icon: const Icon(Icons.remove)),
        Expanded(
          child: Center(
            child: Text(valueLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
        ),
        IconButton.filledTonal(onPressed: onPlus, icon: const Icon(Icons.add)),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      // Two steppers plus the toggle can outgrow a short screen — keep it scrollable.
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.receipt_long, color: PgColors.primary),
          const SizedBox(width: 10),
          const Expanded(
              child: Text('Invoice Automation',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18))),
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
        ]),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
        else if (_error != null)
          Padding(padding: const EdgeInsets.symmetric(vertical: 24),
              child: ErrorState(error: _error, retry: _load))
        else ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _autoEnabled,
            onChanged: _saving ? null : (v) => setState(() => _autoEnabled = v),
            title: const Text('Auto-generate invoices',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text(
                'Runs daily at 1:00 AM. Each tenant is invoiced ahead of their billing date. '
                'You can still generate invoices manually anytime.'),
          ),
          const Divider(height: 24),
          Opacity(
            opacity: _autoEnabled ? 1 : 0.4,
            child: _dayStepper(
              title: 'Generate invoices in advance',
              description:
                  'How many days before the due date to raise the invoice ($_minLeadDays–$_maxLeadDays).',
              valueLabel: _leadDays == 0
                  ? 'On the due date'
                  : '$_leadDays day${_leadDays == 1 ? '' : 's'} before',
              onMinus: (!_autoEnabled || _saving || _leadDays <= _minLeadDays)
                  ? null : () => setState(() => _leadDays--),
              onPlus: (!_autoEnabled || _saving || _leadDays >= _maxLeadDays)
                  ? null : () => setState(() => _leadDays++),
            ),
          ),
          const Divider(height: 24),
          // Applies however the invoice was raised (scheduler or manual), so it is not
          // dimmed with the automation toggle.
          _dayStepper(
            title: 'Checkout grace after the due date',
            description:
                'A tenant checking out within this many days of the due date has that '
                'invoice deleted instead of being asked to pay or write it off '
                '($_minGraceDays–$_maxGraceDays). Invoices with a payment already collected '
                'are always kept.',
            valueLabel: _graceDays == 0
                ? 'Up to the due date'
                : '$_graceDays day${_graceDays == 1 ? '' : 's'} after',
            onMinus: (_saving || _graceDays <= _minGraceDays)
                ? null : () => setState(() => _graceDays--),
            onPlus: (_saving || _graceDays >= _maxGraceDays)
                ? null : () => setState(() => _graceDays++),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save'),
            ),
          ),
        ],
      ]),
      ),
    );
  }
}
