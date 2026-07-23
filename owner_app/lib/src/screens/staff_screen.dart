import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../theme/app_theme.dart';
import '../utils/validators.dart';
import '../widgets/animations.dart';
import '../widgets/app_toast.dart';
import '../widgets/skeleton.dart';
import '../widgets/error_retry_view.dart';

/// Staff management: employees with a profession and monthly salary, a
/// month-by-month paid/due tracker, per-staff Pay and bulk Pay All / Pay
/// Selected. Backed by `/api/staff/**` (schema V17); paying a salary also
/// records a SALARY expense so the expenses dashboard reflects payroll.
///
/// Entry modes mirror ExpensesScreen: route `/staff` (org-level) or pushed
/// from the property workspace with [propertyId]/[propertyName] (locked).
class StaffScreen extends StatefulWidget {
  final int? propertyId;
  final String? propertyName;
  const StaffScreen({super.key, this.propertyId, this.propertyName});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

const _professions = [
  'Cook',
  'Warden',
  'Cleaner',
  'Security',
  'Manager',
  'Electrician',
  'Plumber',
  'Gardener',
];

const Map<String, String> _paymentMethods = {
  'CASH': 'Cash',
  'UPI': 'UPI',
  'CARD': 'Card',
  'BANK_TRANSFER': 'Bank Transfer',
};

const _avatarColors = [
  Color(0xFF4F2DE4),
  Color(0xFF0E9AAB),
  Color(0xFFE07B2A),
  Color(0xFF16A085),
  Color(0xFFDB4A6B),
  Color(0xFF9B59D0),
];

double _num(dynamic v) => v == null ? 0 : (v as num).toDouble();

String _inr(num value) {
  final s = value.round().abs().toString();
  final sign = value < 0 ? '-' : '';
  if (s.length <= 3) return '$sign₹$s';
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final groups = <String>[];
  while (rest.length > 2) {
    groups.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) groups.insert(0, rest);
  return '$sign₹${groups.join(',')},$last3';
}

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
  return DateTime.tryParse(v.toString());
}

class _StaffScreenState extends State<StaffScreen> {
  late Future<Map<String, dynamic>> _future;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  final Set<int> _selected = {};

  String get _monthParam =>
      '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  String get _scopeLabel => widget.propertyName ?? 'All Properties';

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  void _reload() {
    setState(() {
      _selected.clear();
      _future = _fetch();
    });
  }

  Future<Map<String, dynamic>> _fetch() {
    final query = [
      if (widget.propertyId != null) 'propertyId=${widget.propertyId}',
      'month=$_monthParam',
    ].join('&');
    return context.read<AppState>().apiClient.get('/staff?$query');
  }

  void _shiftMonth(int delta) {
    final next = DateTime(_month.year, _month.month + delta);
    final now = DateTime.now();
    if (next.isAfter(DateTime(now.year, now.month))) return;
    setState(() => _month = next);
    _reload();
  }

  void _toastSuccess(String msg, {String? title}) {
    if (!mounted) return;
    AppToast.success(context, msg, title: title);
  }

  void _toastError(String msg) {
    if (!mounted) return;
    AppToast.error(context, msg);
  }

  // ─────────────────────────────────────────────────────────────── build ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PgColors.scaffold,
      appBar: AppBar(
        title:
            const Text('Staff', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
              onPressed: _reload, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openStaffSheet(),
        backgroundColor: PgColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add Staff',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SkeletonList();
          }
          if (snap.hasError) {
            return ErrorRetryView(error: snap.error!, onRetry: _reload);
          }
          return _buildBody(snap.data ?? const {});
        },
      ),
    );
  }

  Widget _buildBody(Map<String, dynamic> d) {
    final items = [
      for (final e in (d['items'] as List? ?? const []))
        Map<String, dynamic>.from(e as Map),
    ];
    final summary = Map<String, dynamic>.from(d['summary'] as Map? ?? {});
    _selected.removeWhere((id) => !items.any((s) =>
        (s['staffId'] as num?)?.toInt() == id && s['paidAmount'] == null));

    return RefreshIndicator(
      onRefresh: () async {
        _reload();
        await _future;
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: [
              FadeSlideIn(child: _buildScopeAndMonth()),
              const SizedBox(height: 14),
              FadeSlideIn(
                  delay: const Duration(milliseconds: 40),
                  child: _buildSummaryCard(summary)),
              const SizedBox(height: 14),
              if ((summary['dueCount'] as num? ?? 0) > 0)
                FadeSlideIn(
                    delay: const Duration(milliseconds: 80),
                    child: _buildPayBar(items, summary)),
              const SizedBox(height: 20),
              FadeSlideIn(
                delay: const Duration(milliseconds: 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Staff (${items.length})',
                        style: const TextStyle(
                            color: PgColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    if (items.isEmpty)
                      _LightCard(
                        child: _EmptyHint(
                          icon: Icons.badge_outlined,
                          text:
                              'No staff yet. Add your cook, warden, security and more.',
                          actionLabel: 'Add Staff',
                          onAction: () => _openStaffSheet(),
                        ),
                      )
                    else
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0) const SizedBox(height: 10),
                        _staffCard(items[i]),
                      ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────── scope + month ──

  Widget _buildScopeAndMonth() {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: PgColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.apartment_rounded,
                    color: PgColors.primary, size: 17),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(_scopeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: PgColors.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: PgColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => _shiftMonth(-1),
                icon: const Icon(Icons.chevron_left_rounded,
                    color: PgColors.textSecondary, size: 20),
              ),
              Text(DateFormat('MMM yyyy').format(_month),
                  style: const TextStyle(
                      color: PgColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: _isCurrentMonth ? null : () => _shiftMonth(1),
                icon: Icon(Icons.chevron_right_rounded,
                    color: _isCurrentMonth
                        ? PgColors.hairline
                        : PgColors.textSecondary,
                    size: 20),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────── summary card ──

  Widget _buildSummaryCard(Map<String, dynamic> summary) {
    final payroll = _num(summary['monthlyPayroll']);
    final paidTotal = _num(summary['paidTotal']);
    final dueTotal = _num(summary['dueTotal']);
    final paidCount = (summary['paidCount'] as num? ?? 0).toInt();
    final dueCount = (summary['dueCount'] as num? ?? 0).toInt();
    final active = (summary['activeStaff'] as num? ?? 0).toInt();
    final target = paidTotal + dueTotal;
    return _LightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('MONTHLY PAYROLL',
                    style: TextStyle(
                        color: PgColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2)),
              ),
              _Chip(
                  label: '$active active',
                  color: PgColors.primary,
                  icon: Icons.badge_outlined),
            ],
          ),
          const SizedBox(height: 8),
          Text(_inr(payroll),
              style: const TextStyle(
                  color: PgColors.textPrimary,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1)),
          const SizedBox(height: 14),
          Row(
            children: [
              _Chip(
                  label: '$paidCount paid · ${_inr(paidTotal)}',
                  color: PgColors.success,
                  icon: Icons.check_circle_rounded),
              const SizedBox(width: 8),
              _Chip(
                  label: '$dueCount due · ${_inr(dueTotal)}',
                  color: dueCount > 0
                      ? PgColors.warning
                      : PgColors.textSecondary,
                  icon: Icons.schedule_rounded),
            ],
          ),
          if (target > 0) ...[
            const SizedBox(height: 14),
            _AnimatedBar(
                fraction: (paidTotal / target).clamp(0.0, 1.0),
                color: PgColors.success),
          ],
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────── pay bar ──

  Widget _buildPayBar(
      List<Map<String, dynamic>> items, Map<String, dynamic> summary) {
    final due = [
      for (final s in items)
        if (s['paidAmount'] == null && s['status'] == 'ACTIVE') s,
    ];
    final targets = _selected.isEmpty
        ? due
        : [
            for (final s in due)
              if (_selected.contains((s['staffId'] as num).toInt())) s,
          ];
    final total = targets.fold<double>(0, (t, s) => t + _num(s['monthlySalary']));
    final label = _selected.isEmpty
        ? 'Pay All (${targets.length})'
        : 'Pay Selected (${targets.length})';
    return _LightCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    _selected.isEmpty
                        ? '${due.length} salaries due'
                        : '${targets.length} of ${due.length} selected',
                    style: const TextStyle(
                        color: PgColors.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(_inr(total),
                    style: const TextStyle(
                        color: PgColors.textSecondary, fontSize: 12.5)),
              ],
            ),
          ),
          if (_selected.isNotEmpty)
            TextButton(
              onPressed: () => setState(_selected.clear),
              child: const Text('Clear',
                  style: TextStyle(fontSize: 12.5, color: PgColors.primary)),
            ),
          FilledButton.icon(
            onPressed: targets.isEmpty ? null : () => _confirmPay(targets),
            style: FilledButton.styleFrom(
                minimumSize: const Size(0, 42),
                padding: const EdgeInsets.symmetric(horizontal: 16)),
            icon: const Icon(Icons.payments_rounded, size: 16),
            label: Text(label,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmPay(List<Map<String, dynamic>> targets) async {
    var method = 'CASH';
    final total =
        targets.fold<double>(0, (t, s) => t + _num(s['monthlySalary']));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Pay Salaries',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  '${targets.length} staff · ${_inr(total)} for ${DateFormat('MMMM yyyy').format(_month)}',
                  style: const TextStyle(
                      color: PgColors.textSecondary, fontSize: 13.5)),
              const SizedBox(height: 14),
              RadioGroup<String>(
                groupValue: method,
                onChanged: (v) => setDialogState(() => method = v ?? method),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final e in _paymentMethods.entries)
                      RadioListTile<String>(
                        value: e.key,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        activeColor: PgColors.primary,
                        title: Text(e.value,
                            style: const TextStyle(fontSize: 14)),
                      ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Pay ${_inr(total)}')),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final result = await context.read<AppState>().apiClient.post('/staff/pay', {
        'staffIds': [for (final s in targets) (s['staffId'] as num).toInt()],
        'month': _monthParam,
        'paymentMethod': method,
      });
      final paid = (result['paid'] as num? ?? 0).toInt();
      final skipped = (result['skipped'] as num? ?? 0).toInt();
      _toastSuccess(
          skipped > 0
              ? '$paid paid · $skipped skipped (already paid or inactive)'
              : '$paid salaries paid · ${_inr(_num(result['totalAmount']))}',
          title: 'Salaries Paid');
      _reload();
    } catch (e) {
      _toastError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  // ──────────────────────────────────────────────────────────── staff card ──

  Widget _staffCard(Map<String, dynamic> s) {
    final id = (s['staffId'] as num).toInt();
    final name = '${s['fullName'] ?? ''}';
    final active = s['status'] == 'ACTIVE';
    final paid = s['paidAmount'] != null;
    final mobile = '${s['mobileNumber'] ?? ''}';
    final color = _avatarColors[name.hashCode.abs() % _avatarColors.length];
    return _LightCard(
      padding: const EdgeInsets.all(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openStaffSheet(staff: s),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: color.withValues(alpha: 0.12),
              child: Text(_initials(name),
                  style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: active
                                    ? PgColors.textPrimary
                                    : PgColors.textTertiary,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700)),
                      ),
                      if (!active) ...[
                        const SizedBox(width: 6),
                        const _Chip(
                            label: 'Inactive', color: PgColors.textTertiary),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                      '${s['profession'] ?? ''} · ${_inr(_num(s['monthlySalary']))}/mo',
                      style: const TextStyle(
                          color: PgColors.textSecondary, fontSize: 12.5)),
                  if (paid) ...[
                    const SizedBox(height: 5),
                    _Chip(
                      label:
                          'Paid ${_inr(_num(s['paidAmount']))} · ${_paidOn(s)}',
                      color: PgColors.success,
                      icon: Icons.check_circle_rounded,
                    ),
                  ],
                ],
              ),
            ),
            if (mobile.isNotEmpty)
              IconButton(
                onPressed: () =>
                    launchUrl(Uri(scheme: 'tel', path: mobile)),
                icon: const Icon(Icons.call_rounded,
                    color: PgColors.success, size: 19),
                tooltip: mobile,
              ),
            if (!paid && active) ...[
              Checkbox(
                value: _selected.contains(id),
                activeColor: PgColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5)),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selected.add(id);
                  } else {
                    _selected.remove(id);
                  }
                }),
              ),
              _PillButton(
                label: 'Pay',
                color: PgColors.primary,
                onTap: () => _confirmPay([s]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, parts.first.length == 1 ? 1 : 2).toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  static String _paidOn(Map<String, dynamic> s) {
    final d = _parseDate(s['paidDate']);
    return d == null ? '' : DateFormat('d MMM').format(d);
  }

  // ─────────────────────────────────────────────────────────────── sheets ──

  Future<void> _openStaffSheet({Map<String, dynamic>? staff}) async {
    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _StaffSheet(
        propertyId: widget.propertyId,
        scopeLabel: _scopeLabel,
        staff: staff,
      ),
    );
    if (result == 'deleted') {
      _toastSuccess('Staff deleted', title: 'Staff Deleted');
      _reload();
    } else if (result == true) {
      _toastSuccess(staff == null ? 'Staff added' : 'Staff updated',
          title: staff == null ? 'Staff Added' : 'Staff Updated');
      _reload();
    }
  }
}

// ─────────────────────────────────────────────────────── add/edit sheet ──

class _StaffSheet extends StatefulWidget {
  final int? propertyId;
  final String scopeLabel;
  final Map<String, dynamic>? staff;
  const _StaffSheet(
      {required this.propertyId, required this.scopeLabel, this.staff});

  @override
  State<_StaffSheet> createState() => _StaffSheetState();
}

class _StaffSheetState extends State<_StaffSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: '${widget.staff?['fullName'] ?? ''}');
  late final _salary = TextEditingController(
      text: widget.staff == null
          ? ''
          : _num(widget.staff!['monthlySalary']).round().toString());
  late final _mobile =
      TextEditingController(text: '${widget.staff?['mobileNumber'] ?? ''}');
  late final _notes =
      TextEditingController(text: '${widget.staff?['notes'] ?? ''}');
  late final _customProfession = TextEditingController(
      text: _isKnownProfession ? '' : '${widget.staff?['profession'] ?? ''}');
  late String _profession =
      _isKnownProfession ? '${widget.staff?['profession'] ?? _professions.first}' : 'Other';
  late DateTime? _joinDate = _parseDate(widget.staff?['joinDate']);
  late bool _active = widget.staff == null || widget.staff!['status'] == 'ACTIVE';
  bool _saving = false;
  String? _joinDateError;

  bool get _isKnownProfession =>
      widget.staff == null ||
      _professions.contains('${widget.staff?['profession'] ?? ''}');

  bool get _isEdit => widget.staff != null;

  /// Salary for the selected month is already paid — the amount is locked so
  /// the recorded payment and the staff row can't drift apart.
  bool get _salaryPaid => _isEdit && widget.staff!['paidAmount'] != null;

  @override
  void dispose() {
    _name.dispose();
    _salary.dispose();
    _mobile.dispose();
    _notes.dispose();
    _customProfession.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final fieldsValid = _formKey.currentState!.validate();
    setState(() =>
        _joinDateError = _joinDate == null ? 'Join date is required' : null);
    if (!fieldsValid || _joinDate == null) return;
    setState(() => _saving = true);
    final profession =
        _profession == 'Other' ? _customProfession.text.trim() : _profession;
    final propertyId = _isEdit
        ? (widget.staff!['propertyId'] as num?)?.toInt()
        : widget.propertyId;
    final body = {
      'fullName': _name.text.trim(),
      'profession': profession,
      'monthlySalary': double.parse(_salary.text.trim()),
      'mobileNumber': _mobile.text.trim(),
      if (propertyId != null) 'propertyId': propertyId,
      'joinDate': DateFormat('yyyy-MM-dd').format(_joinDate!),
      if (_isEdit) 'status': _active ? 'ACTIVE' : 'INACTIVE',
      if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
    };
    try {
      final api = context.read<AppState>().apiClient;
      if (_isEdit) {
        await api.put('/staff/${(widget.staff!['staffId'] as num).toInt()}', body);
      } else {
        await api.post('/staff', body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        AppToast.error(context, e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  Future<void> _delete() async {
    final name = '${widget.staff!['fullName']}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete staff?'),
        content: Text(
            '$name will be removed from the staff list and payroll. '
            'Past salary payments are kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: PgColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final api = context.read<AppState>().apiClient;
      await api.delete('/staff/${(widget.staff!['staffId'] as num).toInt()}');
      if (mounted) Navigator.pop(context, 'deleted');
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        AppToast.error(context, e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  Future<void> _pickJoinDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _joinDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _joinDate = picked;
        _joinDateError = null;
      });
    }
  }

  Future<void> _showHistory() async {
    final staffId = (widget.staff!['staffId'] as num).toInt();
    final api = context.read<AppState>().apiClient;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PaymentHistorySheet(
          name: '${widget.staff!['fullName']}',
          future: api.get('/staff/$staffId/payments')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(_isEdit ? 'Edit Staff' : 'Add Staff',
                          style: const TextStyle(
                              color: PgColors.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.w700)),
                    ),
                    if (_isEdit) ...[
                      IconButton(
                        onPressed: _showHistory,
                        tooltip: 'Payment history',
                        icon: const Icon(Icons.history_rounded,
                            color: PgColors.primary),
                      ),
                      IconButton(
                        onPressed: _saving ? null : _delete,
                        tooltip: 'Delete staff',
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: PgColors.danger),
                      ),
                    ],
                    _Chip(
                        label: widget.scopeLabel,
                        color: PgColors.primary,
                        icon: Icons.apartment_rounded),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                      labelText: 'Full Name', hintText: 'e.g. Ramesh Kumar'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _profession,
                        decoration:
                            const InputDecoration(labelText: 'Profession'),
                        items: [
                          for (final p in _professions)
                            DropdownMenuItem(value: p, child: Text(p)),
                          const DropdownMenuItem(
                              value: 'Other', child: Text('Other')),
                        ],
                        onChanged: (v) =>
                            setState(() => _profession = v ?? _profession),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _salary,
                        enabled: !_salaryPaid,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                            labelText: 'Monthly Salary (₹)',
                            helperText: _salaryPaid
                                ? 'Locked — already paid this month'
                                : null,
                            helperMaxLines: 2),
                        validator: (v) {
                          final n = double.tryParse((v ?? '').trim());
                          if (n == null || n <= 0) {
                            return 'Enter a valid salary';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                if (_profession == 'Other') ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _customProfession,
                    decoration: const InputDecoration(
                        labelText: 'Profession name',
                        hintText: 'e.g. Driver'),
                    validator: (v) => _profession == 'Other' &&
                            (v == null || v.trim().isEmpty)
                        ? 'Enter the profession'
                        : null,
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _mobile,
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                        decoration: const InputDecoration(
                            labelText: 'Mobile', counterText: ''),
                        validator: Validators.mobile,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: _pickJoinDate,
                        borderRadius: BorderRadius.circular(12),
                        child: InputDecorator(
                          decoration: InputDecoration(
                              labelText: 'Join Date',
                              errorText: _joinDateError),
                          child: Text(
                              _joinDate == null
                                  ? '—'
                                  : DateFormat('d MMM yyyy').format(_joinDate!),
                              style: TextStyle(
                                  color: _joinDate == null
                                      ? PgColors.textTertiary
                                      : PgColors.textPrimary)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notes,
                  decoration:
                      const InputDecoration(labelText: 'Notes (optional)'),
                ),
                if (_isEdit)
                  SwitchListTile(
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                    contentPadding: EdgeInsets.zero,
                    title:
                        const Text('Active', style: TextStyle(fontSize: 14)),
                    subtitle: const Text(
                        'Inactive staff are excluded from payroll',
                        style: TextStyle(
                            fontSize: 12, color: PgColors.textSecondary)),
                  ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style:
                      FilledButton.styleFrom(minimumSize: const Size(0, 50)),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.4))
                      : Text(_isEdit ? 'Save Changes' : 'Add Staff',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────── payment history sheet ──

class _PaymentHistorySheet extends StatelessWidget {
  final String name;
  final Future<Map<String, dynamic>> future;
  const _PaymentHistorySheet({required this.name, required this.future});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Payment History · $name',
                style: const TextStyle(
                    color: PgColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Flexible(
              child: FutureBuilder<Map<String, dynamic>>(
                future: future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(28),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final items = [
                    for (final e in (snap.data?['items'] as List? ?? const []))
                      Map<String, dynamic>.from(e as Map),
                  ];
                  if (items.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('No salary payments recorded yet.',
                          style: TextStyle(
                              color: PgColors.textSecondary, fontSize: 13)),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: PgColors.hairline, height: 1),
                    itemBuilder: (_, i) {
                      final p = items[i];
                      final month =
                          DateTime.tryParse('${p['payMonth']}-01');
                      final paidDate = _parseDate(p['paidDate']);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: const Icon(Icons.receipt_long_rounded,
                            color: PgColors.primary, size: 20),
                        title: Text(
                            month == null
                                ? '${p['payMonth']}'
                                : DateFormat('MMMM yyyy').format(month),
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                            '${_paymentMethods['${p['paymentMethod']}'] ?? p['paymentMethod']}'
                            '${paidDate == null ? '' : ' · ${DateFormat('d MMM yyyy').format(paidDate)}'}',
                            style: const TextStyle(
                                fontSize: 12,
                                color: PgColors.textSecondary)),
                        trailing: Text(_inr(_num(p['amount'])),
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700)),
                      );
                    },
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

// ──────────────────────────────────────────────────────── shared widgets ──

class _LightCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _LightCard(
      {required this.child, this.padding = const EdgeInsets.all(18)});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PgColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _EmptyHint(
      {required this.icon,
      required this.text,
      this.actionLabel,
      this.onAction});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: PgColors.textTertiary, size: 32),
            const SizedBox(height: 10),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: PgColors.textSecondary, fontSize: 13)),
            if (actionLabel != null) ...[
              const SizedBox(height: 12),
              _PillButton(
                  label: actionLabel!,
                  color: PgColors.primary,
                  onTap: onAction ?? () {}),
            ],
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  const _Chip({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 12),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 10.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _PillButton(
      {required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _AnimatedBar extends StatelessWidget {
  final double fraction;
  final Color color;
  const _AnimatedBar({required this.fraction, required this.color});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: fraction.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 1000),
      curve: Curves.easeOutCubic,
      builder: (_, t, __) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 8,
          color: PgColors.hairline,
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: t,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
