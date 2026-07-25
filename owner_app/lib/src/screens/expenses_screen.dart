import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme/app_theme.dart';
import '../utils/expense_categories.dart';
import '../widgets/animations.dart';
import '../widgets/app_toast.dart';
import '../widgets/skeleton.dart';
import '../widgets/error_retry_view.dart';

/// Expenses dashboard, light-themed like the rest of the app and fully backed
/// by the expense module API (`/api/expenses/**`, schema V16 — see
/// docs/EXPENSES_SCHEMA_MAPPING.md).
///
/// Sections: monthly summary (+ Set Budget), quick actions, category
/// overview, pending approvals, recent transactions (last 7 days, filtered
/// server-side), and insights.
///
/// Two entry modes:
///  * org-level (route `/expenses`) — property switcher enabled ("All
///    Properties" or any property from `/owner/properties`)
///  * property-scoped (pushed from the property workspace with [propertyId] /
///    [propertyName]) — the scope is locked to that property.
class ExpensesScreen extends StatefulWidget {
  final int? propertyId;
  final String? propertyName;
  const ExpensesScreen({super.key, this.propertyId, this.propertyName});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

// ─────────────────────────────────────────────────────────── category meta ──

// The category master lives in utils/expense_categories.dart so the reports
// screen filters on exactly the same list.
const _categoryMeta = expenseCategoryMeta;

ExpenseCategoryMeta _meta(String? category) => expenseCategory(category);

const Map<String, String> _paymentMethods = {
  'CASH': 'Cash',
  'UPI': 'UPI',
  'CARD': 'Card',
  'BANK_TRANSFER': 'Bank Transfer',
};

// ──────────────────────────────────────────────────────────────── helpers ──

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

String _relative(dynamic iso) {
  final d = _parseDate(iso);
  if (d == null) return '';
  final now = DateTime.now();
  final diff = DateTime(now.year, now.month, now.day)
      .difference(DateTime(d.year, d.month, d.day))
      .inDays;
  if (diff <= 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff < 7) return '$diff days ago';
  return DateFormat('d MMM').format(d);
}

// ──────────────────────────────────────────────────────────────── screen ──

class _ExpensesScreenState extends State<ExpensesScreen> {
  late Future<Map<String, dynamic>> _future;
  List<Map<String, dynamic>> _properties = const [];
  int? _propertyId;
  String? _propertyName;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  bool get _locked => widget.propertyId != null;

  String get _monthParam =>
      '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  String get _scopeLabel => _locked
      ? (widget.propertyName ?? 'Property')
      : (_propertyName ?? 'All Properties');

  @override
  void initState() {
    super.initState();
    _propertyId = widget.propertyId;
    _propertyName = widget.propertyName;
    _future = _fetch();
  }

  // Block body on purpose: `() => _future = _fetch()` would make the closure
  // return the Future, and setState's debug assert then throws BEFORE the
  // widget is marked dirty — the fetch happens but the UI never repaints.
  void _reload() {
    setState(() {
      _future = _fetch();
    });
  }

  Future<Map<String, dynamic>> _fetch() async {
    final api = context.read<AppState>().apiClient;
    if (!_locked && _properties.isEmpty) {
      try {
        final res = await api.get('/owner/properties');
        _properties = [
          for (final p in (res['items'] as List? ?? const []))
            Map<String, dynamic>.from(p as Map),
        ];
      } catch (_) {
        // Selector falls back to "All Properties" only.
      }
    }
    final query = [
      if (_propertyId != null) 'propertyId=$_propertyId',
      'month=$_monthParam',
    ].join('&');
    return api.get('/expenses/dashboard?$query');
  }

  void _shiftMonth(int delta) {
    final next = DateTime(_month.year, _month.month + delta);
    final now = DateTime.now();
    if (next.isAfter(DateTime(now.year, now.month))) return;
    setState(() => _month = next);
    _reload();
  }

  // ─────────────────────────────────────────────────────────────── build ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PgColors.scaffold,
      appBar: AppBar(
        title: const Text('Expenses',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
              onPressed: _reload, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddExpense(),
        backgroundColor: PgColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Expense',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SkeletonList(showLeading: false);
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
    final summary = Map<String, dynamic>.from(d['summary'] as Map? ?? {});
    final categories = _listOfMaps(d['categories']);
    final pending = Map<String, dynamic>.from(d['pendingApprovals'] as Map? ?? {});
    final insights = [for (final i in (d['insights'] as List? ?? const [])) '$i'];

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
              FadeSlideIn(child: _buildPropertySelector()),
              const SizedBox(height: 14),
              FadeSlideIn(
                  delay: const Duration(milliseconds: 40),
                  child: _buildSummaryCard(summary)),
              const SizedBox(height: 18),
              FadeSlideIn(
                  delay: const Duration(milliseconds: 80),
                  child: _buildQuickActions(pending)),
              const SizedBox(height: 22),
              FadeSlideIn(
                delay: const Duration(milliseconds: 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _SectionHeader('Category Overview'),
                    const SizedBox(height: 10),
                    _buildCategoryOverview(categories),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              FadeSlideIn(
                  delay: const Duration(milliseconds: 160),
                  child: _buildInsights(insights)),
            ],
          ),
        ),
      ),
    );
  }

  static List<Map<String, dynamic>> _listOfMaps(dynamic v) => [
        for (final e in (v as List? ?? const []))
          Map<String, dynamic>.from(e as Map),
      ];

  void _toastSuccess(String msg, {String? title}) {
    if (!mounted) return;
    AppToast.success(context, msg, title: title);
  }

  // ─────────────────────────────────────────────────── property selector ──

  Widget _buildPropertySelector() {
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: _locked ? null : _pickProperty,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
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
                    const SizedBox(width: 5),
                    if (_locked)
                      const Icon(Icons.lock_rounded,
                          color: PgColors.textTertiary, size: 14)
                    else
                      const Icon(Icons.keyboard_arrow_down_rounded,
                          color: PgColors.textSecondary, size: 19),
                  ],
                ),
              ),
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

  void _pickProperty() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select Property',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: PgColors.textPrimary)),
              const SizedBox(height: 10),
              _propertyTile(ctx, null, 'All Properties'),
              for (final p in _properties)
                _propertyTile(ctx, (p['facilityId'] as num?)?.toInt(),
                    '${p['facilityName'] ?? 'Property'}'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _propertyTile(BuildContext ctx, int? id, String name) {
    final selected = id == _propertyId;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
            color: PgColors.lavender, borderRadius: BorderRadius.circular(12)),
        child: Icon(id == null ? Icons.domain_rounded : Icons.apartment_rounded,
            color: PgColors.primary, size: 20),
      ),
      title: Text(name,
          style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: PgColors.textPrimary)),
      trailing: selected
          ? const Icon(Icons.check_circle_rounded,
              color: PgColors.primary, size: 21)
          : null,
      onTap: () {
        Navigator.pop(ctx);
        setState(() {
          _propertyId = id;
          _propertyName = id == null ? null : name;
        });
        _reload();
      },
    );
  }

  // ──────────────────────────────────────────────────────── summary card ──

  Widget _buildSummaryCard(Map<String, dynamic> summary) {
    final total = _num(summary['total']);
    final changePct =
        summary['changePct'] == null ? null : _num(summary['changePct']);
    final budget = summary['budget'] == null ? null : _num(summary['budget']);
    final remaining =
        summary['remaining'] == null ? null : _num(summary['remaining']);
    return _LightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                    _isCurrentMonth
                        ? 'EXPENSES THIS MONTH'
                        : 'EXPENSES · ${DateFormat('MMM yyyy').format(_month).toUpperCase()}',
                    style: const TextStyle(
                        color: PgColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2)),
              ),
              if (changePct != null)
                _Chip(
                  icon: changePct >= 0
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  label:
                      '${changePct >= 0 ? '+' : ''}${changePct.round()}% from last month',
                  color: changePct > 0 ? PgColors.danger : PgColors.success,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(_inr(total),
              style: const TextStyle(
                  color: PgColors.textPrimary,
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                  height: 1.05)),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Budget Remaining',
                        style: TextStyle(
                            color: PgColors.textSecondary, fontSize: 12.5)),
                    const SizedBox(height: 4),
                    if (budget == null)
                      const Text('No budget set',
                          style: TextStyle(
                              color: PgColors.textTertiary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600))
                    else
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                color: (remaining ?? 0) < 0
                                    ? PgColors.danger
                                    : PgColors.success,
                                shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 7),
                          Text(_inr(remaining ?? 0),
                              style: TextStyle(
                                  color: (remaining ?? 0) < 0
                                      ? PgColors.danger
                                      : PgColors.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _openSetBudget,
                style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 42),
                    padding: const EdgeInsets.symmetric(horizontal: 16)),
                icon: const Icon(Icons.edit_rounded, size: 15),
                label: const Text('Set Budget',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          if (budget != null && budget > 0) ...[
            const SizedBox(height: 14),
            _AnimatedBar(
                fraction: (total / budget).clamp(0.0, 1.0),
                color: total > budget ? PgColors.danger : PgColors.primary),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────── quick actions ──

  /// The landing page is the month's *picture* (total, categories, insights);
  /// the row-by-row work lives one tap away in [ExpenseActivityScreen].
  Widget _buildQuickActions(Map<String, dynamic> pending) {
    final count = (pending['count'] as num?)?.toInt() ?? 0;
    return Row(
      children: [
        Expanded(
          child: _QuickActionChip(
            label: 'Approvals',
            icon: Icons.fact_check_outlined,
            color: PgColors.warning,
            badge: count > 0 ? '$count' : null,
            onTap: () => _openActivity(0),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickActionChip(
            label: 'Transactions',
            icon: Icons.receipt_long_rounded,
            color: PgColors.primary,
            onTap: () => _openActivity(1),
          ),
        ),
      ],
    );
  }

  Future<void> _openActivity(int page) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => ExpenseActivityScreen(
        propertyId: _propertyId,
        scopeLabel: _scopeLabel,
        month: _month,
        initialPage: page,
      ),
    ));
    // Approvals/edits/deletes there move this month's totals.
    if (mounted) _reload();
  }

  // ─────────────────────────────────────────────────── category overview ──

  Widget _buildCategoryOverview(List<Map<String, dynamic>> categories) {
    if (categories.isEmpty) {
      return _LightCard(
        child: _EmptyHint(
          icon: Icons.donut_large_rounded,
          text: 'No expenses recorded this month yet.',
          actionLabel: 'Add Expense',
          onAction: () => _openAddExpense(),
        ),
      );
    }
    final total = categories.fold<double>(0, (s, c) => s + _num(c['total']));
    return _LightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stacked distribution bar.
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, t, __) => ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: SizedBox(
                height: 12,
                child: Row(
                  children: [
                    for (final c in categories)
                      Expanded(
                        flex: (_num(c['total']) * t).round().clamp(1, 1 << 20),
                        child: Container(
                          color: _meta('${c['category']}').color,
                          margin: const EdgeInsets.only(right: 1.5),
                        ),
                      ),
                    if (t < 1) Spacer(flex: (total * (1 - t)).round() + 1),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < categories.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _categoryRow(categories[i], total),
          ],
        ],
      ),
    );
  }

  Widget _categoryRow(Map<String, dynamic> c, double total) {
    final meta = _meta('${c['category']}');
    final amount = _num(c['total']);
    final pct = total > 0 ? (amount / total * 100).round() : 0;
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: meta.color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(meta.label,
              style: const TextStyle(
                  color: PgColors.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500)),
        ),
        Text(_inr(amount),
            style: const TextStyle(
                color: PgColors.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w700)),
        SizedBox(
          width: 44,
          child: Text('$pct%',
              textAlign: TextAlign.right,
              style: const TextStyle(
                  color: PgColors.textSecondary, fontSize: 12.5)),
        ),
      ],
    );
  }


  // ──────────────────────────────────────────────────────────── insights ──

  Widget _buildInsights(List<String> insights) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF1EEFE),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    color: PgColors.primary, size: 19),
              ),
              const SizedBox(width: 12),
              const Text('Smart Insights',
                  style: TextStyle(
                      color: PgColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < insights.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _insightRow(insights[i]),
          ],
        ],
      ),
    );
  }

  Widget _insightRow(String text) {
    final lower = text.toLowerCase();
    final (icon, color) = lower.contains('increased')
        ? (Icons.trending_up_rounded, PgColors.danger)
        : lower.contains('utilization')
            ? (Icons.pie_chart_rounded, PgColors.warning)
            : lower.contains('saving')
                ? (Icons.savings_rounded, PgColors.success)
                : (Icons.auto_awesome_rounded, PgColors.primary);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: PgColors.textPrimary, fontSize: 13, height: 1.45)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────── sheets ──

  Future<void> _openAddExpense() async {
    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) =>
          _AddExpenseSheet(propertyId: _propertyId, scopeLabel: _scopeLabel),
    );
    if (saved != null) {
      _toastSuccess(
          saved == 'pending'
              ? 'Expense recorded — awaiting approval'
              : 'Expense recorded',
          title: 'Expense Added');
      _reload();
    }
  }

  Future<void> _openSetBudget() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) =>
          _SetBudgetSheet(propertyId: _propertyId, scopeLabel: _scopeLabel),
    );
    if (saved == true) {
      _toastSuccess('Budget saved', title: 'Budget Saved');
      _reload();
    }
  }
}

// ─────────────────────────────────────────────────────── expense activity ──

/// The row-by-row half of the expenses module, split out of the landing page so
/// that page stays a single glance at the month (total, categories, insights).
///
/// Layout: the month selector is a **fixed** header — it applies to both pages,
/// so it must not scroll away — and below it the two work lists live in a
/// swipeable [PageView]: Pending Expenses (approve / reject) and Transactions
/// (edit / delete). Reached from the Approvals / Transactions chips.
class ExpenseActivityScreen extends StatefulWidget {
  final int? propertyId;
  final String scopeLabel;
  final DateTime month;
  /// 0 = Pending Expenses, 1 = Transactions.
  final int initialPage;
  const ExpenseActivityScreen({
    super.key,
    required this.propertyId,
    required this.scopeLabel,
    required this.month,
    this.initialPage = 0,
  });

  @override
  State<ExpenseActivityScreen> createState() => _ExpenseActivityScreenState();
}

class _ExpenseActivityScreenState extends State<ExpenseActivityScreen> {
  late Future<Map<String, dynamic>> _future;
  late DateTime _month;
  late final PageController _pageController;
  late int _page;
  String? _txnCategory; // Transactions category filter (null = All)

  @override
  void initState() {
    super.initState();
    _month = widget.month;
    _page = widget.initialPage;
    _pageController = PageController(initialPage: widget.initialPage);
    _future = _fetch();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String get _monthParam =>
      '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  Future<Map<String, dynamic>> _fetch() {
    final query = [
      if (widget.propertyId != null) 'propertyId=${widget.propertyId}',
      'month=$_monthParam',
    ].join('&');
    return context.read<AppState>().apiClient.get('/expenses/dashboard?$query');
  }

  // Block body: an arrow body would return the Future and trip setState's assert.
  void _reload() {
    setState(() {
      _future = _fetch();
    });
  }

  void _shiftMonth(int delta) {
    final next = DateTime(_month.year, _month.month + delta);
    final now = DateTime.now();
    if (next.isAfter(DateTime(now.year, now.month))) return;
    setState(() {
      _month = next;
      _txnCategory = null;
    });
    _reload();
  }

  void _selectPage(int index) => _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
      );

  void _toastSuccess(String msg, {String? title}) {
    if (!mounted) return;
    AppToast.success(context, msg, title: title);
  }

  void _toastError(String msg) {
    if (!mounted) return;
    AppToast.error(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PgColors.scaffold,
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Expense Activity',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            Text(widget.scopeLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11.5,
                    color: PgColors.textSecondary,
                    fontWeight: FontWeight.w500)),
          ],
        ),
        actions: [
          IconButton(
              onPressed: _reload, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddExpense,
        backgroundColor: PgColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Expense',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          final loading = snap.connectionState != ConnectionState.done;
          final pending = Map<String, dynamic>.from(
              (snap.data?['pendingApprovals'] as Map?) ?? const {});
          final txns = _listOfMaps(snap.data?['recentTransactions']);
          final count = (pending['count'] as num?)?.toInt() ?? 0;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                children: [
                  // Fixed: the month applies to both pages.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                    child: _monthBar(),
                  ),
                  _pageTabs(count),
                  // The pager stays mounted across reloads — swapping it for a
                  // skeleton detaches _pageController, which then restores to
                  // its initialPage and leaves the highlighted tab pointing at
                  // a different page than the one on screen.
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      onPageChanged: (i) => setState(() => _page = i),
                      children: [
                        _pageState(loading, snap.error,
                            () => _pendingPage(pending)),
                        _pageState(loading, snap.error,
                            () => _transactionsPage(txns)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Per-page loading/error wrapper, so the pager itself never leaves the tree.
  Widget _pageState(bool loading, Object? error, Widget Function() content) {
    if (loading) return const SkeletonList(showLeading: false);
    if (error != null) return ErrorRetryView(error: error, onRetry: _reload);
    return content();
  }

  Widget _monthBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: PgColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => _shiftMonth(-1),
            icon: const Icon(Icons.chevron_left_rounded,
                color: PgColors.textSecondary, size: 22),
          ),
          Text(DateFormat('MMMM yyyy').format(_month),
              style: const TextStyle(
                  color: PgColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: _isCurrentMonth ? null : () => _shiftMonth(1),
            icon: Icon(Icons.chevron_right_rounded,
                color: _isCurrentMonth
                    ? PgColors.hairline
                    : PgColors.textSecondary,
                size: 22),
          ),
        ],
      ),
    );
  }

  /// Segmented control mirroring the [PageView] — tap or swipe, both work.
  Widget _pageTabs(int pendingCount) {
    Widget tab(int index, String label, String? badge) {
      final selected = _page == index;
      return Expanded(
        child: InkWell(
          onTap: () => _selectPage(index),
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: selected ? PgColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? Colors.white
                              : PgColors.textSecondary)),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white.withValues(alpha: 0.25)
                          : PgColors.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(badge,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color:
                                selected ? Colors.white : PgColors.danger)),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PgColors.border),
      ),
      child: Row(
        children: [
          tab(0, 'Pending', pendingCount > 0 ? '$pendingCount' : null),
          tab(1, 'Transactions', null),
        ],
      ),
    );
  }

  Widget _pendingPage(Map<String, dynamic> pending) {
    return RefreshIndicator(
      onRefresh: () async {
        _reload();
        await _future;
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        children: [_buildApprovalsCard(pending)],
      ),
    );
  }

  Widget _transactionsPage(List<Map<String, dynamic>> txns) {
    final filtered = _txnCategory == null
        ? txns
        : [
            for (final t in txns)
              if ('${t['category']}' == _txnCategory) t
          ];
    return RefreshIndicator(
      onRefresh: () async {
        _reload();
        await _future;
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        children: [
          _SectionHeader('Transactions',
              subtitle: _isCurrentMonth
                  ? 'This month'
                  : DateFormat('MMMM yyyy').format(_month)),
          const SizedBox(height: 10),
          ..._txnFilterBar(txns),
          _buildTransactions(filtered),
        ],
      ),
    );
  }

  static List<Map<String, dynamic>> _listOfMaps(dynamic v) => [
        for (final e in (v as List? ?? const []))
          Map<String, dynamic>.from(e as Map),
      ];

  // ─────────────────────────────────────────────────────────────── sheets ──

  Future<void> _openAddExpense() async {
    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddExpenseSheet(
          propertyId: widget.propertyId, scopeLabel: widget.scopeLabel),
    );
    if (saved != null) {
      _toastSuccess(
          saved == 'pending'
              ? 'Expense recorded — awaiting approval'
              : 'Expense recorded',
          title: 'Expense Added');
      _reload();
    }
  }

  /// Fetches the full row (the dashboard payload omits vendor/notes/property),
  /// then reopens the expense sheet in edit mode.
  Future<void> _openEditExpense(Map<String, dynamic> txn) async {
    final messenger = ScaffoldMessenger.of(context);
    Map<String, dynamic> detail;
    try {
      detail = await context
          .read<AppState>()
          .apiClient
          .get('/expenses/${txn['expenseId']}');
    } catch (e) {
      AppToast.errorOf(messenger, e.toString().replaceFirst('Exception: ', ''));
      return;
    }
    if (!mounted) return;
    if (detail['editable'] == false) {
      _showLocked('Cannot Edit Expense', detail['lockedReason']);
      return;
    }
    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddExpenseSheet(
        propertyId: widget.propertyId,
        scopeLabel: widget.scopeLabel,
        expense: detail,
      ),
    );
    if (saved != null) {
      _toastSuccess('Expense updated', title: 'Expense Updated');
      _reload();
    }
  }

  Future<void> _deleteExpense(Map<String, dynamic> txn) async {
    final title = '${txn['title'] ?? 'this expense'}';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Expense?'),
        content: Text('$title · ${_inr(_num(txn['amount']))} will be removed '
            'from this month\'s totals.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PgColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context
          .read<AppState>()
          .apiClient
          .delete('/expenses/${txn['expenseId']}');
      AppToast.successOf(messenger, '$title was deleted',
          title: 'Expense Deleted');
      _reload();
    } catch (e) {
      if (mounted) {
        _showLocked('Cannot Delete Expense',
            e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  void _showLocked(String title, Object? reason) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text('${reason ?? 'This expense cannot be changed.'}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  // ─── moved from the landing page: approvals + transactions ───────────────
  // ──────────────────────────────────────────────────── pending approvals ──

  Widget _buildApprovalsCard(Map<String, dynamic> pending) {
    final count = (pending['count'] as num?)?.toInt() ?? 0;
    final items = _listOfMaps(pending['items']);
    return _LightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.pending_actions_rounded,
                    color: Color(0xFFD97706), size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Pending Expenses',
                    style: TextStyle(
                        color: PgColors.textPrimary,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: PgColors.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: PgColors.danger.withValues(alpha: 0.3)),
                ),
                child: Text('$count',
                    style: const TextStyle(
                        color: PgColors.danger,
                        fontSize: 14,
                        fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('All caught up — nothing waiting on you here.',
                  style:
                      TextStyle(color: PgColors.textSecondary, fontSize: 13)),
            )
          else
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0)
                const Divider(
                    color: PgColors.hairline, height: 22, thickness: 0.8),
              _approvalRow(items[i]),
            ],
        ],
      ),
    );
  }

  Widget _approvalRow(Map<String, dynamic> a) {
    final meta = _meta('${a['category']}');
    final vendor = '${a['vendorName'] ?? ''}';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${a['title']}',
                  style: const TextStyle(
                      color: PgColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(vendor.isEmpty ? meta.label : '${meta.label} · $vendor',
                  style: const TextStyle(
                      color: PgColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 3),
              Text(_inr(_num(a['amount'])),
                  style: const TextStyle(
                      color: PgColors.primary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        _PillButton(
          label: 'Approve',
          color: PgColors.success,
          onTap: () => _resolveApproval(a, approved: true),
        ),
        const SizedBox(width: 8),
        _PillButton(
          label: 'Reject',
          color: PgColors.danger,
          onTap: () => _resolveApproval(a, approved: false),
        ),
      ],
    );
  }

  Future<void> _resolveApproval(Map<String, dynamic> a,
      {required bool approved}) async {
    try {
      await context.read<AppState>().apiClient.patch(
          '/expenses/${a['expenseId']}/status',
          {'status': approved ? 'APPROVED' : 'REJECTED'});
      _toastSuccess(
          approved
              ? '${a['title']} approved · ${_inr(_num(a['amount']))}'
              : '${a['title']} rejected',
          title: approved ? 'Expense Approved' : 'Expense Rejected');
      _reload();
    } catch (e) {
      _toastError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  // ──────────────────────────────────────────────────────── transactions ──

  /// Category filter chips for Recent Transactions. Built from the categories
  /// actually present this month; hidden when there's nothing to filter.
  List<Widget> _txnFilterBar(List<Map<String, dynamic>> txns) {
    final cats = <String>[];
    for (final t in txns) {
      final c = '${t['category']}';
      if (!cats.contains(c)) cats.add(c);
    }
    if (cats.length < 2 && _txnCategory == null) return const [];
    return [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _txnFilterChip(null, 'All'),
            for (final c in cats) ...[
              const SizedBox(width: 8),
              _txnFilterChip(c, _meta(c).label),
            ],
          ],
        ),
      ),
      const SizedBox(height: 10),
    ];
  }

  Widget _txnFilterChip(String? value, String label) {
    final selected = _txnCategory == value;
    return InkWell(
      onTap: () => setState(() => _txnCategory = value),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? PgColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: selected ? PgColors.primary : PgColors.border),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : PgColors.textSecondary)),
      ),
    );
  }

  Widget _buildTransactions(List<Map<String, dynamic>> txns) {
    if (txns.isEmpty) {
      return _LightCard(
        child: _EmptyHint(
          icon: Icons.receipt_long_rounded,
          text: _txnCategory == null
              ? 'No expenses ${_isCurrentMonth ? 'this month' : 'in ${DateFormat('MMMM yyyy').format(_month)}'}.'
              : 'No ${_meta(_txnCategory).label} expenses ${_isCurrentMonth ? 'this month' : 'in ${DateFormat('MMMM yyyy').format(_month)}'}.',
          actionLabel: 'Add Expense',
          onAction: () => _openAddExpense(),
        ),
      );
    }
    return _LightCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < txns.length; i++) ...[
            if (i > 0)
              const Divider(
                  color: PgColors.hairline, height: 1, thickness: 0.8),
            _txnRow(txns[i]),
          ],
        ],
      ),
    );
  }

  Widget _txnRow(Map<String, dynamic> t) {
    final meta = _meta('${t['category']}');
    final method =
        _paymentMethods['${t['paymentMethod']}'] ?? '${t['paymentMethod']}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: meta.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(meta.icon, color: meta.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${t['title']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: PgColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 5),
                Row(
                  children: [
                    _Chip(label: method, color: PgColors.textSecondary),
                    const SizedBox(width: 6),
                    if (t['status'] == 'PENDING')
                      const _Chip(
                          label: 'Pending',
                          color: PgColors.warning,
                          icon: Icons.hourglass_top_rounded)
                    else
                      _Chip(
                          label: t['status'] == 'PAID' ? 'Paid' : 'Approved',
                          color: PgColors.success,
                          icon: Icons.check_circle_rounded),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('- ${_inr(_num(t['amount']))}',
                  style: const TextStyle(
                      color: PgColors.textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(_relative(t['expenseDate']),
                  style: const TextStyle(
                      color: PgColors.textTertiary, fontSize: 11.5)),
            ],
          ),
          // Fix a mis-keyed amount/category, or drop the row entirely.
          SizedBox(
            width: 28,
            child: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded,
                  size: 18, color: PgColors.textTertiary),
              padding: EdgeInsets.zero,
              tooltip: 'Expense actions',
              onSelected: (v) {
                if (v == 'edit') _openEditExpense(t);
                if (v == 'delete') _deleteExpense(t);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(children: [
                    Icon(Icons.edit_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('Edit'),
                  ]),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline, size: 18, color: PgColors.danger),
                    SizedBox(width: 8),
                    Text('Delete', style: TextStyle(color: PgColors.danger)),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────── bottom sheets ──

class _SheetScaffold extends StatelessWidget {
  final String title;
  final String scopeLabel;
  final List<Widget> children;
  const _SheetScaffold(
      {required this.title, required this.scopeLabel, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            color: PgColors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w700)),
                  ),
                  _Chip(
                      label: scopeLabel,
                      color: PgColors.primary,
                      icon: Icons.apartment_rounded),
                ],
              ),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _AddExpenseSheet extends StatefulWidget {
  final int? propertyId;
  final String scopeLabel;
  /// Detail payload from `GET /expenses/{id}` — set to edit instead of create.
  final Map<String, dynamic>? expense;
  const _AddExpenseSheet({
    required this.propertyId,
    required this.scopeLabel,
    this.expense,
  });

  @override
  State<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<_AddExpenseSheet> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _vendor = TextEditingController();
  final _description = TextEditingController();
  String _category = 'FOOD';
  String _method = 'CASH';
  DateTime _date = DateTime.now();
  bool _requiresApproval = false;
  bool _saving = false;

  bool get _isEdit => widget.expense != null;

  @override
  void initState() {
    super.initState();
    final e = widget.expense;
    if (e == null) return;
    _title.text = '${e['title'] ?? ''}';
    _amount.text = _num(e['amount']).toStringAsFixed(2);
    _vendor.text = '${e['vendorName'] ?? ''}';
    _description.text = '${e['description'] ?? ''}';
    if (_categoryMeta.containsKey('${e['category']}')) _category = '${e['category']}';
    if (_paymentMethods.containsKey('${e['paymentMethod']}')) _method = '${e['paymentMethod']}';
    final parsed = DateTime.tryParse('${e['expenseDate']}');
    if (parsed != null) _date = parsed;
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _vendor.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    // On edit, keep the expense on the property it was booked against — the sheet
    // may have been opened from the org-level screen.
    final propertyId = _isEdit
        ? (widget.expense!['propertyId'] as num?)?.toInt()
        : widget.propertyId;
    final body = {
      'title': _title.text.trim(),
      'category': _category,
      'amount': double.parse(_amount.text.trim()),
      'expenseDate': DateFormat('yyyy-MM-dd').format(_date),
      'paymentMethod': _method,
      if (propertyId != null) 'propertyId': propertyId,
      if (_vendor.text.trim().isNotEmpty) 'vendorName': _vendor.text.trim(),
      if (_description.text.trim().isNotEmpty)
        'description': _description.text.trim(),
      if (!_isEdit) 'requiresApproval': _requiresApproval,
    };
    try {
      final api = context.read<AppState>().apiClient;
      final res = _isEdit
          ? await api.put('/expenses/${widget.expense!['expenseId']}', body)
          : await api.post('/expenses', body);
      if (mounted) {
        Navigator.pop(
            context,
            _isEdit
                ? 'updated'
                : res['status'] == 'PENDING'
                    ? 'pending'
                    : 'approved');
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        AppToast.error(context, e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    // An older expense being corrected must stay inside the picker's range.
    final earliest = now.subtract(const Duration(days: 365));
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: _date.isBefore(earliest) ? _date : earliest,
      lastDate: _date.isAfter(now) ? _date : now,
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: _isEdit ? 'Edit Expense' : 'Add Expense',
      scopeLabel: widget.scopeLabel,
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(
                    labelText: 'Title', hintText: 'e.g. Electricity Bill'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Title is required' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _amount,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration:
                          const InputDecoration(labelText: 'Amount (₹)'),
                      validator: (v) {
                        final n = double.tryParse((v ?? '').trim());
                        if (n == null || n <= 0) return 'Enter a valid amount';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Date'),
                        child: Text(DateFormat('d MMM yyyy').format(_date)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final e in _categoryMeta.entries)
                    DropdownMenuItem(
                      value: e.key,
                      child: Row(
                        children: [
                          Icon(e.value.icon, color: e.value.color, size: 16),
                          const SizedBox(width: 9),
                          Text(e.value.label),
                        ],
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _method,
                decoration: const InputDecoration(labelText: 'Payment Method'),
                items: [
                  for (final e in _paymentMethods.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _method = v ?? _method),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _vendor,
                decoration: const InputDecoration(
                    labelText: 'Vendor (optional)',
                    hintText: 'e.g. Heritage Dairy'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                maxLines: 2,
                decoration:
                    const InputDecoration(labelText: 'Notes (optional)'),
              ),
              // Approval is a status change (PATCH /status), not part of an edit.
              if (!_isEdit)
                SwitchListTile(
                  value: _requiresApproval,
                  onChanged: (v) => setState(() => _requiresApproval = v),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Requires approval',
                      style: TextStyle(fontSize: 14)),
                  subtitle: const Text('Keep it pending until approved',
                      style: TextStyle(
                          fontSize: 12, color: PgColors.textSecondary)),
                )
              else
                const SizedBox(height: 12),
              const SizedBox(height: 6),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.4))
                    : Text(_isEdit ? 'Update Expense' : 'Save Expense',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SetBudgetSheet extends StatefulWidget {
  final int? propertyId;
  final String scopeLabel;
  const _SetBudgetSheet({required this.propertyId, required this.scopeLabel});

  @override
  State<_SetBudgetSheet> createState() => _SetBudgetSheetState();
}

class _SetBudgetSheetState extends State<_SetBudgetSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  /// Fixed to the overall monthly budget while the category picker is hidden.
  final String _category = 'ALL';
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await context.read<AppState>().apiClient.put('/expenses/budget', {
        if (widget.propertyId != null) 'propertyId': widget.propertyId,
        'category': _category,
        'amount': double.parse(_amount.text.trim()),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        AppToast.error(context, e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      title: 'Set Monthly Budget',
      scopeLabel: widget.scopeLabel,
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Per-category budgets are hidden for now — the sheet only sets
              // the overall monthly budget (`_category` stays 'ALL'). The
              // endpoint and `expense_budget` still accept a category, so
              // restoring this dropdown is all that's needed to bring them back.
              //
              // DropdownButtonFormField<String>(
              //   initialValue: _category,
              //   decoration: const InputDecoration(labelText: 'Budget for'),
              //   items: [
              //     const DropdownMenuItem(
              //         value: 'ALL', child: Text('Overall (this month)')),
              //     for (final e in _categoryMeta.entries)
              //       DropdownMenuItem(value: e.key, child: Text(e.value.label)),
              //   ],
              //   onChanged: (v) => setState(() => _category = v ?? _category),
              // ),
              // const SizedBox(height: 12),
              TextFormField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    const InputDecoration(labelText: 'Budget Amount (₹)'),
                validator: (v) {
                  final n = double.tryParse((v ?? '').trim());
                  if (n == null || n <= 0) return 'Enter a valid amount';
                  return null;
                },
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.4))
                    : const Text('Save Budget',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────── shared widgets ──

class _LightCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _LightCard({required this.child, this.padding = const EdgeInsets.all(18)});

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

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  const _SectionHeader(this.title, {this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(title,
              style: const TextStyle(
                  color: PgColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
        ),
        if (subtitle != null)
          Text(subtitle!,
              style: const TextStyle(
                  color: PgColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  /// Optional count pill (e.g. how many approvals are waiting).
  final String? badge;
  const _QuickActionChip(
      {required this.label,
      required this.icon,
      required this.color,
      required this.onTap,
      this.badge});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: PgColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: PgColors.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600)),
            ),
            if (badge != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(badge!,
                    style: TextStyle(
                        color: color,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _EmptyHint(
      {required this.icon, required this.text, this.actionLabel, this.onAction});

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

/// Rounded progress bar that animates from zero on first build.
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
