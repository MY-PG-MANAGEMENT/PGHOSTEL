import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/async_action_button.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

String _rupees(dynamic v) {
  if (v == null) return '₹0';
  final n = v is num ? v : num.tryParse('$v') ?? 0;
  return '₹${n % 1 == 0 ? n.toInt() : n}';
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
            Tab(text: 'Payments'),
            Tab(text: 'Invoices'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _DashboardTab(dashFuture: _dashFuture, onRefresh: () => setState(_load)),
              _PaymentsTab(
                refreshTrigger: _paymentsRefreshTrigger,
                onCollect: _openCollect,
                propertyId: widget.propertyId,
              ),
              _InvoicesTab(
                invoicesFuture: _invoicesFuture,
                onRefresh: () => setState(_load),
                onCollect: _openCollect,
                onGenerate: _generateInvoices,
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
      return _buildBody();
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A2E),
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
          child: Container(height: 1, color: const Color(0xFFE5E7EB)),
        ),
      ),
      body: _buildBody(),
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

  Future<void> _generateInvoices() async {
    final now = DateTime.now();
    final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    try {
      final result = await context.read<AppState>().apiClient
          .post('/billing/generate-invoices?month=$month', {});
      if (mounted) {
        final gen = result['generated'] ?? 0;
        final skip = result['skipped'] ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$gen invoice(s) generated, $skip already existed.'),
          backgroundColor: gen > 0 ? PgColors.success : Colors.grey,
        ));
        setState(_load);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: PgColors.danger,
        ));
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
          return const Center(child: CircularProgressIndicator());
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
                      icon: Icons.check_circle_outline,
                      color: PgColors.success,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatCard(
                      label: 'Received Today',
                      value: _rupees(data['receivedToday']),
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
                  itemBuilder: (_, i) => _PaymentCard(payment: payments[i]),
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
                  children: ['ALL', 'PENDING', 'PAID', 'PARTIAL'].map((f) {
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
                              ? 'Tap the button below to generate invoices for active tenants.'
                              : 'No ${_filter.toLowerCase()} invoices.',
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async => widget.onRefresh(),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                      itemCount: invoices.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => _InvoiceCard(
                        invoice: invoices[i],
                        onCollect: widget.onCollect,
                        onRefresh: widget.onRefresh,
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
                  tooltip: 'Generate invoices for this month',
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
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: PgColors.success),
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

class InvoiceDetailSheet extends StatelessWidget {
  const InvoiceDetailSheet({required this.invoice, required this.onRefresh});

  final Map<String, dynamic> invoice;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final name = '${invoice['full_name'] ?? 'Unknown'}';
    final total = invoice['total_amount'];
    final paid = invoice['paid_amount'];
    final balance = invoice['balance'];
    final status = '${invoice['status'] ?? 'PENDING'}';
    final color = _statusColor(status);
    final canPay = status == 'PENDING' || status == 'PARTIAL' || status == 'OVERDUE';

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Text('Invoice', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Text(status, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
            ),
            const SizedBox(width: 8),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 4),
          _DetailRow('Tenant', name),
          _DetailRow('Month', _fmtMonth(invoice['invoice_month'])),
          _DetailRow('Due Date', _fmtDate(invoice['due_date'])),
          _DetailRow('Total', _rupees(total)),
          _DetailRow('Paid', _rupees(paid)),
          _DetailRow('Balance', _rupees(balance), color: (balance is num && balance > 0) ? PgColors.danger : PgColors.success),
          const SizedBox(height: 20),
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
                ).then((done) { if (done == true) onRefresh(); });
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
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _step = 0),
                child: const Text('← Back'),
              ),
            ),
            const SizedBox(width: 12),
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
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Payment recorded successfully'),
                        backgroundColor: PgColors.success,
                      ));
                      Navigator.pop(context, true);
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(e.toString().replaceFirst('Exception: ', '')),
                        backgroundColor: PgColors.danger,
                      ));
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
    this.onTap,
    this.selected = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: selected ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: selected
            ? BorderSide(color: color, width: 2)
            : BorderSide.none,
      ),
      color: selected ? color.withValues(alpha: 0.06) : Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        splashColor: onTap != null ? color.withValues(alpha: 0.18) : null,
        highlightColor: onTap != null ? color.withValues(alpha: 0.1) : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: color.withValues(alpha: selected ? 0.2 : 0.12),
                    child: Icon(icon, color: color, size: 18),
                  ),
                  if (onTap != null) ...[
                    const Spacer(),
                    Icon(
                      selected ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      size: 16,
                      color: Colors.grey.shade400,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Text(value,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: color)),
              Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
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
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 48, color: PgColors.danger),
          const SizedBox(height: 12),
          const Text('Could not load data', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
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
