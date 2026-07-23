import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/animations.dart';
import '../widgets/error_retry_view.dart';
import '../widgets/skeleton.dart';

/// Unified money-in / money-out ledger for a month: tenant payments (in)
/// merged with approved expenses (out). Backed by `GET /api/transactions`.
///
/// Entry: the "Transactions" quick action on the property workspace Overview
/// tab (locked to that property). Also works org-wide when [propertyId] is
/// null. Month switcher mirrors StaffScreen/ExpensesScreen (future blocked).
class TransactionsScreen extends StatefulWidget {
  final int? propertyId;
  final String? propertyName;
  const TransactionsScreen({super.key, this.propertyId, this.propertyName});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

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

const Map<String, String> _methodLabels = {
  'CASH': 'Cash',
  'UPI': 'UPI',
  'CARD': 'Card',
  'DEBIT_CARD': 'Debit Card',
  'CREDIT_CARD': 'Credit Card',
  'CHEQUE': 'Cheque',
  'NET_BANKING': 'Net Banking',
  'WALLET': 'Wallet',
  'BANK_TRANSFER': 'Bank Transfer',
};

String _pretty(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  final known = _methodLabels[raw];
  if (known != null) return known;
  final lower = raw.toLowerCase().replaceAll('_', ' ');
  return lower[0].toUpperCase() + lower.substring(1);
}

DateTime? _parseDate(dynamic v) => v == null ? null : DateTime.tryParse('$v');

String _relative(dynamic v) {
  final d = _parseDate(v);
  if (d == null) return '';
  final now = DateTime.now();
  final diff = DateTime(now.year, now.month, now.day)
      .difference(DateTime(d.year, d.month, d.day))
      .inDays;
  if (diff <= 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateFormat('d MMM').format(d);
}

/// Time-of-day the transaction was recorded (from the `at` timestamp), e.g.
/// "2:47 PM". Empty when no timestamp is available.
String _timeOfDay(dynamic at) {
  final d = _parseDate(at);
  return d == null ? '' : DateFormat('h:mm a').format(d);
}

// ─────────────────────────────────────────────────────────────────── screen ──

class _TransactionsScreenState extends State<TransactionsScreen> {
  late Future<Map<String, dynamic>> _future;
  String? _typeFilter; // null = All, 'IN', 'OUT'
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  String get _scopeLabel => widget.propertyName ?? 'All Properties';

  String get _monthParam =>
      '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  void _reload() {
    setState(() {
      _future = _fetch();
    });
  }

  Future<Map<String, dynamic>> _fetch() {
    final query = [
      if (widget.propertyId != null) 'propertyId=${widget.propertyId}',
      'month=$_monthParam',
    ].join('&');
    return context.read<AppState>().apiClient.get('/transactions?$query');
  }

  void _shiftMonth(int delta) {
    final next = DateTime(_month.year, _month.month + delta);
    final now = DateTime.now();
    if (next.isAfter(DateTime(now.year, now.month))) return;
    setState(() {
      _month = next;
      _typeFilter = null;
    });
    _reload();
  }

  // ─────────────────────────────────────────────────────────────── build ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PgColors.scaffold,
      appBar: AppBar(
        title: const Text('Transactions',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
              onPressed: _reload, icon: const Icon(Icons.refresh_rounded)),
        ],
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
    final items = [
      for (final e in (d['items'] as List? ?? const []))
        Map<String, dynamic>.from(e as Map),
    ];
    final visible = _typeFilter == null
        ? items
        : [
            for (final i in items)
              if ('${i['type']}' == _typeFilter) i
          ];

    // Header, summary, and filter chips stay pinned; only the ledger scrolls.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FadeSlideIn(child: _buildHeaderRow()),
                  const SizedBox(height: 14),
                  FadeSlideIn(
                      delay: const Duration(milliseconds: 40),
                      child: _buildSummaryCard(summary)),
                  const SizedBox(height: 16),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 80),
                    child: Row(
                      children: [
                        _filterChip(null, 'All'),
                        const SizedBox(width: 8),
                        _filterChip('IN', 'Money In'),
                        const SizedBox(width: 8),
                        _filterChip('OUT', 'Money Out'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  _reload();
                  await _future;
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    FadeSlideIn(
                        delay: const Duration(milliseconds: 120),
                        child: _buildLedger(visible)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderRow() {
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
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
                  if (widget.propertyId != null) ...[
                    const SizedBox(width: 5),
                    const Icon(Icons.lock_rounded,
                        color: PgColors.textTertiary, size: 14),
                  ],
                ],
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

  Widget _buildSummaryCard(Map<String, dynamic> summary) {
    final totalIn = _num(summary['totalIn']);
    final totalOut = _num(summary['totalOut']);
    final net = _num(summary['net']);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PgColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _summaryStat('MONEY IN', totalIn, PgColors.success,
              prefix: '+', count: summary['countIn']),
          _vDivider(),
          _summaryStat('MONEY OUT', totalOut, PgColors.danger,
              prefix: '-', count: summary['countOut']),
          _vDivider(),
          _summaryStat(
              'NET', net, net >= 0 ? PgColors.success : PgColors.danger,
              prefix: net >= 0 ? '+' : '-'),
        ],
      ),
    );
  }

  Widget _vDivider() => Container(
      width: 1,
      height: 44,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: PgColors.hairline);

  Widget _summaryStat(String label, double value, Color color,
      {required String prefix, Object? count}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: PgColors.textSecondary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            // abs(): the sign lives in [prefix]; _inr would add its own '-'
            // for negative values, rendering "--₹x".
            child: Text('$prefix${_inr(value.abs())}',
                style: TextStyle(
                    color: color, fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 2),
          // Always occupy the third line so all three stats stay top-aligned
          // (NET has no count and would otherwise sit lower than the others).
          Text(count != null ? '$count txns' : '',
              style:
                  const TextStyle(color: PgColors.textTertiary, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _filterChip(String? value, String label) {
    final selected = _typeFilter == value;
    return InkWell(
      onTap: () => setState(() => _typeFilter = value),
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

  Widget _buildLedger(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      final what = _typeFilter == 'IN'
          ? 'payments'
          : _typeFilter == 'OUT'
              ? 'expenses'
              : 'transactions';
      final when = _isCurrentMonth
          ? 'this month'
          : 'in ${DateFormat('MMMM yyyy').format(_month)}';
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 36),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: PgColors.border),
        ),
        child: Column(
          children: [
            const Icon(Icons.receipt_long_rounded,
                color: PgColors.textTertiary, size: 34),
            const SizedBox(height: 10),
            Text('No $what $when.',
                style: const TextStyle(
                    color: PgColors.textSecondary, fontSize: 13.5)),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PgColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              const Divider(color: PgColors.hairline, height: 1, thickness: 0.8),
            _txnRow(items[i]),
          ],
        ],
      ),
    );
  }

  Widget _txnRow(Map<String, dynamic> t) {
    final isIn = '${t['type']}' == 'IN';
    final color = isIn ? PgColors.success : PgColors.danger;
    final subtitle = [
      _pretty('${t['method'] ?? ''}'),
      if (isIn) 'Payment received' else _pretty('${t['category'] ?? ''}'),
    ].where((s) => s.isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
                isIn ? Icons.south_west_rounded : Icons.north_east_rounded,
                color: color,
                size: 20),
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
                const SizedBox(height: 4),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: PgColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${isIn ? '+' : '-'} ${_inr(_num(t['amount']))}',
                  style: TextStyle(
                      color: color,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              // Day + time both come from the creation timestamp (`at`) so the
              // label matches the created-at sort order; fall back to the plain
              // date only when no timestamp is present.
              Text(_relative(t['at'] ?? t['date']),
                  style: const TextStyle(
                      color: PgColors.textTertiary, fontSize: 11.5)),
              if (_timeOfDay(t['at']).isNotEmpty) ...[
                const SizedBox(height: 1),
                Text(_timeOfDay(t['at']),
                    style: const TextStyle(
                        color: PgColors.textTertiary, fontSize: 10.5)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
