import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_shell.dart';
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
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    e.toString().replaceFirst('Exception: ', ''),
                                  ),
                                ),
                              );
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
          return ListView(
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Profile updated')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
                      );
                    }
                  }
                },
                child: const Text('Save Changes'),
              ),
            ],
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
                    );
                  }
                }
              },
              child: const Text('Update Password'),
            ),
          ],
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
      body: ListView(
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
                  await context.read<AppState>().setBiometricEnabled(value);
                  if (mounted) setState(() {});
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
          _SettingsGroup(title: 'Data & Storage', children: [
            _SettingTile(
              icon: Icons.delete_outline,
              title: 'Clear Cache',
              onTap: () async {
                final cache = await SharedPreferences.getInstance();
                await cache.clear();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Local cache cleared.')));
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
          return Card(child: ListTile(
            leading: const CircleAvatar(backgroundColor: PgColors.lavender, child: Icon(Icons.notifications_outlined, color: PgColors.primary)),
            title: Text('${item['title']}', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${item['message']}'),
            trailing: PopupMenuButton<String>(onSelected: (action) async {
              final id = item['notification_id'];
              await context.read<AppState>().apiClient.patch('/notifications/$id/${action == 'read' ? 'read' : 'archive'}', {});
              setState(_load);
            }, itemBuilder: (_) => const [
              PopupMenuItem(value: 'read', child: Text('Mark as read')),
              PopupMenuItem(value: 'archive', child: Text('Archive')),
            ]),
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
      return ListView(padding: const EdgeInsets.all(12), children: items.map((raw) {
        final item = raw as Map<String, dynamic>;
        final enabled = item['enabled'] == true || item['enabled'] == 1;
        return Card(child: SwitchListTile(value: enabled, title: Text('${item['name']}', style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text('${item['description'] ?? ''}'), onChanged: (value) async {
          await context.read<AppState>().apiClient.patch('/notifications/preferences', {'${item['category_id']}': value});
          setState(() => future = context.read<AppState>().apiClient.get('/notifications/preferences'));
        }));
      }).toList());
    }),
  );
}

// ─── Super Admin Screen ───────────────────────────────────────────────────────

class SuperAdminScreen extends StatefulWidget {
  const SuperAdminScreen({super.key});
  @override
  State<SuperAdminScreen> createState() => _SuperAdminScreenState();
}
class _SuperAdminScreenState extends State<SuperAdminScreen> {
  int selected = 0;
  static const sections = [
    ('Dashboard', '/super-admin/dashboard', Icons.dashboard_outlined),
    ('Properties', '/super-admin/properties', Icons.apartment_outlined),
    ('Customers', '/super-admin/organizations', Icons.business_outlined),
    ('Users', '/super-admin/users', Icons.people_outline),
    ('Plans & Pricing', '/super-admin/plans', Icons.sell_outlined),
    ('Reports', '/super-admin/reports/revenue', Icons.bar_chart),
    ('Audit Logs', '/super-admin/audit-logs', Icons.history),
    ('System Settings', '/super-admin/system-settings', Icons.settings_outlined),
  ];
  @override
  Widget build(BuildContext context) {
    final section = sections[selected];
    return AppShell(title: section.$1, child: Row(children: [
      NavigationRail(
        selectedIndex: selected,
        labelType: NavigationRailLabelType.none,
        onDestinationSelected: (value) => setState(() => selected = value),
        destinations: sections.map((s) => NavigationRailDestination(icon: Icon(s.$3), label: Text(s.$1))).toList(),
      ),
      const VerticalDivider(width: 1),
      Expanded(child: Padding(padding: const EdgeInsets.only(left: 20), child: FutureBuilder<Map<String, dynamic>>(
        key: ValueKey(selected),
        future: context.read<AppState>().apiClient.get(section.$2),
        builder: (context, snapshot) {
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
