import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme/app_theme.dart';
import '../utils/money.dart';
import '../widgets/animations.dart';
import '../widgets/app_toast.dart';
import '../widgets/async_action_button.dart';
import '../widgets/error_retry_view.dart';
import '../widgets/skeleton.dart';
import 'billing_screen.dart' show CollectPaymentSheet;
import 'tenant_screen.dart' show AddTenantScreen;

/// Property-scoped Temporary Stay management. Lists temporary-stay guests for the
/// property (backed by `GET /api/occupancy/temp-stays`), with a summary, search,
/// status filters, and per-booking actions (Edit, Extend, Checkout, Call). New
/// bookings and edits price the stay from the Price Master per-day rate
/// (`days * perDayPrice`, editable) and reuse the existing temp-stay / invoice
/// flow. Reached from the property workspace "Temporary Stay" quick action.
class TemporaryStayScreen extends StatefulWidget {
  final int propertyId;
  final String? propertyName;
  const TemporaryStayScreen({super.key, required this.propertyId, this.propertyName});

  @override
  State<TemporaryStayScreen> createState() => _TemporaryStayScreenState();
}

class _TemporaryStayScreenState extends State<TemporaryStayScreen> {
  // TEMP_BED / TEMP_STAY are a type dimension (allocation vs day-wise stay),
  // ACTIVE / CHECKOUT_TODAY are booking status. All applied client-side.
  static const _filters = [
    ('ALL', 'All'),
    ('ACTIVE', 'Active'),
    ('TEMP_STAY', 'Temporary Stay'),
    ('TEMP_BED', 'Temporary Bed'),
    ('CHECKOUT_TODAY', 'Checkout Today'),
  ];

  Future<Map<String, dynamic>>? _future;
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _status = 'ACTIVE'; // screen opens showing active stays

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _load() {
    // Fetch the full property set once; search AND the filter chips are applied
    // client-side (see build) so switching filters is instant with no refetch.
    _future = context
        .read<AppState>()
        .apiClient
        .get('/occupancy/temp-stays?propertyId=${widget.propertyId}');
  }

  void _reload() => setState(_load);

  // Live, partial-match search over name / mobile / bed location.
  List<Map<String, dynamic>> _applySearch(List<Map<String, dynamic>> items) {
    if (_query.isEmpty) return items;
    return items.where((it) {
      final hay = [
        it['fullName'],
        it['mobileNumber'],
        it['floorName'],
        it['roomName'],
        it['bedName'],
      ].where((e) => e != null).map((e) => '$e'.toLowerCase()).join(' ');
      return hay.contains(_query);
    }).toList();
  }

  // Filter chip: TEMP_BED = allocation (no checkout date), TEMP_STAY = day-wise
  // stay (has a checkout date), ACTIVE / CHECKOUT_TODAY = booking status.
  List<Map<String, dynamic>> _applyFilter(List<Map<String, dynamic>> items) {
    switch (_status) {
      case 'TEMP_BED':
        return items.where((it) => it['checkOutDate'] == null).toList();
      case 'TEMP_STAY':
        return items.where((it) => it['checkOutDate'] != null).toList();
      case 'ACTIVE':
        return items.where((it) => '${it['bookingStatus']}' == 'ACTIVE').toList();
      case 'CHECKOUT_TODAY':
        return items.where((it) => '${it['bookingStatus']}' == 'CHECKOUT_TODAY').toList();
      default: // ALL
        return items;
    }
  }

  Future<void> _openForm({Map<String, dynamic>? existing}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _TempStayFormScreen(
          propertyId: widget.propertyId,
          existing: existing,
        ),
      ),
    );
    if (saved == true && mounted) _reload();
  }

  Future<void> _checkout(Map<String, dynamic> item) async {
    final name = '${item['fullName'] ?? 'guest'}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Check Out?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text('Check out $name from the temporary bed now? The bed becomes vacant.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PgColors.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Check Out'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().apiClient.post('/occupancy/temp-stay/end', {
        'partyId': item['partyId'],
      });
      if (mounted) {
        _reload();
        AppToast.successOf(messenger, 'Checked out', title: 'Temporary Stay Ended');
      }
    } catch (e) {
      AppToast.errorOf(messenger, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _pay(Map<String, dynamic> item) async {
    final invoiceId = item['invoiceId'];
    if (invoiceId == null) {
      AppToast.info(context, 'No invoice to collect against yet.', title: 'Nothing Due');
      return;
    }
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => CollectPaymentSheet(
        // CollectPaymentSheet reads snake_case keys (total_amount / paid_amount /
        // invoice_id) for its summary + confirm; include both styles so the
        // amount displays correctly and prefills the remaining balance.
        preselectedInvoice: {
          'invoice_id': invoiceId,
          'invoiceId': invoiceId,
          'total_amount': item['totalAmount'],
          'totalAmount': item['totalAmount'],
          'paid_amount': item['paidAmount'],
          'paidAmount': item['paidAmount'],
          'full_name': item['fullName'],
          // The sheet's summary shows _fmtMonth(invoice_month); temp stays have no
          // billing month, so surface the check-in date instead.
          'invoice_month': item['checkInDate'],
        },
      ),
    );
    if (done == true && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        centerTitle: false,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Temporary Stay',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            if (widget.propertyName != null)
              Text('${widget.propertyName}',
                  style: const TextStyle(
                      fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w400)),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE5E7EB)),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: PgColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Temporary Stay'),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const SkeletonList();
          }
          if (snap.hasError) {
            return ErrorRetryView(error: snap.error!, onRetry: _reload);
          }
          final data = snap.data ?? const {};
          final summary = (data['summary'] as Map?)?.cast<String, dynamic>() ?? const {};
          final items = _applyFilter(_applySearch(
              (data['items'] is List ? data['items'] as List : [])
                  .cast<Map<String, dynamic>>()));
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                _SummaryRow(summary: summary),
                const SizedBox(height: 14),
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search name, mobile, room, bed…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: _searchCtrl.clear,
                          )
                        : null,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final f in _filters)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(f.$2, style: const TextStyle(fontSize: 12)),
                            selected: _status == f.$1,
                            onSelected: (_) => setState(() => _status = f.$1),
                            selectedColor: PgColors.primary.withValues(alpha: 0.15),
                            labelStyle: TextStyle(
                                color: _status == f.$1 ? PgColors.primary : const Color(0xFF4B5563),
                                fontWeight: _status == f.$1 ? FontWeight.w700 : FontWeight.w500),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(
                                  color: _status == f.$1 ? PgColors.primary : Colors.grey.shade300),
                            ),
                            backgroundColor: Colors.white,
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 48),
                    child: Column(
                      children: [
                        Icon(Icons.hotel_outlined, size: 52, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text(
                          _query.isNotEmpty || _status != 'ALL'
                              ? 'No temporary stays match your filter.'
                              : 'No temporary stays yet.\nTap "Add Temporary Stay" to create one.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                else
                  for (var i = 0; i < items.length; i++)
                    FadeSlideIn(
                      delay: Duration(milliseconds: 30 * (i.clamp(0, 8))),
                      child: _TempStayCard(
                        item: items[i],
                        onEdit: () => _openForm(existing: items[i]),
                        onCheckout: () => _checkout(items[i]),
                        onPay: () => _pay(items[i]),
                      ),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Summary row ──────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.summary});
  final Map<String, dynamic> summary;

  int _n(String k) => (summary[k] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      ('Guests', _n('totalGuests'), Icons.groups_outlined, const Color(0xFF4F2DE4)),
      ('Active', _n('active'), Icons.check_circle_outline, const Color(0xFF16A34A)),
      ("Today In", _n('todayCheckins'), Icons.login_outlined, const Color(0xFF2563EB)),
      ("Today Out", _n('todayCheckouts'), Icons.logout_outlined, const Color(0xFFF97316)),
    ];
    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFECECF2)),
              ),
              child: Column(
                children: [
                  Icon(tiles[i].$3, size: 18, color: tiles[i].$4),
                  const SizedBox(height: 6),
                  Text('${tiles[i].$2}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(tiles[i].$1,
                      style: const TextStyle(fontSize: 10.5, color: Colors.grey),
                      textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
          if (i < tiles.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

// ─── Booking card ───────────────────────────────────────────────────────────

class _TempStayCard extends StatelessWidget {
  const _TempStayCard({
    required this.item,
    required this.onEdit,
    required this.onCheckout,
    required this.onPay,
  });

  final Map<String, dynamic> item;
  final VoidCallback onEdit;
  final VoidCallback onCheckout;
  final VoidCallback onPay;

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  static String _fmt(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      return DateFormat('dd MMM').format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = '${item['fullName'] ?? 'Guest'}';
    final status = '${item['bookingStatus'] ?? 'ACTIVE'}';
    final checkedOut = status == 'CHECKED_OUT';
    final bed = [item['floorName'], item['roomName'], item['bedName']]
        .where((e) => e != null && '$e'.isNotEmpty)
        .join(' › ');
    final days = (item['totalDays'] as num?)?.toInt() ?? 1;
    final total = (item['totalAmount'] as num?)?.toDouble() ?? 0;
    final paid = (item['paidAmount'] as num?)?.toDouble() ?? 0;
    final due = (item['dueAmount'] as num?)?.toDouble() ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFECECF2)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: .04), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: PgColors.primary.withValues(alpha: 0.12),
                child: Text(_initials(name),
                    style: const TextStyle(
                        color: PgColors.primary, fontWeight: FontWeight.w800, fontSize: 15)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    if ('${item['mobileNumber'] ?? ''}'.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('${item['mobileNumber']}',
                            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
                      ),
                    if (bed.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(children: [
                          const Icon(Icons.bed_outlined, size: 13, color: PgColors.primary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(bed,
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    color: PgColors.primary,
                                    fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ]),
                      ),
                  ],
                ),
              ),
              // Status + top-right checkout affordance.
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _StatusBadge(status: status),
                  if (!checkedOut)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Tooltip(
                        message: 'Check out',
                        child: InkWell(
                          onTap: onCheckout,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: PgColors.danger.withValues(alpha: 0.10),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.logout_outlined,
                                size: 18, color: PgColors.danger),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F8FC),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    _kv('Check-in', _fmt('${item['checkInDate'] ?? ''}')),
                    _kv('Check-out', _fmt('${item['checkOutDate'] ?? ''}')),
                    _kv('Days', '$days'),
                  ],
                ),
                const Divider(height: 16),
                Row(
                  children: [
                    _kv('Total', inr(total)),
                    _kv('Paid', inr(paid), color: paid > 0 ? PgColors.success : null),
                    _kv('Due', inr(due), color: due > 0 ? PgColors.danger : PgColors.success),
                  ],
                ),
              ],
            ),
          ),
          if (!checkedOut) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                _PaymentBadge(status: '${item['paymentStatus'] ?? 'NONE'}'),
                const SizedBox(width: 8),
                Expanded(
                  child: _RemainingChip(remaining: (item['remainingDays'] as num?)?.toInt()),
                ),
              ],
            ),
          ],
          if (!checkedOut) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (due > 0) ...[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onPay,
                      icon: const Icon(Icons.payments_outlined, size: 16),
                      label: Text('Pay ${inr(due)}',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      style: FilledButton.styleFrom(
                        backgroundColor: PgColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                _ActionBtn(icon: Icons.edit_outlined, label: 'Edit', onTap: onEdit),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _kv(String k, String v, {Color? color}) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k, style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
            const SizedBox(height: 3),
            Text(v,
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13, color: color)),
          ],
        ),
      );
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 15, color: Colors.white),
        label: Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.white)),
        style: FilledButton.styleFrom(
          backgroundColor: PgColors.primary,
          padding: const EdgeInsets.symmetric(vertical: 8),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'ACTIVE' => ('Active', const Color(0xFF16A34A)),
      'UPCOMING' => ('Upcoming', const Color(0xFF2563EB)),
      'CHECKOUT_TODAY' => ('Checkout Today', const Color(0xFFF97316)),
      'OVERDUE' => ('Overdue', const Color(0xFFDC2626)),
      'CHECKED_OUT' => ('Checked Out', const Color(0xFF6B7280)),
      _ => (status, const Color(0xFF6B7280)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _PaymentBadge extends StatelessWidget {
  const _PaymentBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'PAID' => ('Paid', const Color(0xFF16A34A)),
      'PARTIAL' => ('Partial', const Color(0xFFF97316)),
      'PENDING' => ('Pending', const Color(0xFFDC2626)),
      _ => ('No charge', const Color(0xFF6B7280)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _RemainingChip extends StatelessWidget {
  const _RemainingChip({required this.remaining});
  final int? remaining;

  @override
  Widget build(BuildContext context) {
    if (remaining == null) return const SizedBox.shrink();
    final Color color;
    final String label;
    if (remaining! < 0) {
      color = const Color(0xFFDC2626);
      label = 'Overdue by ${remaining!.abs()} day${remaining!.abs() == 1 ? '' : 's'}';
    } else if (remaining == 0) {
      color = const Color(0xFFF97316);
      label = 'Checkout today';
    } else if (remaining! <= 2) {
      color = const Color(0xFFF97316);
      label = '$remaining day${remaining == 1 ? '' : 's'} left';
    } else {
      color = const Color(0xFF16A34A);
      label = '$remaining days left';
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule, size: 13, color: color),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ─── Add / Edit form ──────────────────────────────────────────────────────────

class _TempStayFormScreen extends StatefulWidget {
  const _TempStayFormScreen({required this.propertyId, this.existing});
  final int propertyId;
  final Map<String, dynamic>? existing;

  @override
  State<_TempStayFormScreen> createState() => _TempStayFormScreenState();
}

class _TempStayFormScreenState extends State<_TempStayFormScreen> {
  bool get _isEdit => widget.existing != null;

  // A "bed allocation" entry has no checkout date — its only edit path is the
  // shift-to-permanent flow, so the edit form skips the Extend/Permanent toggle.
  bool get _isAllocationEdit => _isEdit && widget.existing!['checkOutDate'] == null;

  // What the guest already paid during the allocation — carried as an advance credit
  // onto the move-in invoice when converting to a permanent bed.
  double get _allocationPaid =>
      _isEdit ? ((widget.existing!['paidAmount'] as num?)?.toDouble() ?? 0) : 0;

  // Outstanding balance on the allocation invoice. A permanent bed cannot be
  // assigned until this is cleared.
  double get _allocationDue =>
      _isEdit ? ((widget.existing!['dueAmount'] as num?)?.toDouble() ?? 0) : 0;

  // Add sub-mode: 'STAY' (day-wise stay with a planned checkout) vs
  // 'ALLOCATION' (Temporary Bed Allocation — check-in + a one-time payment, no
  // checkout; the guest is shifted to a permanent bed later from Edit).
  String _addMode = 'STAY';

  // Edit sub-mode: 'EXTEND' (Case 1 — extend the day-wise stay) vs
  // 'PERMANENT' (Case 2 — a room of the wanted sharing type has freed up, so
  // shift the guest into it and convert them to a permanent monthly tenant).
  String _editMode = 'EXTEND';

  // Tenant selection — only tenants not currently admitted to a bed.
  List<Map<String, dynamic>>? _tenants;
  int? _selectedPartyId;
  Map<String, dynamic>? _selectedTenant;

  // Bed selection
  List<Map<String, dynamic>>? _beds;
  Map<String, dynamic>? _selectedBed;
  int? _selectedBedId;

  // Dates + pricing
  DateTime _checkIn = DateTime.now();
  DateTime _checkOut = DateTime.now().add(const Duration(days: 1));
  // The already-booked checkout at the time the edit form opened. In EXTEND mode
  // this is the boundary between already-billed days and the new extension days.
  DateTime? _bookedUntil;
  final _perDayCtrl = TextEditingController();

  // Make-permanent pricing (Case 2)
  final _rentCtrl = TextEditingController();
  final _depositCtrl = TextEditingController();
  final _acCtrl = TextEditingController();
  bool _bedHasAc = false;
  DateTime? _permCheckout; // optional expected checkout once permanent

  bool _saving = false;

  int get _days {
    final d = _checkOut.difference(DateTime(_checkIn.year, _checkIn.month, _checkIn.day)).inDays;
    return d < 1 ? 1 : d;
  }

  double get _perDay => double.tryParse(_perDayCtrl.text.trim()) ?? 0;
  double get _total => _perDay * _days;

  // Bed-allocation joining charge = Monthly Rent + Security Deposit + AC (from
  // Price Master for the picked bed, editable). This is what the guest pays at join.
  double get _allocRent => double.tryParse(_rentCtrl.text.trim()) ?? 0;
  double get _allocDeposit => double.tryParse(_depositCtrl.text.trim()) ?? 0;
  double get _allocAc => _bedHasAc ? (double.tryParse(_acCtrl.text.trim()) ?? 0) : 0;
  double get _allocTotal => _allocRent + _allocDeposit + _allocAc;

  // EXTEND mode: only the added days beyond the already-booked checkout are billed
  // as the "extra" amount the owner sees; the invoice total still becomes _total.
  int get _addedDays {
    final b = _bookedUntil;
    if (b == null) return 0;
    final d = _checkOut.difference(DateTime(b.year, b.month, b.day)).inDays;
    return d < 0 ? 0 : d;
  }

  double get _extraAmount => _perDay * _addedDays;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final e = widget.existing!;
      _selectedPartyId = (e['partyId'] as num?)?.toInt();
      _selectedBedId = (e['bedFacilityId'] as num?)?.toInt();
      _checkIn = _parse(e['checkInDate']) ?? DateTime.now();
      _checkOut = _parse(e['checkOutDate']) ?? _checkIn.add(const Duration(days: 1));
      _bookedUntil = _checkOut;
      _perDayCtrl.text = _plain(e['pricePerDay']);
      // A bed allocation (no checkout) can only be shifted to a permanent bed.
      if (_isAllocationEdit) _editMode = 'PERMANENT';
    } else {
      _loadTenants();
    }
    _loadBeds();
  }

  @override
  void dispose() {
    _perDayCtrl.dispose();
    _rentCtrl.dispose();
    _depositCtrl.dispose();
    _acCtrl.dispose();
    super.dispose();
  }

  DateTime? _parse(dynamic iso) {
    if (iso == null) return null;
    try {
      return DateTime.parse('$iso');
    } catch (_) {
      return null;
    }
  }

  String _plain(dynamic v) {
    if (v == null) return '';
    final s = '$v';
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  Future<void> _loadTenants() async {
    try {
      final res = await context.read<AppState>().apiClient
          .get('/properties/${widget.propertyId}/tenants');
      final all = (res['items'] is List ? res['items'] as List : [])
          .cast<Map<String, dynamic>>();
      // Only tenants not currently admitted to a bed are eligible for a temp stay.
      final inactive = all.where((t) => t['hasActiveAdmission'] != true).toList();
      if (mounted) setState(() => _tenants = inactive);
    } catch (_) {
      if (mounted) setState(() => _tenants = []);
    }
  }

  Future<void> _loadBeds() async {
    try {
      final res = await context.read<AppState>().apiClient
          .get('/properties/${widget.propertyId}/vacant-beds');
      final all = (res['items'] is List ? res['items'] as List : [])
          .cast<Map<String, dynamic>>();
      final vacant = all.where((b) => '${b['bed_status']}'.toUpperCase() == 'VACANT').toList();
      if (mounted) setState(() => _beds = vacant);
    } catch (_) {
      if (mounted) setState(() => _beds = []);
    }
  }

  Future<void> _openAddTenant() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddTenantScreen(propertyId: widget.propertyId)),
    );
    if (created == true) _loadTenants();
  }

  Future<void> _pickTenant() async {
    final list = _tenants;
    if (list == null || list.isEmpty) {
      AppToast.info(context, 'No available tenants — add one first.', title: 'No Tenants');
      return;
    }
    final chosen = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _SearchPickerSheet(
        title: 'Select Tenant',
        items: list,
        primary: (t) => '${t['fullName'] ?? 'Tenant'}',
        secondary: (t) => '${t['mobileNumber'] ?? ''}',
      ),
    );
    if (chosen != null) {
      setState(() {
        _selectedTenant = chosen;
        _selectedPartyId = (chosen['tenantId'] as num?)?.toInt();
      });
    }
  }

  Future<void> _pickBed() async {
    final list = _beds;
    if (list == null || list.isEmpty) {
      AppToast.info(context, 'No vacant beds in this property.', title: 'No Beds');
      return;
    }
    final chosen = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _SearchPickerSheet(
        title: 'Select Bed',
        items: list,
        primary: (b) => [b['floor_name'], b['room_name'], b['bed_name']]
            .where((e) => e != null && '$e'.isNotEmpty)
            .join(' › '),
        secondary: (b) => '${b['sharing_type'] ?? '?'}-Sharing',
        filterValue: (b) => '${b['sharing_type'] ?? ''}',
        filterLabel: (v) => '$v-Sharing',
      ),
    );
    if (chosen != null) await _onBedSelected(chosen);
  }

  Future<void> _onBedSelected(Map<String, dynamic> bed) async {
    setState(() {
      _selectedBed = bed;
      _selectedBedId = (bed['bed_id'] as num?)?.toInt();
      _bedHasAc = false;
    });
    // AC charges apply only when the selected bed's room is actually an AC room
    // (facility.is_ac). A non-AC room never carries an AC charge, even if Price
    // Master has an AC rate configured for the sharing type.
    final roomIsAc = _asBool(bed['is_ac']);
    final sharing = bed['sharing_type'];
    if (sharing == null) return;
    try {
      final res = await context.read<AppState>().apiClient
          .get('/properties/${widget.propertyId}/sharing-prices/$sharing');
      final perDay = (res['perDayPrice'] as num?)?.toDouble();
      final rent = (res['monthlyRent'] as num?)?.toDouble();
      final deposit = (res['securityDeposit'] as num?)?.toDouble();
      final ac = (res['acCharges'] as num?)?.toDouble();
      if (!mounted) return;
      setState(() {
        if (perDay != null && perDay > 0) _perDayCtrl.text = perDay.toStringAsFixed(0);
        // Prefill the make-permanent monthly pricing from Price Master for the picked bed.
        if (rent != null && rent > 0) _rentCtrl.text = rent.toStringAsFixed(0);
        if (deposit != null && deposit > 0) _depositCtrl.text = deposit.toStringAsFixed(0);
        if (roomIsAc && ac != null && ac > 0) {
          _bedHasAc = true;
          _acCtrl.text = ac.toStringAsFixed(0);
        } else {
          _bedHasAc = false;
          _acCtrl.clear();
        }
      });
    } catch (_) {
      // No price configured for this sharing type — owner can type it in.
    }
  }

  // TINYINT(1) arrives as a bool, int, or string depending on the driver/JSON.
  bool _asBool(dynamic v) =>
      v == true || v == 1 || '$v' == '1' || '$v'.toLowerCase() == 'true';

  Future<void> _pickDate({required bool isCheckIn}) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = isCheckIn ? _checkIn : _checkOut;
    final first = isCheckIn ? today : _checkIn.add(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first) ? first : initial,
      firstDate: first,
      lastDate: today.add(const Duration(days: 365)),
      helpText: isCheckIn ? 'Select check-in date' : 'Select check-out date',
    );
    if (picked == null) return;
    setState(() {
      if (isCheckIn) {
        _checkIn = picked;
        if (!_checkOut.isAfter(_checkIn)) {
          _checkOut = _checkIn.add(const Duration(days: 1));
        }
      } else {
        _checkOut = picked;
      }
    });
  }

  String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    if (_isEdit && _editMode == 'PERMANENT') {
      await _submitMakePermanent();
      return;
    }
    if (_isEdit) {
      await _submitExtend();
      return;
    }
    // Add: either a day-wise Temporary Stay (with checkout) or a Temporary Bed
    // Allocation (check-in + one-time payment, no checkout).
    if (_selectedBedId == null) {
      AppToast.info(context, 'Select a bed', title: 'Bed Required');
      return;
    }
    final partyId = _selectedPartyId;
    if (partyId == null) {
      AppToast.info(context, 'Select a tenant', title: 'Tenant Required');
      return;
    }
    final allocation = _addMode == 'ALLOCATION';
    final amount = allocation ? _allocTotal : _total;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().apiClient.post('/occupancy/temp-stay', {
        'partyId': partyId,
        'bedFacilityId': _selectedBedId,
        'fromDate': _iso(_checkIn),
        // Bed allocation: no checkout date; the Amount raises the allocation invoice
        // (collected later from the card). A day-wise stay bills its total.
        if (!allocation) 'expectedCheckoutDate': _iso(_checkOut),
        if (amount > 0) 'amount': amount,
      });
      if (mounted) {
        Navigator.pop(context, true);
        AppToast.successOf(messenger, allocation ? 'Bed allocated' : 'Temporary stay created',
            title: 'Saved');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        AppToast.errorOf(messenger, e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  // Case 1 edit — extend the day-wise stay. The invoice is re-totalled to the new
  // full amount; the owner only ever sees the incremental (extra-days) charge.
  Future<void> _submitExtend() async {
    if (_addedDays <= 0) {
      AppToast.info(context, 'Pick a later checkout date to extend the stay.',
          title: 'Nothing to Extend');
      return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().apiClient.put(
          '/occupancy/temp-stay/${widget.existing!['facilityPartyId']}', {
        'expectedCheckoutDate': _iso(_checkOut),
        'amount': _total,
      });
      if (mounted) {
        Navigator.pop(context, true);
        AppToast.successOf(messenger,
            'Extended by $_addedDays day(s) · ${inr(_extraAmount)} added',
            title: 'Stay Extended');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        AppToast.errorOf(messenger, e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  // Case 2 edit — a room of the wanted sharing type freed up: shift the guest into
  // the chosen bed and convert them into a permanent monthly tenant. Billing is
  // anchored to the temp start date by the backend.
  Future<void> _submitMakePermanent() async {
    // Business rule: the allocation invoice must be fully paid before the guest
    // can be moved into a permanent bed.
    if (_allocationDue > 0) {
      AppToast.info(
        context,
        'Collect the pending ${inr(_allocationDue)} on the temporary invoice before assigning a permanent bed.',
        title: 'Payment Pending',
      );
      return;
    }
    if (_selectedBedId == null) {
      AppToast.info(context, 'Select the bed to move into.', title: 'Bed Required');
      return;
    }
    final partyId = _selectedPartyId;
    if (partyId == null) return;
    final baseRent = double.tryParse(_rentCtrl.text.trim()) ?? 0;
    final acAmt = _bedHasAc ? (double.tryParse(_acCtrl.text.trim()) ?? 0) : 0.0;
    // monthlyRent is the all-in total; acCharges tells the backend how much is AC.
    final totalRent = baseRent + acAmt;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().apiClient.post('/occupancy/temp-stay/make-permanent', {
        'partyId': partyId,
        'bedFacilityId': _selectedBedId,
        if (totalRent > 0) 'monthlyRent': totalRent,
        if (acAmt > 0) 'acCharges': acAmt,
        if (_depositCtrl.text.trim().isNotEmpty)
          'securityDeposit': double.tryParse(_depositCtrl.text.trim()),
        if (_permCheckout != null) 'expectedCheckoutDate': _iso(_permCheckout!),
      });
      if (mounted) {
        Navigator.pop(context, true);
        AppToast.successOf(messenger, 'Guest moved in as a permanent tenant',
            title: 'Made Permanent');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        AppToast.errorOf(messenger, e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool permanent = _isEdit && _editMode == 'PERMANENT';
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        title: Text(_isEdit ? 'Edit Temporary Stay' : 'Add Temporary Stay',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE5E7EB)),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ..._buildGuest(),
          if (!_isEdit)
            ..._buildAddBody()
          else if (_isAllocationEdit)
            // Bed allocation → only the shift-to-permanent flow.
            ..._buildPermanentBody()
          else
            // Direct temporary stay → extend only (no make-permanent).
            ..._buildExtendBody(),
          const SizedBox(height: 24),
          AsyncActionButton(
            label: _addBtnLabel(permanent),
            onPressed: () async {
              if (!_saving) await _submit();
            },
          ),
        ],
      ),
    );
  }

  String _addBtnLabel(bool permanent) {
    if (!_isEdit) return _addMode == 'ALLOCATION' ? 'Allocate Temporary Bed' : 'Create Temporary Stay';
    if (_isAllocationEdit) return 'Make Permanent';
    return permanent ? 'Make Permanent' : 'Extend Stay';
  }

  List<Widget> _buildGuest() {
    if (!_isEdit) {
      return [
        _sectionTitle('Guest'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _selectorField(
                label: 'Tenant',
                value: _selectedTenant != null
                    ? '${_selectedTenant!['fullName'] ?? 'Tenant'}'
                    : 'Tap to select',
                placeholder: _selectedTenant == null,
                icon: Icons.person_search_outlined,
                onTap: _tenants == null ? null : _pickTenant,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _openAddTenant,
                icon: const Icon(Icons.person_add_alt_1, size: 16),
                label: const Text('Add'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: PgColors.primary,
                  side: const BorderSide(color: PgColors.primary),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ),
          ],
        ),
        if (_selectedTenant != null &&
            '${_selectedTenant!['mobileNumber'] ?? ''}'.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text('${_selectedTenant!['mobileNumber']}',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
          ),
        const SizedBox(height: 20),
      ];
    }
    return [
      _sectionTitle('Guest'),
      const SizedBox(height: 6),
      Text('${widget.existing!['fullName'] ?? 'Guest'}',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'In temp bed: ${_currentBedLabel()}',
          style: const TextStyle(
              fontSize: 12.5, color: PgColors.primary, fontWeight: FontWeight.w600),
        ),
      ),
      const SizedBox(height: 20),
    ];
  }

  String _currentBedLabel() => [
        widget.existing!['floorName'],
        widget.existing!['roomName'],
        widget.existing!['bedName']
      ].where((e) => e != null && '$e'.isNotEmpty).join(' › ');

  Widget _bedSelector() => _selectorField(
        label: 'Bed',
        value: _selectedBed != null
            ? [
                _selectedBed!['floor_name'],
                _selectedBed!['room_name'],
                _selectedBed!['bed_name']
              ].where((e) => e != null && '$e'.isNotEmpty).join(' › ')
            : 'Tap to select',
        placeholder: _selectedBed == null,
        icon: Icons.bed_outlined,
        onTap: _beds == null ? null : _pickBed,
      );

  // Add form — a toggle between a day-wise Temporary Stay (with checkout) and a
  // Temporary Bed Allocation (check-in + one-time payment, no checkout).
  List<Widget> _buildAddBody() {
    final df = DateFormat('dd MMM yyyy');
    final allocation = _addMode == 'ALLOCATION';
    return [
      Center(
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(
                value: 'STAY',
                label: Text('Temporary Stay'),
                icon: Icon(Icons.event_outlined, size: 16)),
            ButtonSegment(
                value: 'ALLOCATION',
                label: Text('Temporary Bed'),
                icon: Icon(Icons.meeting_room_outlined, size: 16)),
          ],
          selected: {_addMode},
          onSelectionChanged: (s) => setState(() => _addMode = s.first),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        allocation
            ? 'Allocate an available bed now and raise the invoice. No checkout date — '
                'set rent + deposit and shift to a permanent bed later from Edit.'
            : 'Day-wise stay with a planned checkout date.',
        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
      ),
      const SizedBox(height: 20),

      _sectionTitle('Bed'),
      const SizedBox(height: 8),
      _bedSelector(),
      const SizedBox(height: 20),

      _sectionTitle(allocation ? 'Temporary Bed' : 'Stay'),
      const SizedBox(height: 8),
      if (allocation) ...[
        _dateTile(
          label: 'Check-in',
          value: df.format(_checkIn),
          onTap: () => _pickDate(isCheckIn: true),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _rentCtrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Monthly Rent (₹)',
                  prefixIcon: Icon(Icons.currency_rupee),
                  helperText: 'From Price Master — editable',
                  helperStyle: TextStyle(fontSize: 10.5),
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _depositCtrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Deposit (₹)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              ),
            ),
          ],
        ),
        if (_bedHasAc) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _acCtrl,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'AC Charges (₹)',
              prefixIcon: Icon(Icons.ac_unit, size: 18),
              helperText: 'From Price Master — editable',
              helperStyle: TextStyle(fontSize: 10.5),
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          ),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: PgColors.lavender,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(Icons.summarize_outlined, size: 16, color: PgColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Joining charge: Rent + Deposit${_bedHasAc ? ' + AC' : ''} = ${inr(_allocTotal)}',
                  style: const TextStyle(
                      fontSize: 12.5, color: PgColors.primary, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ] else ...[
        Row(
          children: [
            Expanded(
              child: _dateTile(
                label: 'Check-in',
                value: df.format(_checkIn),
                onTap: () => _pickDate(isCheckIn: true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _dateTile(
                label: 'Check-out',
                value: df.format(_checkOut),
                onTap: () => _pickDate(isCheckIn: false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: PgColors.lavender,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 16, color: PgColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _perDay > 0
                      ? '$_days day(s) × ${inr(_perDay)}/day = ${inr(_total)}'
                      : '$_days day(s) — enter a per-day rate to auto-calculate the total',
                  style: const TextStyle(fontSize: 12, color: PgColors.primary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _perDayCtrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Per Day (₹)',
                  prefixIcon: Icon(Icons.currency_rupee),
                  helperText: 'From Price Master — editable',
                  helperStyle: TextStyle(fontSize: 10.5),
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Total (₹)',
                  prefixIcon: Icon(Icons.summarize_outlined),
                  helperText: 'days × per day',
                  helperStyle: TextStyle(fontSize: 10.5),
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Color(0xFFF3F0FF),
                ),
                child: Text(
                  inrPlain(_total),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16, color: PgColors.primary),
                ),
              ),
            ),
          ],
        ),
      ],
    ];
  }

  // Edit → Extend mode: extend the day-wise stay via the colour-coded calendar.
  List<Widget> _buildExtendBody() {
    return [
      _sectionTitle('Extend Stay'),
      const SizedBox(height: 8),
      _ExtensionCalendar(
        checkIn: _checkIn,
        bookedUntil: _bookedUntil ?? _checkOut,
        selected: _checkOut,
        onSelect: (d) => setState(() => _checkOut = d),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: PgColors.lavender,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 16, color: PgColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _addedDays > 0
                    ? 'Extending by $_addedDays day(s) × ${inr(_perDay)} = ${inr(_extraAmount)} extra'
                    : 'Pick a later checkout date to extend the stay.',
                style: const TextStyle(fontSize: 12, color: PgColors.primary),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _perDayCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Per Day (₹)',
                prefixIcon: Icon(Icons.currency_rupee),
                helperText: 'From Price Master — editable',
                helperStyle: TextStyle(fontSize: 10.5),
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Extra (₹)',
                prefixIcon: Icon(Icons.summarize_outlined),
                helperText: 'added days × per day',
                helperStyle: TextStyle(fontSize: 10.5),
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Color(0xFFF3F0FF),
              ),
              child: Text(
                inrPlain(_extraAmount),
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 16, color: PgColors.primary),
              ),
            ),
          ),
        ],
      ),
    ];
  }

  // Edit → Make Permanent (Case 2): assign the guest a bed only. No payment /
  // charge inputs here — the guest already paid when the allocation was created,
  // and monthly rent + deposit are resolved from Price Master for the picked bed.
  List<Widget> _buildPermanentBody() {
    return [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: PgColors.lavender,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Row(children: [
          Icon(Icons.info_outline, size: 16, color: PgColors.primary),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Assign the guest a bed and start regular monthly billing. Rent and '
              'deposit are taken from Price Master; billing is anchored to their '
              'temporary start date.',
              style: TextStyle(fontSize: 12, color: PgColors.primary),
            ),
          ),
        ]),
      ),
      if (_allocationDue > 0) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: PgColors.danger.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: PgColors.danger.withValues(alpha: 0.35)),
          ),
          child: Row(children: [
            const Icon(Icons.lock_outline, size: 16, color: PgColors.danger),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${inr(_allocationDue)} still due on the temporary invoice. Collect the '
                'full amount before assigning a permanent bed.',
                style: const TextStyle(
                    fontSize: 12, color: PgColors.danger, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
      ] else if (_allocationPaid > 0) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: PgColors.success.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: PgColors.success.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.savings_outlined, size: 16, color: PgColors.success),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${inr(_allocationPaid)} already paid during the allocation will be '
                'credited to this invoice — only the balance stays due.',
                style: const TextStyle(fontSize: 12, color: PgColors.success),
              ),
            ),
          ]),
        ),
      ],
      const SizedBox(height: 16),
      _sectionTitle('Assign Bed'),
      const SizedBox(height: 8),
      _selectorField(
        label: 'Bed',
        value: _selectedBed != null
            ? [
                _selectedBed!['floor_name'],
                _selectedBed!['room_name'],
                _selectedBed!['bed_name']
              ].where((e) => e != null && '$e'.isNotEmpty).join(' › ')
            : 'Tap to select a vacant bed',
        placeholder: _selectedBed == null,
        icon: Icons.bed_outlined,
        onTap: _beds == null ? null : _pickBed,
      ),
    ];
  }

  Widget _sectionTitle(String t) =>
      Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15));

  Widget _selectorField({
    required String label,
    required String value,
    required IconData icon,
    required bool placeholder,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 18),
          border: const OutlineInputBorder(),
          suffixIcon: onTap == null ? null : const Icon(Icons.expand_more),
        ),
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: placeholder ? Colors.grey[500] : null,
              fontWeight: placeholder ? FontWeight.w400 : FontWeight.w600),
        ),
      ),
    );
  }

  Widget _dateTile({required String label, required String value, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
          border: const OutlineInputBorder(),
          enabled: onTap != null,
        ),
        child: Text(value, style: TextStyle(color: onTap == null ? Colors.grey[600] : null)),
      ),
    );
  }
}

// ─── Extension calendar (Case 1 edit) ────────────────────────────────────────

/// Month calendar for extending a temporary stay. Already-booked days
/// (check-in → current checkout) render in the "booked" colour; the newly added
/// extension days (up to the tapped checkout) render in the "extension" colour.
/// Only days after the current checkout are tappable.
class _ExtensionCalendar extends StatefulWidget {
  const _ExtensionCalendar({
    required this.checkIn,
    required this.bookedUntil,
    required this.selected,
    required this.onSelect,
  });

  final DateTime checkIn;
  final DateTime bookedUntil;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  @override
  State<_ExtensionCalendar> createState() => _ExtensionCalendarState();
}

class _ExtensionCalendarState extends State<_ExtensionCalendar> {
  late DateTime _month;
  static const _extension = Color(0xFF16A34A);

  @override
  void initState() {
    super.initState();
    final s = widget.selected;
    _month = DateTime(s.year, s.month);
  }

  static DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);

  void _shift(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta));

  @override
  Widget build(BuildContext context) {
    final checkIn = _d(widget.checkIn);
    final booked = _d(widget.bookedUntil);
    final selected = _d(widget.selected);
    final first = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final lead = first.weekday % 7; // Sunday = 0

    final cells = <Widget>[];
    for (var i = 0; i < lead; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_month.year, _month.month, day);
      final isBooked = !date.isBefore(checkIn) && !date.isAfter(booked);
      final isExtension = date.isAfter(booked) && !date.isAfter(selected);
      final selectable = date.isAfter(booked);
      final isEnd = date == selected && selected.isAfter(booked);

      Color? bg;
      Color fg = const Color(0xFF1A1A2E);
      if (isEnd) {
        bg = _extension;
        fg = Colors.white;
      } else if (isExtension) {
        bg = _extension.withValues(alpha: 0.18);
        fg = _extension;
      } else if (isBooked) {
        bg = PgColors.lavender;
        fg = PgColors.primary;
      } else if (!selectable) {
        fg = Colors.grey.shade400;
      }

      cells.add(_cell(day, bg, fg, selectable ? () => widget.onSelect(date) : null));
    }

    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 7) {
      rows.add(Row(
        children: [
          for (var j = 0; j < 7; j++)
            Expanded(child: i + j < cells.length ? cells[i + j] : const SizedBox.shrink()),
        ],
      ));
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFECECF2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
              Expanded(
                child: Text(DateFormat('MMMM yyyy').format(_month),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
            ],
          ),
          Row(
            children: [
              for (final w in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
                Expanded(
                  child: Center(
                    child: Text(w,
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          ...rows,
          const SizedBox(height: 10),
          Row(
            children: [
              _legend(PgColors.lavender, PgColors.primary, 'Booked'),
              const SizedBox(width: 16),
              _legend(_extension.withValues(alpha: 0.18), _extension, 'Extension'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cell(int day, Color? bg, Color fg, VoidCallback? onTap) {
    return Padding(
      padding: const EdgeInsets.all(2),
      child: AspectRatio(
        aspectRatio: 1,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
            child: Text('$day',
                style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }

  Widget _legend(Color bg, Color fg, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 11.5, color: fg, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ─── Searchable picker sheet (tenants / beds) ─────────────────────────────────

class _SearchPickerSheet extends StatefulWidget {
  const _SearchPickerSheet({
    required this.title,
    required this.items,
    required this.primary,
    required this.secondary,
    this.filterValue,
    this.filterLabel,
  });

  final String title;
  final List<Map<String, dynamic>> items;
  final String Function(Map<String, dynamic>) primary;
  final String Function(Map<String, dynamic>) secondary;

  /// Optional filter dimension (e.g. sharing type for beds). When provided, a
  /// chip row of the distinct values (plus "All") is shown and the list is
  /// filtered by the selected value in addition to the search query.
  final String Function(Map<String, dynamic>)? filterValue;

  /// How to render a raw filter value as a chip label. Defaults to the value.
  final String Function(String)? filterLabel;

  @override
  State<_SearchPickerSheet> createState() => _SearchPickerSheetState();
}

class _SearchPickerSheetState extends State<_SearchPickerSheet> {
  final _ctrl = TextEditingController();
  String _q = '';
  String? _filter; // selected filter value (null = All)

  // Distinct, non-empty filter values in first-seen order.
  List<String> get _filterValues {
    final fn = widget.filterValue;
    if (fn == null) return const [];
    final seen = <String>[];
    for (final it in widget.items) {
      final v = fn(it).trim();
      if (v.isNotEmpty && !seen.contains(v)) seen.add(v);
    }
    seen.sort();
    return seen;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.viewInsetsOf(context).bottom;
    final fn = widget.filterValue;
    final filtered = widget.items.where((it) {
      if (_q.isNotEmpty) {
        final hay = '${widget.primary(it)} ${widget.secondary(it)}'.toLowerCase();
        if (!hay.contains(_q)) return false;
      }
      if (_filter != null && fn != null && fn(it).trim() != _filter) return false;
      return true;
    }).toList();
    final filterValues = _filterValues;
    return Padding(
      padding: EdgeInsets.only(bottom: pad),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                  color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.title,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                  IconButton(
                      icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _q.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _ctrl.clear();
                            setState(() => _q = '');
                          },
                        )
                      : null,
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
            if (filterValues.length > 1)
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  children: [
                    for (final v in <String?>[null, ...filterValues])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                            v == null
                                ? 'All'
                                : (widget.filterLabel?.call(v) ?? v),
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: _filter == v,
                          onSelected: (_) => setState(() => _filter = v),
                          selectedColor: PgColors.primary.withValues(alpha: 0.15),
                          labelStyle: TextStyle(
                              color: _filter == v ? PgColors.primary : const Color(0xFF4B5563),
                              fontWeight: _filter == v ? FontWeight.w700 : FontWeight.w500),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                                color: _filter == v ? PgColors.primary : Colors.grey.shade300),
                          ),
                          backgroundColor: Colors.white,
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                  ],
                ),
              ),
            if (filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No matches', style: TextStyle(color: Colors.grey)),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final it = filtered[i];
                    final sub = widget.secondary(it);
                    return ListTile(
                      title: Text(widget.primary(it)),
                      subtitle: sub.isEmpty ? null : Text(sub),
                      onTap: () => Navigator.pop(context, it),
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
