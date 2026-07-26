import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/error_retry_view.dart';

/// Property-scoped staff logins: create one, choose which properties it can reach,
/// deactivate it, reset its password.
///
/// This is the answer to "one owner, many properties": each manager gets a login
/// that can only see and act on the properties assigned here. The restriction is
/// enforced entirely server-side by `PropertyAccessGuard` — this screen only
/// decides the assignment, it is not the security boundary.
///
/// Owner-only: every endpoint under `/api/managers` is guarded to OWNER, because a
/// manager who could edit assignments could grant themselves the properties they
/// were denied.
class ManagersScreen extends StatefulWidget {
  const ManagersScreen({super.key});

  @override
  State<ManagersScreen> createState() => _ManagersScreenState();
}

class _ManagersScreenState extends State<ManagersScreen> {
  List<Map<String, dynamic>> _managers = [];
  List<Map<String, dynamic>> _properties = [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AppState>().apiClient;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final managers = await api.get('/managers');
      final tree = await api.get('/facilities/tree');
      if (!mounted) return;
      setState(() {
        _managers = (managers['items'] as List? ?? []).cast<Map<String, dynamic>>();
        _properties = _propertiesFromTree(tree);
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

  /// The org's direct children in the facility tree are its properties. Reusing the
  /// tree avoids a second endpoint, and it is already the app's source of truth for
  /// "which properties exist".
  List<Map<String, dynamic>> _propertiesFromTree(Map<String, dynamic> tree) {
    final children = (tree['children'] as List? ?? const []);
    return [
      for (final c in children)
        if ('${(c as Map)['facilityTypeId'] ?? ''}' == 'PROPERTY')
          {
            'propertyId': c['facilityId'],
            'propertyName': c['facilityName'] ?? 'Property',
          },
    ];
  }

  Future<void> _openForm({Map<String, dynamic>? manager}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ManagerFormSheet(properties: _properties, manager: manager),
    );
    if (saved == true) await _load();
  }

  Future<void> _setStatus(Map<String, dynamic> manager, bool active) async {
    final api = context.read<AppState>().apiClient;
    try {
      await api.patch('/managers/${manager['user_login_id']}/status', {'active': active});
      if (!mounted) return;
      AppToast.success(context, active ? 'Login activated' : 'Login deactivated');
      await _load();
    } catch (e) {
      if (mounted) AppToast.error(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _resetPassword(Map<String, dynamic> manager) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Password'),
        content: Text(
            'Reset the password for ${manager['full_name'] ?? manager['username']}? '
            'They will be signed out everywhere and must set a new password on next sign-in.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final api = context.read<AppState>().apiClient;
    try {
      final res = await api.post('/managers/${manager['user_login_id']}/reset-password', {});
      if (!mounted) return;
      await _showCredentials(
        title: 'Password Reset',
        loginId: '${manager['mobile_number'] ?? manager['username']}',
        password: '${res['temporaryPassword']}',
      );
    } catch (e) {
      if (mounted) AppToast.error(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// The temporary password is only knowable at this moment — only its hash is
  /// stored — so it gets a dialog the owner has to dismiss, not a toast.
  Future<void> _showCredentials({
    required String title,
    required String loginId,
    required String password,
  }) =>
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Share these with the manager. The password is shown only once.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
              const SizedBox(height: 14),
              _CredentialRow(label: 'Sign in with', value: loginId),
              const SizedBox(height: 8),
              _CredentialRow(label: 'Temporary password', value: password),
              const SizedBox(height: 12),
              const Text('They must change it when they first sign in.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
            ],
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Managers', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Add manager',
            icon: const Icon(Icons.person_add_alt_1),
            onPressed: _loading ? null : () => _openForm(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetryView(error: _error!, onRetry: _load)
              : _managers.isEmpty
                  ? _emptyState()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _managers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _managerCard(_managers[i]),
                      ),
                    ),
    );
  }

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.badge_outlined, size: 44, color: Color(0xFF9CA3AF)),
              const SizedBox(height: 12),
              const Text('No manager logins yet',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 6),
              Text(
                'Give one person one property. A manager only sees the properties you assign — '
                'everything else in the organization stays hidden.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => _openForm(),
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                label: const Text('Add Manager'),
              ),
            ],
          ),
        ),
      );

  Widget _managerCard(Map<String, dynamic> m) {
    final active = '${m['status'] ?? 'ACTIVE'}' == 'ACTIVE';
    final properties = (m['properties'] as List? ?? const []).cast<Map<String, dynamic>>();
    final name = '${m['full_name'] ?? m['username'] ?? '—'}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: active ? PgColors.lavender : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(
                        color: active ? PgColors.primary : const Color(0xFF9CA3AF),
                        fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 2),
                // Their sign-in id. The stored username carries an org suffix that is an
                // implementation detail, so showing it here would just confuse the owner.
                Text('${m['mobile_number'] ?? m['username']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: Color(0xFF6B7280))),
              ]),
            ),
            if (!active)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('INACTIVE',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF6B7280))),
              ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 18, color: Color(0xFF9CA3AF)),
              onSelected: (v) {
                if (v == 'edit') _openForm(manager: m);
                if (v == 'reset') _resetPassword(m);
                if (v == 'toggle') _setStatus(m, !active);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit properties')),
                const PopupMenuItem(value: 'reset', child: Text('Reset password')),
                PopupMenuItem(
                  value: 'toggle',
                  child: Text(active ? 'Deactivate login' : 'Activate login'),
                ),
              ],
            ),
          ]),
          const SizedBox(height: 10),
          if (properties.isEmpty)
            // Worth calling out: an unassigned login can sign in but sees nothing,
            // which looks like a broken app rather than a configuration gap.
            Row(children: const [
              Icon(Icons.warning_amber_rounded, size: 15, color: PgColors.warning),
              SizedBox(width: 6),
              Expanded(
                child: Text('No properties assigned — this login can sign in but will see nothing.',
                    style: TextStyle(fontSize: 11.5, color: PgColors.warning)),
              ),
            ])
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in properties)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: PgColors.lavender,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('${p['propertyName']}',
                        style: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w600, color: PgColors.primary)),
                  ),
              ],
            ),
        ]),
      ),
    );
  }
}

class _CredentialRow extends StatelessWidget {
  const _CredentialRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF9F9FD),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: PgColors.border),
        ),
        child: Row(children: [
          Text('$label  ', style: const TextStyle(fontSize: 11.5, color: Color(0xFF6B7280))),
          Expanded(
            child: SelectableText(value,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ]),
      );
}

/// Create a manager, or change an existing manager's property assignment.
///
/// The name/mobile fields are create-only: editing an existing login is purely an
/// assignment change, so re-showing identity fields that the form would not send
/// would be misleading.
class _ManagerFormSheet extends StatefulWidget {
  const _ManagerFormSheet({required this.properties, this.manager});
  final List<Map<String, dynamic>> properties;
  final Map<String, dynamic>? manager;

  @override
  State<_ManagerFormSheet> createState() => _ManagerFormSheetState();
}

class _ManagerFormSheetState extends State<_ManagerFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  late Set<int> _selected;
  bool _busy = false;

  bool get _isEdit => widget.manager != null;

  @override
  void initState() {
    super.initState();
    _selected = {
      for (final p in (widget.manager?['properties'] as List? ?? const []))
        ((p as Map)['propertyId'] as num).toInt(),
    };
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _mobileCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_isEdit && !_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final api = context.read<AppState>().apiClient;
    try {
      if (_isEdit) {
        await api.put('/managers/${widget.manager!['user_login_id']}/properties',
            {'propertyIds': _selected.toList()});
        if (!mounted) return;
        Navigator.pop(context, true);
        AppToast.success(context, 'Assigned properties updated');
      } else {
        final res = await api.post('/managers', {
          'fullName': _nameCtrl.text.trim(),
          'mobileNumber': _mobileCtrl.text.trim(),
          'propertyIds': _selected.toList(),
        });
        if (!mounted) return;
        Navigator.pop(context, true);
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Manager Created'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Share these with the manager. The password is shown only once.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                const SizedBox(height: 14),
                // The mobile, not the stored username: the backend resolves a bare 10-digit
                // entry to the org-suffixed username, so nobody has to type "@m103".
                _CredentialRow(label: 'Sign in with', value: '${res['loginId'] ?? _mobileCtrl.text.trim()}'),
                const SizedBox(height: 8),
                _CredentialRow(label: 'Temporary password', value: '${res['temporaryPassword']}'),
              ],
            ),
            actions: [
              FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
            ],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppToast.error(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text(_isEdit ? 'Assigned Properties' : 'Add Manager',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(height: 4),
              Text(
                _isEdit
                    ? 'This login can only see the properties ticked below.'
                    : 'Creates a login limited to the properties you tick.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
              ),
              const SizedBox(height: 18),
              if (!_isEdit) ...[
                TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Full name', isDense: true),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _mobileCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Mobile number',
                    helperText: 'They sign in with this number',
                    isDense: true,
                  ),
                  validator: (v) =>
                      RegExp(r'^\d{10}$').hasMatch((v ?? '').trim()) ? null : 'Enter 10 digits',
                ),
                const SizedBox(height: 18),
              ],
              const Text('Properties',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 6),
              if (widget.properties.isEmpty)
                Text('No properties yet — add a property first.',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[600]))
              else
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: PgColors.border),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(children: [
                    for (int i = 0; i < widget.properties.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      CheckboxListTile(
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _selected.contains(
                            (widget.properties[i]['propertyId'] as num).toInt()),
                        title: Text('${widget.properties[i]['propertyName']}',
                            style: const TextStyle(fontSize: 13.5)),
                        onChanged: _busy
                            ? null
                            : (on) => setState(() {
                                  final id =
                                      (widget.properties[i]['propertyId'] as num).toInt();
                                  if (on == true) {
                                    _selected.add(id);
                                  } else {
                                    _selected.remove(id);
                                  }
                                }),
                      ),
                    ],
                  ]),
                ),
              if (_selected.isEmpty) ...[
                const SizedBox(height: 8),
                Row(children: const [
                  Icon(Icons.warning_amber_rounded, size: 15, color: PgColors.warning),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text('With nothing ticked, this login will see nothing.',
                        style: TextStyle(fontSize: 11.5, color: PgColors.warning)),
                  ),
                ]),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_isEdit ? 'Save' : 'Create Login'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
