import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme/app_theme.dart';
import '../utils/money.dart';
import '../widgets/animations.dart';
import '../widgets/app_toast.dart';
import '../widgets/skeleton.dart';
import '../widgets/async_action_button.dart';
import '../widgets/error_retry_view.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

String _rupees(dynamic v) => inr(v ?? 0, nullText: '₹0');

/// "3 invoices" / "1 payment" — null when the backend didn't send a count.
String? _countLabel(dynamic v, String noun) {
  final n = v is num ? v.toInt() : int.tryParse('${v ?? ''}');
  if (n == null) return null;
  return '$n $noun${n == 1 ? '' : 's'}';
}

String _fmtDate(dynamic v) {
  if (v == null) return '—';
  try {
    final d = DateTime.parse('$v');
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day.toString().padLeft(2, '0')} ${m[d.month - 1]} ${d.year}';
  } catch (_) {
    return '$v';
  }
}

String _fmtMonth(dynamic v) {
  if (v == null) return '—';
  try {
    final parts = '$v'.split('-');
    if (parts.length < 2) return '$v';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final mi = int.parse(parts[1]) - 1;
    return '${m[mi.clamp(0, 11)]} ${parts[0]}';
  } catch (_) {
    return '$v';
  }
}

Color _statusColor(String? s) {
  switch (s?.toUpperCase()) {
    case 'PAID':
      return PgColors.success;
    case 'PENDING':
      return PgColors.warning;
    case 'OVERDUE':
      return PgColors.danger;
    case 'PARTIAL':
      return const Color(0xFF2563EB);
    default:
      return Colors.grey;
  }
}

Color _modeColor(String? mode) {
  switch (mode?.toUpperCase()) {
    case 'UPI':
      return const Color(0xFF7C3AED);
    case 'BANK_TRANSFER':
      return const Color(0xFF2563EB);
    case 'CHEQUE':
      return PgColors.warning;
    case 'WRITE_OFF':
      return const Color(0xFFF59E0B); // amber/yellow
    default:
      return PgColors.success; // CASH
  }
}

IconData _modeIcon(String? mode) {
  switch (mode?.toUpperCase()) {
    case 'UPI':
      return Icons.smartphone_outlined;
    case 'BANK_TRANSFER':
      return Icons.account_balance_outlined;
    case 'CHEQUE':
      return Icons.description_outlined;
    case 'WRITE_OFF':
      return Icons.remove_circle_outline;
    default:
      return Icons.payments_outlined; // CASH
  }
}

// ─── Billing Screen ───────────────────────────────────────────────────────

class BillingScreen extends StatefulWidget {
  final bool embedded;
  final int? propertyId;
  const BillingScreen({this.embedded = false, this.propertyId, super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late Future<Map<String, dynamic>> _dashFuture;
  late Future<Map<String, dynamic>> _invoicesFuture;
  int _paymentsRefreshTrigger = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _load() {
    final api = context.read<AppState>().apiClient;
    final pid = widget.propertyId;
    _dashFuture = api.get('/billing/dashboard${pid != null ? '?propertyId=$pid' : ''}');
    _invoicesFuture = api.get('/billing/invoices${pid != null ? '?propertyId=$pid' : ''}');
    _paymentsRefreshTrigger++;
  }

  Widget _buildBody() {
    return Column(
      children: [
        TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Dashboard'),
            Tab(text: 'Invoices'),
            Tab(text: 'Payments'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _DashboardTab(dashFuture: _dashFuture, onRefresh: () => setState(_load)),
              _InvoicesTab(
                invoicesFuture: _invoicesFuture,
                onRefresh: () => setState(_load),
                onCollect: _openCollect,
                onGenerate: _generateInvoices,
              ),
              _PaymentsTab(
                refreshTrigger: _paymentsRefreshTrigger,
                onCollect: _openCollect,
                propertyId: widget.propertyId,
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return FadeSlideIn(child: _buildBody());
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: PgColors.textPrimary,
        elevation: 0,
        title: const Text('Billing', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_card_outlined),
            tooltip: 'Collect Payment',
            onPressed: _openCollect,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: PgColors.hairline),
        ),
      ),
      body: FadeSlideIn(child: _buildBody()),
    );
  }

  void _openCollect() async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => CollectPaymentSheet(propertyId: widget.propertyId),
    );
    if (done == true) setState(_load);
  }

  // Raises only the invoices that fall due today (the backend filters on each
  // tenant's billing anniversary) — never a whole month at once.
  Future<void> _generateInvoices() async {
    final pid = widget.propertyId;
    final query = pid != null ? '?propertyId=$pid' : '';
    try {
      final result = await context.read<AppState>().apiClient
          .post('/billing/generate-invoices$query', {});
      if (mounted) {
        final gen = result['generated'] ?? 0;
        final skip = result['skipped'] ?? 0;
        if (gen is num && gen > 0) {
          AppToast.success(
              context, '$gen invoice(s) due today generated, $skip already existed.',
              title: 'Invoices Generated');
        } else if (skip is num && skip > 0) {
          AppToast.info(context, 'All invoices due today already exist.');
        } else {
          AppToast.info(context, 'No invoices are due today.');
        }
        setState(_load);
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }
}

// ─── Dashboard Tab ────────────────────────────────────────────────────────

class _DashboardTab extends StatefulWidget {
  const _DashboardTab({required this.dashFuture, required this.onRefresh});

  final Future<Map<String, dynamic>> dashFuture;
  final VoidCallback onRefresh;

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  // null = recent payments, 'outstanding' = outstanding today, 'overdue' = overdue
  String? _activeFilter;

  void _toggleFilter(String key) =>
      setState(() => _activeFilter = _activeFilter == key ? null : key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: widget.dashFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SkeletonList(showLeading: false);
        }
        if (snapshot.hasError) {
          return _BillingErrorState(error: snapshot.error, onRetry: widget.onRefresh);
        }
        final data = snapshot.data ?? {};

        final outstandingInvoices = (data['outstandingTodayInvoices'] is List
                ? data['outstandingTodayInvoices'] as List
                : [])
            .cast<Map<String, dynamic>>();
        final overdueInvoices = (data['overdueInvoices'] is List
                ? data['overdueInvoices'] as List
                : [])
            .cast<Map<String, dynamic>>();
        final todayPayments = (data['todayPayments'] is List
                ? data['todayPayments'] as List
                : [])
            .cast<Map<String, dynamic>>();

        final List<Map<String, dynamic>> filteredInvoices = _activeFilter == 'outstanding'
            ? outstandingInvoices
            : _activeFilter == 'overdue'
                ? overdueInvoices
                : [];

        return RefreshIndicator(
          onRefresh: () async => widget.onRefresh(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
            children: [
              // Row 1: Total Collected | Received Today
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'Total Collected',
                      value: _rupees(data['totalCollection']),
                      count: _countLabel(data['totalCollectionCount'], 'payment'),
                      icon: Icons.check_circle_outline,
                      color: PgColors.success,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatCard(
                      label: 'Received Today',
                      value: _rupees(data['receivedToday']),
                      count: _countLabel(todayPayments.length, 'payment'),
                      icon: Icons.calendar_month_outlined,
                      color: PgColors.primary,
                      selected: _activeFilter == 'payments',
                      onTap: () => _toggleFilter('payments'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Row 2: Outstanding Today | Overdue (tappable)
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'Outstanding Today',
                      value: _rupees(data['outstandingToday']),
                      count: _countLabel(outstandingInvoices.length, 'invoice'),
                      icon: Icons.warning_amber_outlined,
                      color: PgColors.warning,
                      selected: _activeFilter == 'outstanding',
                      onTap: () => _toggleFilter('outstanding'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatCard(
                      label: 'Overdue',
                      value: _rupees(data['overdue']),
                      count: _countLabel(overdueInvoices.length, 'invoice'),
                      icon: Icons.error_outline,
                      color: PgColors.danger,
                      selected: _activeFilter == 'overdue',
                      onTap: () => _toggleFilter('overdue'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Section header changes based on filter
              Row(
                children: [
                  Text(
                    _activeFilter == 'outstanding'
                        ? 'Outstanding Invoices'
                        : _activeFilter == 'overdue'
                            ? 'Overdue Invoices'
                            : _activeFilter == 'payments'
                                ? 'Payments Today'
                                : 'Recent Payments',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const Spacer(),
                  if (_activeFilter == null && data['recentPayments'] is List)
                    Text('${(data['recentPayments'] as List).length} records',
                        style: const TextStyle(color: Colors.grey, fontSize: 12))
                  else if (_activeFilter == 'payments')
                    Text('${todayPayments.length} record${todayPayments.length == 1 ? '' : 's'}',
                        style: const TextStyle(color: Colors.grey, fontSize: 12))
                  else if (_activeFilter != null)
                    Text('${filteredInvoices.length} record${filteredInvoices.length == 1 ? '' : 's'}',
                        style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 8),
              if (_activeFilter == 'payments') ...[
                if (todayPayments.isEmpty)
                  const _BillingEmptyState(
                    icon: Icons.payments_outlined,
                    title: 'No payments today',
                    message: 'Payments received today will appear here.',
                  )
                else
                  ...todayPayments.map((p) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _PaymentCard(payment: p),
                      )),
              ] else if (_activeFilter != null) ...[
                if (filteredInvoices.isEmpty)
                  _BillingEmptyState(
                    icon: Icons.task_alt,
                    title: _activeFilter == 'outstanding'
                        ? 'No outstanding invoices'
                        : 'No overdue invoices',
                    message: _activeFilter == 'outstanding'
                        ? 'All invoices have been paid.'
                        : 'Great — no invoices are past their due date.',
                    onAction: null,
                  )
                else
                  ...filteredInvoices.map((inv) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _DashboardInvoiceCard(
                          invoice: inv,
                          onRefresh: widget.onRefresh,
                        ),
                      )),
              ] else ...[
                if (data['recentPayments'] is List &&
                    (data['recentPayments'] as List).isNotEmpty)
                  ...(data['recentPayments'] as List)
                      .cast<Map<String, dynamic>>()
                      .take(10)
                      .map((p) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _PaymentCard(payment: p),
                          ))
                else
                  const _BillingEmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No payments yet',
                    message: 'Collected payments will appear here.',
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ─── Payments Tab ─────────────────────────────────────────────────────────

class _PaymentsTab extends StatefulWidget {
  const _PaymentsTab({
    required this.refreshTrigger,
    required this.onCollect,
    this.propertyId,
  });

  final int refreshTrigger;
  final VoidCallback onCollect;
  final int? propertyId;

  @override
  State<_PaymentsTab> createState() => _PaymentsTabState();
}

class _PaymentsTabState extends State<_PaymentsTab> {
  final _search = TextEditingController();
  String _query = '';
  late DateTime _fromDate;
  late DateTime _toDate;
  Future<Map<String, dynamic>>? _future;

  @override
  void initState() {
    super.initState();
    _toDate = DateTime.now();
    _fromDate = _toDate.subtract(const Duration(days: 30));
    _search.addListener(() => setState(() => _query = _search.text.toLowerCase()));
    _load();
  }

  @override
  void didUpdateWidget(_PaymentsTab old) {
    super.didUpdateWidget(old);
    if (widget.refreshTrigger != old.refreshTrigger) _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _isoDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _displayDate(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day.toString().padLeft(2,'0')} ${m[d.month-1]} ${d.year}';
  }

  void _load() {
    final from = _isoDate(_fromDate);
    final to   = _isoDate(_toDate);
    final pid  = widget.propertyId;
    setState(() {
      _future = context.read<AppState>().apiClient
          .get('/billing/payments?fromDate=$from&toDate=$to&size=500${pid != null ? '&propertyId=$pid' : ''}');
    });
  }

  Future<void> _showDateFilter() async {
    DateTime tempFrom = _fromDate;
    DateTime tempTo   = _toDate;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDs) => AlertDialog(
          title: const Text('Filter by Date'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.calendar_today_outlined),
                title: const Text('From Date'),
                subtitle: Text(_displayDate(tempFrom),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: tempFrom,
                    firstDate: DateTime(2020),
                    lastDate: tempTo,
                  );
                  if (picked != null) setDs(() => tempFrom = picked);
                },
              ),
              ListTile(
                leading: const Icon(Icons.calendar_month_outlined),
                title: const Text('To Date'),
                subtitle: Text(_displayDate(tempTo),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: tempTo,
                    firstDate: tempFrom,
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setDs(() => tempTo = picked);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _fromDate = tempFrom;
                _toDate   = tempTo;
                _load();
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  bool get _isCustomRange {
    final defaultFrom = DateTime.now().subtract(const Duration(days: 30));
    return (_fromDate.difference(defaultFrom).inDays).abs() > 1 ||
        _toDate.day != DateTime.now().day;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    hintText: 'Search by tenant, amount or date…',
                    prefixIcon: Icon(Icons.search),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: Icon(Icons.filter_list,
                        color: _isCustomRange ? PgColors.primary : Colors.grey.shade600),
                    tooltip: 'Filter by date range',
                    onPressed: _showDateFilter,
                  ),
                  if (_isCustomRange)
                    Positioned(
                      top: 8, right: 8,
                      child: Container(
                        width: 8, height: 8,
                        decoration: const BoxDecoration(
                          color: PgColors.primary, shape: BoxShape.circle),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Row(
            children: [
              const Icon(Icons.date_range, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text(
                '${_displayDate(_fromDate)}  –  ${_displayDate(_toDate)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: FutureBuilder<Map<String, dynamic>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _BillingErrorState(
                    error: snapshot.error, onRetry: _load);
              }
              final rawList = snapshot.data?['items'];
              final List raw = rawList is List ? rawList : [];
              final payments = raw.cast<Map<String, dynamic>>().where((p) {
                if (_query.isEmpty) return true;
                return '${p['full_name']}'.toLowerCase().contains(_query) ||
                    '${p['amount']}'.contains(_query) ||
                    _fmtDate(p['payment_date']).toLowerCase().contains(_query);
              }).toList();

              if (payments.isEmpty) {
                return _BillingEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No payments found',
                  message: _query.isNotEmpty
                      ? 'No payments match "$_query".'
                      : 'No payments in the selected date range.',
                  onAction: widget.onCollect,
                  actionLabel: 'Collect Payment',
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _load(),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
                  itemCount: payments.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => FadeSlideIn(
                    delay: Duration(milliseconds: 40 * (i.clamp(0, 8))),
                    child: _PaymentCard(payment: payments[i]),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── Invoices Tab ─────────────────────────────────────────────────────────

class _InvoicesTab extends StatefulWidget {
  const _InvoicesTab({
    required this.invoicesFuture,
    required this.onRefresh,
    required this.onCollect,
    required this.onGenerate,
  });

  final Future<Map<String, dynamic>> invoicesFuture;
  final VoidCallback onRefresh;
  final VoidCallback onCollect;
  final Future<void> Function() onGenerate;

  @override
  State<_InvoicesTab> createState() => _InvoicesTabState();
}

class _InvoicesTabState extends State<_InvoicesTab> {
  String _filter = 'ALL';
  bool _generating = false;
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() => _query = _search.text.toLowerCase()));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                  hintText: 'Search by tenant name…',
                  prefixIcon: Icon(Icons.search),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  // CANCELLED is the deleted-invoice bucket — it is the only way to find
                  // one again to restore it.
                  children: ['ALL', 'PENDING', 'PAID', 'PARTIAL', 'CANCELLED'].map((f) {
                    final selected = _filter == f;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(f),
                        selected: selected,
                        selectedColor: PgColors.lavender,
                        checkmarkColor: PgColors.primary,
                        labelStyle: TextStyle(
                            color: selected ? PgColors.primary : null,
                            fontWeight: selected ? FontWeight.w700 : null),
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<Map<String, dynamic>>(
                future: widget.invoicesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _BillingErrorState(error: snapshot.error, onRetry: widget.onRefresh);
                  }
                  final rawList = snapshot.data?['items'];
                  final List raw = rawList is List ? rawList : [];
                  final invoices = raw.cast<Map<String, dynamic>>().where((inv) {
                    final matchesFilter = _filter == 'ALL' || '${inv['status']}'.toUpperCase() == _filter;
                    final matchesSearch = _query.isEmpty ||
                        '${inv['full_name']}'.toLowerCase().contains(_query);
                    return matchesFilter && matchesSearch;
                  }).toList();

                  if (invoices.isEmpty) {
                    return _BillingEmptyState(
                      icon: Icons.description_outlined,
                      title: 'No invoices',
                      message: _query.isNotEmpty
                          ? 'No invoices match "$_query".'
                          : _filter == 'ALL'
                              ? 'Tap the button below to generate the invoices due today.'
                              : 'No ${_filter.toLowerCase()} invoices.',
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async => widget.onRefresh(),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                      itemCount: invoices.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => FadeSlideIn(
                        delay: Duration(milliseconds: 40 * (i.clamp(0, 8))),
                        child: _InvoiceCard(
                          invoice: invoices[i],
                          onCollect: widget.onCollect,
                          onRefresh: widget.onRefresh,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        // Generate invoices FAB — bottom right
        Positioned(
          bottom: 16,
          right: 16,
          child: _generating
              ? FloatingActionButton(
                  heroTag: 'generateInvoices',
                  onPressed: null,
                  backgroundColor: PgColors.primary,
                  child: const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                )
              : FloatingActionButton.extended(
                  heroTag: 'generateInvoices',
                  backgroundColor: PgColors.primary,
                  icon: const Icon(Icons.auto_awesome_outlined, color: Colors.white),
                  label: const Text('Generate', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  tooltip: 'Generate invoices due today',
                  onPressed: () async {
                    setState(() => _generating = true);
                    await widget.onGenerate();
                    if (mounted) setState(() => _generating = false);
                  },
                ),
        ),
      ],
    );
  }
}

// ─── Payment Card ─────────────────────────────────────────────────────────

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.payment});

  final Map<String, dynamic> payment;

  @override
  Widget build(BuildContext context) {
    final name = '${payment['full_name'] ?? 'Unknown'}';
    final amount = payment['amount'];
    final mode = '${payment['payment_mode'] ?? 'CASH'}';
    final date = _fmtDate(payment['payment_date']);
    final ref = payment['reference_number'];
    final color = _modeColor(mode);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.12),
              child: Icon(_modeIcon(mode), color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  Row(children: [
                    _ModeBadge(mode),
                    const SizedBox(width: 6),
                    Text(date, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                  ]),
                  if (ref != null && '$ref'.isNotEmpty)
                    Text('Ref: $ref', style: TextStyle(color: Colors.grey[400], fontSize: 11)),
                ],
              ),
            ),
            Text(
              _rupees(amount),
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeBadge extends StatelessWidget {
  final String mode;
  const _ModeBadge(this.mode);

  @override
  Widget build(BuildContext context) {
    final label = switch (mode.toUpperCase()) {
      'BANK_TRANSFER' => 'Bank',
      'UPI' => 'UPI',
      'CHEQUE' => 'Cheque',
      'WRITE_OFF' => 'Write Off',
      _ => 'Cash',
    };
    final color = _modeColor(mode);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

// ─── Invoice Card ─────────────────────────────────────────────────────────

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({required this.invoice, required this.onCollect, required this.onRefresh});

  final Map<String, dynamic> invoice;
  final VoidCallback onCollect;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final name = '${invoice['full_name'] ?? 'Unknown'}';
    final total = invoice['total_amount'];
    final paid = invoice['paid_amount'];
    final status = '${invoice['status'] ?? 'PENDING'}';
    final color = _statusColor(status);
    final month = _fmtMonth(invoice['invoice_month']);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showDetail(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(Icons.receipt_outlined, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    Text(month,
                        style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    Text('Due: ${_fmtDate(invoice['due_date'])}',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_rupees(total),
                      style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 15)),
                  if (paid != null)
                    Text('Paid: ${_rupees(paid)}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(status,
                        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => InvoiceDetailSheet(
        invoice: invoice,
        onRefresh: onRefresh,
      ),
    );
  }
}

// ─── Invoice Detail Sheet ─────────────────────────────────────────────────

class InvoiceDetailSheet extends StatefulWidget {
  const InvoiceDetailSheet({required this.invoice, required this.onRefresh});

  final Map<String, dynamic> invoice;
  final VoidCallback onRefresh;

  @override
  State<InvoiceDetailSheet> createState() => _InvoiceDetailSheetState();
}

class _InvoiceDetailSheetState extends State<InvoiceDetailSheet> {
  Map<String, dynamic> get invoice => widget.invoice;

  // Line items (PG rent / AC charges / security deposit …) fetched from the
  // invoice detail endpoint so the sheet can explain how the total is made up.
  List<Map<String, dynamic>>? _items;
  bool _itemsLoading = true;
  bool _busy = false;

  // Status is held locally, not read from widget.invoice, because deleting and
  // restoring flip it while the sheet stays open — the parent list only catches up
  // on the next refresh.
  late String _status;

  @override
  void initState() {
    super.initState();
    _status = '${invoice['status'] ?? 'PENDING'}';
    _loadItems();
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Invoice'),
        content: Text(
            'Delete the ${_fmtMonth(invoice['invoice_month'])} invoice for ${invoice['full_name'] ?? 'this tenant'}?\n\n'
            'It stops counting towards dues, and this month will not be raised again automatically. '
            'You can restore it from here or from the Cancelled filter.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PgColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await context
          .read<AppState>()
          .apiClient
          .delete('/billing/invoices/${invoice['invoice_id']}');
      if (!mounted) return;
      // Deliberately keep the sheet open on the now-cancelled invoice, so Restore is
      // right where the owner just deleted it.
      setState(() {
        _status = 'CANCELLED';
        _busy = false;
      });
      widget.onRefresh();
      AppToast.success(context, 'Invoice deleted — you can restore it below');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppToast.error(context, '$e'.replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      await context
          .read<AppState>()
          .apiClient
          .post('/billing/invoices/${invoice['invoice_id']}/restore', const {});
      if (!mounted) return;
      setState(() {
        _status = 'PENDING';
        _busy = false;
      });
      widget.onRefresh();
      AppToast.success(context, 'Invoice restored');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppToast.error(context, '$e'.replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _editAmount() async {
    // Every charge line (PG rent / AC charges / security deposit / …) is
    // edited individually; the invoice total is their live sum.
    var items = _items;
    if (items == null) {
      try {
        final res = await context
            .read<AppState>()
            .apiClient
            .get('/billing/invoices/${invoice['invoice_id']}');
        items = (res['items'] is List ? res['items'] as List : [])
            .cast<Map<String, dynamic>>();
      } catch (_) {}
    }
    if (!mounted) return;
    if (items == null || items.isEmpty) {
      AppToast.error(context, 'Charge details are not available to edit');
      return;
    }
    final lineItems = items;
    final controllers = [
      for (final it in lineItems)
        TextEditingController(text: '${it['amount'] ?? 0}'),
    ];
    final formKey = GlobalKey<FormState>();

    num currentTotal() {
      num t = 0;
      for (final c in controllers) {
        t += num.tryParse(c.text.trim()) ?? 0;
      }
      return t;
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Edit Invoice Amount'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 0; i < lineItems.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextFormField(
                        controller: controllers[i],
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: _itemLabel(lineItems[i]),
                          prefixText: '₹ ',
                          isDense: true,
                        ),
                        onChanged: (_) => setDialogState(() {}),
                        validator: (v) {
                          final n = num.tryParse((v ?? '').trim());
                          if (n == null || n < 0) return 'Invalid amount';
                          return null;
                        },
                      ),
                    ),
                  const Divider(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('Total',
                              style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                        Text(_rupees(currentTotal()),
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: PgColors.primary)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: PgColors.primary.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: PgColors.primary.withValues(alpha: 0.2)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline,
                            size: 18, color: PgColors.primary),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This changes only this month\'s invoice — not the tenant\'s master rent. '
                            'No partial payment can be created; this is the final amount for this month\'s rent.',
                            style: TextStyle(
                                fontSize: 12,
                                height: 1.3,
                                color: PgColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                if (currentTotal() <= 0) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final payloadItems = [
      for (int i = 0; i < lineItems.length; i++)
        {
          'invoiceItemId': lineItems[i]['invoice_item_id'],
          'amount': num.parse(controllers[i].text.trim()),
        },
    ];
    try {
      await context.read<AppState>().apiClient.patch(
        '/billing/invoices/${invoice['invoice_id']}/amount',
        {'items': payloadItems},
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onRefresh();
      AppToast.successOf(messenger, 'Invoice amount updated');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, '$e'.replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _loadItems() async {
    try {
      final res = await context
          .read<AppState>()
          .apiClient
          .get('/billing/invoices/${invoice['invoice_id']}');
      final items = (res['items'] is List ? res['items'] as List : [])
          .cast<Map<String, dynamic>>();
      if (mounted) {
        setState(() {
          _items = items;
          _itemsLoading = false;
        });
      }
    } catch (_) {
      // Breakdown is a nice-to-have — the sheet still shows the total.
      if (mounted) setState(() => _itemsLoading = false);
    }
  }

  String _itemLabel(Map<String, dynamic> item) {
    switch ('${item['item_type_id']}') {
      case 'MONTHLY_RENT':
        return 'PG Rent';
      case 'AC_CHARGES':
        return 'AC Charges';
      case 'SECURITY_DEPOSIT':
        return 'Security Deposit (one-time)';
      default:
        final desc = '${item['description'] ?? ''}';
        return desc.isNotEmpty ? desc : '${item['item_type_id']}';
    }
  }

  Widget _chargesBreakdown(dynamic total) {
    final items = _items ?? const <Map<String, dynamic>>[];
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Charge Details',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey,
                  letterSpacing: 0.4)),
          const SizedBox(height: 8),
          if (_itemsLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(_itemLabel(item),
                          style: const TextStyle(
                              fontSize: 13, color: PgColors.textSecondary)),
                    ),
                    Text(_rupees(item['amount']),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
          const Divider(height: 14),
          Row(
            children: [
              const Expanded(
                child: Text('Total',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              ),
              Text(_rupees(total),
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: PgColors.primary)),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = '${invoice['full_name'] ?? 'Unknown'}';
    final total = invoice['total_amount'];
    final paid = invoice['paid_amount'];
    final balance = invoice['balance'];
    final status = _status;
    final color = _statusColor(status);
    final canPay = status == 'PENDING' || status == 'PARTIAL' || status == 'OVERDUE';
    // Only a fresh, unpaid invoice can be re-priced — anything already paid or
    // cancelled keeps its amount.
    final canEdit = status == 'PENDING' && (paid is num ? paid == 0 : true);
    // Delete is pending-only and reversible; an overdue or part-paid invoice must be
    // written off instead, so the server rejects it and the icon is not offered.
    final canDelete = canEdit;
    final canRestore = status == 'CANCELLED';

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Text('Invoice', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const Spacer(),
            if (canEdit)
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                color: PgColors.primary,
                tooltip: 'Edit Amount',
                style: IconButton.styleFrom(
                  backgroundColor: PgColors.primary.withValues(alpha: 0.1),
                ),
                onPressed: _busy ? null : _editAmount,
              ),
            if (canEdit) const SizedBox(width: 8),
            if (canDelete)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                color: PgColors.danger,
                tooltip: 'Delete Invoice',
                style: IconButton.styleFrom(
                  backgroundColor: PgColors.danger.withValues(alpha: 0.1),
                ),
                onPressed: _busy ? null : _confirmDelete,
              ),
            const SizedBox(width: 8),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 4),
          _DetailRow('Tenant', name),
          _DetailRow('Month', _fmtMonth(invoice['invoice_month'])),
          _DetailRow('Due Date', _fmtDate(invoice['due_date'])),
          _StatusRow('Status', status, color),
          _chargesBreakdown(total),
          _DetailRow('Paid', _rupees(paid)),
          _DetailRow('Balance', _rupees(balance), color: (balance is num && balance > 0) ? PgColors.danger : PgColors.success),
          const SizedBox(height: 20),
          if (canRestore) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: PgColors.textSecondary),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This invoice is deleted, so it is not counted in dues or collections. '
                      'Nothing was erased — restoring puts it back as pending.',
                      style: TextStyle(
                          fontSize: 12, height: 1.3, color: PgColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.restore),
              label: const Text('Restore Invoice'),
              onPressed: _busy ? null : _restore,
            ),
          ],
          if (canPay)
            FilledButton.icon(
              icon: const Icon(Icons.payments_outlined),
              label: Text('Collect Payment · ${_rupees(balance)}'),
              onPressed: () {
                Navigator.pop(context);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  builder: (_) => CollectPaymentSheet(preselectedInvoice: invoice),
                ).then((done) { if (done == true) widget.onRefresh(); });
              },
            ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value, {this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 100, child: Text(label, style: const TextStyle(color: Colors.grey))),
          Expanded(
            child: Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow(this.label, this.status, this.color);
  final String label;
  final String status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 100, child: Text(label, style: const TextStyle(color: Colors.grey))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Text(status, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ─── Collect Payment Sheet ────────────────────────────────────────────────

class CollectPaymentSheet extends StatefulWidget {
  const CollectPaymentSheet({this.preselectedInvoice, this.propertyId});
  final Map<String, dynamic>? preselectedInvoice;
  final int? propertyId;

  @override
  State<CollectPaymentSheet> createState() => CollectPaymentSheetState();
}

class CollectPaymentSheetState extends State<CollectPaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _ref = TextEditingController();
  final _notes = TextEditingController();
  String _mode = 'CASH';
  int _step = 0;
  Map<String, dynamic>? _selectedInvoice;
  late Future<Map<String, dynamic>> _invoiceFuture;

  bool get _needsRef => _mode == 'UPI' || _mode == 'BANK_TRANSFER' || _mode == 'CHEQUE';

  @override
  void initState() {
    super.initState();
    final pid = widget.propertyId;
    _invoiceFuture = context.read<AppState>().apiClient
        .get('/billing/invoices?size=100${pid != null ? '&propertyId=$pid' : ''}');
    if (widget.preselectedInvoice != null) {
      _selectedInvoice = widget.preselectedInvoice;
      _step = 1;
      _prefillAmount(widget.preselectedInvoice!);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _ref.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _prefillAmount(Map<String, dynamic> inv) {
    final total = inv['total_amount'] ?? inv['totalAmount'];
    final paid = inv['paid_amount'] ?? inv['paidAmount'];
    if (total != null) {
      final remaining = (total as num) - ((paid as num?) ?? 0);
      _amount.text = remaining > 0 ? remaining.toStringAsFixed(0) : '0';
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, padding + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Text(
                _step == 0 ? 'Select Invoice' : 'Payment Details',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 16),
            if (_step == 0) _buildInvoiceList(),
            if (_step == 1) _buildPaymentForm(),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoiceList() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _invoiceFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final rawList = snapshot.data?['items'];
        final List raw = rawList is List ? rawList : [];
        final open = raw.cast<Map<String, dynamic>>().where((inv) {
          final s = '${inv['status']}'.toUpperCase();
          return s == 'PENDING' || s == 'PARTIAL' || s == 'OVERDUE';
        }).toList();

        if (open.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text('No open invoices found.\nGenerate invoices first.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey)),
            ),
          );
        }

        return Column(
          children: [
            ...open.map((inv) {
              final name = '${inv['full_name'] ?? 'Unknown'}';
              final balance = (inv['total_amount'] as num? ?? 0) - (inv['paid_amount'] as num? ?? 0);
              final status = '${inv['status']}';
              final color = _statusColor(status);
              final selected = _selectedInvoice == inv;
              return Card(
                color: selected ? PgColors.lavender : null,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => setState(() => _selectedInvoice = inv),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Radio<Map<String, dynamic>>(
                          value: inv,
                          groupValue: _selectedInvoice,
                          onChanged: (v) => setState(() => _selectedInvoice = v),
                          activeColor: PgColors.primary,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text('${_fmtMonth(inv['invoice_month'])} · Balance: ${_rupees(balance)}',
                                  style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(status,
                              style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _selectedInvoice == null
                  ? null
                  : () {
                      _prefillAmount(_selectedInvoice!);
                      setState(() => _step = 1);
                    },
              child: const Text('Next →'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPaymentForm() {
    final inv = _selectedInvoice;
    final name = inv != null ? '${inv['full_name'] ?? ''}' : '';
    final month = inv != null ? _fmtMonth(inv['invoice_month']) : '';

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Invoice summary chip
          if (inv != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: PgColors.lavender,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.receipt_outlined, color: PgColors.primary, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(month, style: const TextStyle(fontSize: 12, color: PgColors.primary)),
                      ],
                    ),
                  ),
                  Text(_rupees(inv['total_amount']),
                      style: const TextStyle(fontWeight: FontWeight.w800, color: PgColors.primary)),
                ],
              ),
            ),
          const SizedBox(height: 16),
          // Payment mode selector
          const Text('Payment Mode', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 8),
          _ModeSelector(
            selected: _mode,
            onChanged: (m) => setState(() => _mode = m),
          ),
          const SizedBox(height: 14),
          // Amount
          TextFormField(
            controller: _amount,
            decoration: const InputDecoration(
              labelText: 'Amount *',
              prefixIcon: Icon(Icons.currency_rupee),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            validator: (v) {
              final d = double.tryParse(v ?? '');
              return d == null || d <= 0 ? 'Enter a valid amount' : null;
            },
          ),
          const SizedBox(height: 12),
          // Reference number (required for non-cash)
          if (_needsRef) ...[
            TextFormField(
              controller: _ref,
              decoration: InputDecoration(
                labelText: _mode == 'UPI' ? 'UPI Reference / UTR *' :
                           _mode == 'CHEQUE' ? 'Cheque Number *' : 'Transaction Reference *',
                prefixIcon: const Icon(Icons.tag_outlined),
              ),
              validator: (v) =>
                  _needsRef && (v == null || v.trim().isEmpty) ? 'Reference number is required' : null,
            ),
            const SizedBox(height: 12),
          ],
          // Notes
          TextFormField(
            controller: _notes,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              prefixIcon: Icon(Icons.notes_outlined),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 20),
          Row(children: [
            // "Back" returns to the invoice picker (step 0). When the sheet was
            // opened with a preselected invoice there is no picker to go back to,
            // so hide it and let Confirm take the full width.
            if (widget.preselectedInvoice == null) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _step = 0),
                  child: const Text('← Back'),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: AsyncActionButton(
                label: 'Confirm',
                onPressed: () async {
                  if (!_formKey.currentState!.validate()) return;
                  final invoiceId = _selectedInvoice?['invoice_id'] ?? _selectedInvoice?['invoiceId'];
                  final idempotencyKey =
                      '$invoiceId-${_amount.text}-$_mode-${DateTime.now().millisecondsSinceEpoch}';
                  try {
                    await context.read<AppState>().apiClient.post('/billing/payments', {
                      'invoiceId': invoiceId,
                      'amount': double.parse(_amount.text),
                      'paymentMode': _mode,
                      if (_ref.text.isNotEmpty) 'referenceNumber': _ref.text.trim(),
                      if (_notes.text.isNotEmpty) 'notes': _notes.text.trim(),
                      'idempotencyKey': idempotencyKey,
                    });
                    if (mounted) {
                      final messenger = ScaffoldMessenger.of(context);
                      Navigator.pop(context, true);
                      AppToast.successOf(
                          messenger, 'Payment of ₹${_amount.text} recorded',
                          title: 'Payment Collected');
                    }
                  } catch (e) {
                    if (mounted) {
                      AppToast.error(
                          context, e.toString().replaceFirst('Exception: ', ''));
                    }
                  }
                },
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

// ─── Mode Selector ────────────────────────────────────────────────────────

class _ModeSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _ModeSelector({required this.selected, required this.onChanged});

  static const _modes = [
    ('CASH', 'Cash', Icons.payments_outlined),
    ('UPI', 'UPI', Icons.smartphone_outlined),
    ('BANK_TRANSFER', 'Bank', Icons.account_balance_outlined),
    ('CHEQUE', 'Cheque', Icons.description_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _modes.map((m) {
        final isSelected = selected == m.$1;
        final color = _modeColor(m.$1);
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () => onChanged(m.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? color.withValues(alpha: 0.12) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? color : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(m.$3, color: isSelected ? color : Colors.grey, size: 20),
                    const SizedBox(height: 4),
                    Text(m.$2,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                            color: isSelected ? color : Colors.grey)),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.count,
    this.onTap,
    this.selected = false,
  });

  final String label;
  final String value;
  /// Optional "3 invoices" / "5 payments" line under the label.
  final String? count;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, color.withValues(alpha: selected ? 0.12 : 0.05)],
        ),
        border: Border.all(
          color: selected ? color : color.withValues(alpha: 0.16),
          width: selected ? 1.6 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: selected
                ? color.withValues(alpha: 0.22)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: selected ? 14 : 8,
            offset: Offset(0, selected ? 6 : 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          splashColor: onTap != null ? color.withValues(alpha: 0.18) : null,
          highlightColor: onTap != null ? color.withValues(alpha: 0.1) : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: selected ? 0.22 : 0.13),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(icon, color: color, size: 18),
                    ),
                    if (count != null)
                      // Flexible + scaleDown: the card is half the screen wide,
                      // so the pill shrinks rather than overflowing the row.
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: _countPill(),
                          ),
                        ),
                      ),
                    if (onTap != null)
                      AnimatedRotation(
                        turns: selected ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: Icon(
                          Icons.keyboard_arrow_down,
                          size: 18,
                          color: selected ? color : Colors.grey.shade400,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 19,
                      letterSpacing: -0.4,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _countPill() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              count!,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
}

class _DashboardInvoiceCard extends StatelessWidget {
  const _DashboardInvoiceCard({required this.invoice, required this.onRefresh});
  final Map<String, dynamic> invoice;
  final VoidCallback onRefresh;

  void _openDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => InvoiceDetailSheet(invoice: invoice, onRefresh: onRefresh),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = '${invoice['full_name'] ?? '—'}';
    final balance = invoice['balance'];
    final status = '${invoice['status'] ?? ''}';
    final dueDate = _fmtDate(invoice['due_date']);
    final statusColor = _statusColor(status);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDetail(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: statusColor.withValues(alpha: 0.12),
                child: Icon(Icons.receipt_outlined, color: statusColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(status,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: statusColor)),
                        ),
                        const SizedBox(width: 6),
                        Text('Due $dueDate',
                            style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
              Text(_rupees(balance),
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: statusColor)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BillingErrorState extends StatelessWidget {
  const _BillingErrorState({required this.error, required this.onRetry});
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) =>
      ErrorRetryView(error: error ?? Exception('Unknown error'), onRetry: onRetry);
}

class _BillingEmptyState extends StatelessWidget {
  const _BillingEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.onAction,
    this.actionLabel,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onAction;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: PgColors.primary),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
            if (onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: Text(actionLabel ?? 'Go'),
                onPressed: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
