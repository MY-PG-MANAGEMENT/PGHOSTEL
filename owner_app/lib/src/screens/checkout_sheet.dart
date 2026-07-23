import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme/app_theme.dart';
import '../utils/money.dart';
import '../widgets/animations.dart';
import '../widgets/app_toast.dart';

// ─── Checkout Sheet ───────────────────────────────────────────────────────────

class CheckoutSheet extends StatefulWidget {
  const CheckoutSheet({
    required this.partyId,
    required this.tenantName,
    required this.onCheckedOut,
    super.key,
  });

  final int partyId;
  final String tenantName;
  final VoidCallback onCheckedOut;

  @override
  State<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<CheckoutSheet> {
  List<Map<String, dynamic>>? _invoices;
  String? _loadError;
  final Set<int> _payOpen = {};
  final Map<int, TextEditingController> _amountCtrl = {};
  final Map<int, String> _payMode = {};
  DateTime _checkoutDate = DateTime.now();
  bool _checkingOut = false;

  // Security-deposit refund (optional, owner-provided at checkout).
  double? _depositHeld;
  final _refundCtrl = TextEditingController();
  String _refundMode = 'CASH';

  @override
  void initState() {
    super.initState();
    _load();
    _loadDeposit();
  }

  @override
  void dispose() {
    for (final c in _amountCtrl.values) {
      c.dispose();
    }
    _refundCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDeposit() async {
    try {
      final tenant = await context
          .read<AppState>()
          .apiClient
          .get('/tenants/${widget.partyId}');
      final deposit = (tenant['securityDeposit'] as num?)?.toDouble();
      if (mounted) {
        setState(() {
          _depositHeld = deposit;
          if (deposit != null && deposit > 0 && _refundCtrl.text.isEmpty) {
            _refundCtrl.text = deposit.toStringAsFixed(0);
          }
        });
      }
    } catch (_) {
      // Deposit info is optional — checkout still works without it.
    }
  }

  Future<void> _pickCheckoutDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _checkoutDate,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
      helpText: 'Select checkout date',
    );
    if (picked != null) setState(() => _checkoutDate = picked);
  }

  Future<void> _load() async {
    setState(() {
      _invoices = null;
      _loadError = null;
    });
    try {
      final result = await context.read<AppState>().apiClient
          .get('/billing/invoices?partyId=${widget.partyId}&size=50');
      final all = (result['items'] is List ? result['items'] as List : [])
          .cast<Map<String, dynamic>>();
      final pending = all.where((inv) {
        final s = '${inv['status']}'.toUpperCase();
        return s == 'PENDING' || s == 'PARTIAL' || s == 'OVERDUE';
      }).toList();
      if (mounted) setState(() => _invoices = pending);
    } catch (e) {
      if (mounted) {
        setState(() => _loadError = e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  TextEditingController _getOrCreateCtrl(Map<String, dynamic> inv) {
    final id = (inv['invoice_id'] as num).toInt();
    return _amountCtrl.putIfAbsent(id, () {
      final raw = inv['balance']?.toString() ?? '0';
      final clean = raw.endsWith('.0') ? raw.split('.')[0] : raw;
      return TextEditingController(text: clean);
    });
  }

  void _togglePay(int id) {
    setState(() {
      if (_payOpen.contains(id)) {
        _payOpen.remove(id);
      } else {
        _payOpen.add(id);
      }
    });
  }

  String _fmtMonth(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final d = DateTime.parse(iso);
      const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${m[d.month - 1]} ${d.year}';
    } catch (_) {
      return iso;
    }
  }

  Future<void> _writeOff(Map<String, dynamic> invoice) async {
    final id = (invoice['invoice_id'] as num).toInt();
    final month = _fmtMonth(invoice['invoice_month'] as String?);
    final balance = invoice['balance'] ?? invoice['total_amount'] ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Write Off?',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text('Mark ${inr(balance)} due for $month as written off?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Write Off'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<AppState>().apiClient
          .post('/billing/invoices/$id/write-off', {});
      if (mounted) {
        setState(() {
          _invoices!.removeWhere((i) => (i['invoice_id'] as num).toInt() == id);
          _payOpen.remove(id);
          _amountCtrl.remove(id)?.dispose();
          _payMode.remove(id);
        });
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  Future<void> _pay(Map<String, dynamic> invoice) async {
    final id = (invoice['invoice_id'] as num).toInt();
    final ctrl = _amountCtrl[id];
    if (ctrl == null) return;
    final amount = double.tryParse(ctrl.text.trim());
    if (amount == null || amount <= 0) {
      AppToast.info(context, 'Enter a valid amount', title: 'Invalid Amount');
      return;
    }
    final mode = _payMode[id] ?? 'CASH';
    final key =
        '${widget.partyId}-$id-${DateTime.now().millisecondsSinceEpoch}';
    try {
      await context.read<AppState>().apiClient.post('/billing/payments', {
        'invoiceId': id,
        'amount': amount,
        'paymentMode': mode,
        'idempotencyKey': key,
      });
      await _load();
      if (mounted) {
        AppToast.success(context, 'Payment recorded',
            title: 'Payment Collected');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  Future<void> _checkout() async {
    final refund = double.tryParse(_refundCtrl.text.trim());
    if (refund != null && refund > 0 && _depositHeld != null && refund > _depositHeld!) {
      AppToast.info(
          context,
          'Refund exceeds the deposit held (${inr(_depositHeld)})',
          title: 'Check Refund');
      return;
    }
    setState(() => _checkingOut = true);
    final d = _checkoutDate;
    final iso =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    try {
      await context.read<AppState>().apiClient.post('/occupancy/checkout', {
        'partyId': widget.partyId,
        'checkoutDate': iso,
        if (refund != null && refund > 0) ...{
          'refundAmount': refund,
          'refundMethod': _refundMode,
        },
      });
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context, true);
        widget.onCheckedOut();
        AppToast.successOf(
            messenger, 'Checkout completed for ${widget.tenantName}',
            title: 'Checked Out');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _checkingOut = false);
        AppToast.error(context, e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final invoices = _invoices;
    final allSettled = invoices != null && invoices.isEmpty;
    final padding = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: padding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Checkout: ${widget.tenantName}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                ),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          const Divider(height: 1),
          ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.72),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: FadeSlideIn(
                offset: 8,
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (invoices == null && _loadError == null)
                    const Center(
                        child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator())),
                  if (_loadError != null)
                    Text('Failed to load: $_loadError',
                        style: const TextStyle(color: Colors.red)),
                  if (invoices != null && invoices.isNotEmpty) ...[
                    const Text('Settle dues before checkout',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 12),
                    for (final inv in invoices)
                      _InvoicePendingCard(
                        invoice: inv,
                        payOpen: _payOpen
                            .contains((inv['invoice_id'] as num).toInt()),
                        amountCtrl: _getOrCreateCtrl(inv),
                        payMode:
                            _payMode[(inv['invoice_id'] as num).toInt()] ??
                                'CASH',
                        onTogglePay: () =>
                            _togglePay((inv['invoice_id'] as num).toInt()),
                        onPayModeChange: (m) => setState(() =>
                            _payMode[(inv['invoice_id'] as num).toInt()] = m),
                        onPay: () => _pay(inv),
                        onWriteOff: () => _writeOff(inv),
                      ),
                  ],
                  if (allSettled) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: PgColors.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check_circle_outline,
                              color: PgColors.success, size: 18),
                          SizedBox(width: 8),
                          Text('No pending dues',
                              style: TextStyle(
                                  color: PgColors.success,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.savings_outlined,
                                  color: PgColors.primary, size: 18),
                              SizedBox(width: 8),
                              Text('Deposit Refund (optional)',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _depositHeld != null && _depositHeld! > 0
                                ? 'Security deposit held: ${inr(_depositHeld)}. '
                                    'Leave the amount empty to skip the refund.'
                                : 'No security deposit on record. Enter an amount only if you are refunding one.',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _refundCtrl,
                            enabled: !_checkingOut,
                            decoration: const InputDecoration(
                              labelText: 'Refund Amount (₹)',
                              prefixIcon: Icon(Icons.currency_rupee_outlined),
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.]'))
                            ],
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: _refundMode,
                            decoration: const InputDecoration(
                              labelText: 'Refund Mode',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            items: const ['CASH', 'UPI', 'CARD', 'BANK_TRANSFER']
                                .map((m) =>
                                    DropdownMenuItem(value: m, child: Text(m)))
                                .toList(),
                            onChanged: _checkingOut
                                ? null
                                : (v) {
                                    if (v != null) {
                                      setState(() => _refundMode = v);
                                    }
                                  },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: _checkingOut ? null : _pickCheckoutDate,
                      borderRadius: BorderRadius.circular(8),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Checkout Date',
                          prefixIcon: Icon(Icons.event_outlined),
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          '${_checkoutDate.day.toString().padLeft(2, '0')}-'
                          '${_checkoutDate.month.toString().padLeft(2, '0')}-'
                          '${_checkoutDate.year}',
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      icon: const Icon(Icons.logout_outlined),
                      label: Text(_checkingOut
                          ? 'Processing…'
                          : 'Confirm Checkout'),
                      style: FilledButton.styleFrom(
                        backgroundColor: PgColors.danger,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: _checkingOut ? null : _checkout,
                    ),
                  ],
                ],
              ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoicePendingCard extends StatelessWidget {
  const _InvoicePendingCard({
    required this.invoice,
    required this.payOpen,
    required this.amountCtrl,
    required this.payMode,
    required this.onTogglePay,
    required this.onPayModeChange,
    required this.onPay,
    required this.onWriteOff,
    this.showWriteOff = true,
  });

  final Map<String, dynamic> invoice;
  final bool payOpen;
  final TextEditingController amountCtrl;
  final String payMode;
  final VoidCallback onTogglePay;
  final ValueChanged<String> onPayModeChange;
  final VoidCallback onPay;
  final VoidCallback onWriteOff;
  final bool showWriteOff;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _fmtMonth(String? iso) {
    if (iso == null) return '—';
    try {
      final d = DateTime.parse(iso);
      return '${_months[d.month - 1]} ${d.year}';
    } catch (_) {
      return iso;
    }
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    try {
      final d = DateTime.parse(iso);
      return '${d.day} ${_months[d.month - 1]} ${d.year}';
    } catch (_) {
      return iso;
    }
  }

  Widget _stat(String label, String value, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 14, color: color)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = '${invoice['status']}'.toUpperCase();
    final statusColor =
        status == 'OVERDUE' ? PgColors.danger : Colors.orange;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _fmtMonth(invoice['invoice_month'] as String?),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    border: Border.all(color: statusColor),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(status,
                      style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _stat('Total', inr(invoice['total_amount'])),
                const SizedBox(width: 16),
                _stat('Paid', inr(invoice['paid_amount']),
                    color: PgColors.success),
                const SizedBox(width: 16),
                _stat('Balance', inr(invoice['balance']),
                    color: PgColors.danger),
              ],
            ),
            if ((invoice['due_date'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text('Due: ${_fmtDate(invoice['due_date'] as String?)}',
                  style:
                      const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
            const SizedBox(height: 12),
            if (!payOpen)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon:
                          const Icon(Icons.payments_outlined, size: 16),
                      label: const Text('Pay'),
                      style: FilledButton.styleFrom(
                        backgroundColor: PgColors.primary,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: onTogglePay,
                    ),
                  ),
                  if (showWriteOff) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.remove_circle_outline,
                            size: 16),
                        label: const Text('Write Off'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange,
                          side: const BorderSide(color: Colors.orange),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: onWriteOff,
                      ),
                    ),
                  ],
                ],
              ),
            if (payOpen) ...[
              TextFormField(
                controller: amountCtrl,
                decoration: const InputDecoration(
                  labelText: 'Amount (₹)',
                  prefixIcon: Icon(Icons.currency_rupee_outlined),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: payMode,
                decoration: const InputDecoration(
                  labelText: 'Payment Mode',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: ['CASH', 'UPI', 'ONLINE', 'NEFT', 'CHEQUE']
                    .map((m) =>
                        DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) onPayModeChange(v);
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: PgColors.primary,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: onPay,
                      child: const Text('Confirm Pay'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: onTogglePay,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Transfer Bed Sheet ───────────────────────────────────────────────────────

class TransferBedScreen extends StatefulWidget {
  const TransferBedScreen({
    required this.partyId,
    required this.tenantName,
    required this.currentPropertyId,
    required this.onTransferred,
    this.moveInDateIso,
    this.currentSharingType,
    super.key,
  });

  final int partyId;
  final String tenantName;
  final int? currentPropertyId;
  final VoidCallback onTransferred;

  /// Tenant's move-in date (ISO yyyy-MM-dd) — used to compute the next billing
  /// date for a sharing-type change.
  final String? moveInDateIso;

  /// Tenant's current room sharing type (e.g. "4"). Used to decide whether a
  /// chosen bed is the same sharing (immediate) or different (scheduled).
  final String? currentSharingType;

  @override
  State<TransferBedScreen> createState() => _TransferBedScreenState();
}

class _TransferBedScreenState extends State<TransferBedScreen> {
  // ── invoice settlement (same as checkout) ──
  List<Map<String, dynamic>>? _invoices;
  String? _loadError;
  final Set<int> _payOpen = {};
  final Map<int, TextEditingController> _amountCtrl = {};
  final Map<int, String> _payMode = {};

  // ── mode ──
  // 'PERMANENT' = a real bed transfer (same-sharing = immediate, different-sharing
  // = scheduled to next billing date). 'TEMPORARY' = a no-billing temporary stay.
  String _mode = 'PERMANENT';

  // ── bed selection ──
  List<Map<String, dynamic>>? _vacantBeds;
  String? _bedsError;
  Map<String, dynamic>? _selectedBed;
  DateTime _transferDate = DateTime.now();
  bool _transferring = false;
  final _rentCtrl = TextEditingController();
  final _tempAmountCtrl = TextEditingController(); // one-time temporary-stay charge
  double? _standardRent;
  // Bed-list filter (by bed / room / floor name + sharing type).
  final _bedSearchCtrl = TextEditingController();
  String _bedQuery = '';
  String? _bedSharing; // selected sharing-type filter (null = all)

  /// True when the selected bed's sharing type differs from the tenant's current
  /// one — such a move is deferred to the next billing date.
  bool get _isSharingChange {
    final sel = _selectedBed?['sharing_type'];
    final cur = widget.currentSharingType;
    return sel != null && cur != null && '$sel' != cur;
  }

  /// The next billing-cycle date (anniversary of move-in, strictly after today).
  /// Mirrors the backend so the UI can preview when a sharing change takes effect.
  DateTime? get _nextCycleDate {
    final iso = widget.moveInDateIso;
    if (iso == null) return null;
    DateTime moveIn;
    try {
      moveIn = DateTime.parse(iso);
    } catch (_) {
      return null;
    }
    final now = DateTime.now();
    int day = moveIn.day;
    int dim(int y, int m) => DateTime(y, m + 1, 0).day;
    DateTime candidate = DateTime(now.year, now.month, day.clamp(1, dim(now.year, now.month)));
    if (!candidate.isAfter(now)) {
      final ny = now.month == 12 ? now.year + 1 : now.year;
      final nm = now.month == 12 ? 1 : now.month + 1;
      candidate = DateTime(ny, nm, day.clamp(1, dim(ny, nm)));
    }
    return candidate;
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

  @override
  void initState() {
    super.initState();
    _loadInvoices();
    _loadVacantBeds();
  }

  @override
  void dispose() {
    for (final c in _amountCtrl.values) c.dispose();
    _rentCtrl.dispose();
    _tempAmountCtrl.dispose();
    _bedSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInvoices() async {
    setState(() { _invoices = null; _loadError = null; });
    try {
      final result = await context.read<AppState>().apiClient
          .get('/billing/invoices?partyId=${widget.partyId}&size=50');
      final all = (result['items'] is List ? result['items'] as List : [])
          .cast<Map<String, dynamic>>();
      final pending = all.where((inv) {
        final s = '${inv['status']}'.toUpperCase();
        return s == 'PENDING' || s == 'PARTIAL' || s == 'OVERDUE';
      }).toList();
      if (mounted) setState(() => _invoices = pending);
    } catch (e) {
      if (mounted) setState(() => _loadError = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _loadVacantBeds() async {
    final pid = widget.currentPropertyId;
    if (pid == null) return;
    setState(() { _vacantBeds = null; _bedsError = null; });
    try {
      final result = await context.read<AppState>().apiClient
          .get('/properties/$pid/vacant-beds');
      final all = (result is List ? result : (result['items'] ?? result['data'] ?? []))
          .cast<Map<String, dynamic>>();
      // Only show truly vacant beds — exclude UPCOMING (still occupied)
      final vacant = all.where((b) => '${b['bed_status']}'.toUpperCase() == 'VACANT').toList();
      if (mounted) setState(() => _vacantBeds = vacant);
    } catch (e) {
      if (mounted) setState(() => _bedsError = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _onBedSelected(Map<String, dynamic> bed) async {
    setState(() {
      _selectedBed = bed;
      _standardRent = null;
      _rentCtrl.clear();
    });
    final pid = widget.currentPropertyId;
    final sharingType = bed['sharing_type'] as String?;
    if (pid == null || sharingType == null) return;
    try {
      final result = await context.read<AppState>().apiClient
          .get('/properties/$pid/sharing-prices/$sharingType');
      final rent = (result['monthlyRent'] as num?)?.toDouble();
      if (!mounted) return;
      setState(() {
        _standardRent = rent;
        if (rent != null) _rentCtrl.text = rent.toStringAsFixed(0);
      });
    } catch (_) {}
  }

  TextEditingController _getOrCreateCtrl(Map<String, dynamic> inv) {
    final id = (inv['invoice_id'] as num).toInt();
    return _amountCtrl.putIfAbsent(id, () {
      final raw = inv['balance']?.toString() ?? '0';
      final clean = raw.endsWith('.0') ? raw.split('.')[0] : raw;
      return TextEditingController(text: clean);
    });
  }

  void _togglePay(int id) => setState(() {
    if (_payOpen.contains(id)) { _payOpen.remove(id); } else { _payOpen.add(id); }
  });

  String _fmtMonth(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final d = DateTime.parse(iso);
      const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${m[d.month - 1]} ${d.year}';
    } catch (_) { return iso; }
  }

  Future<void> _writeOff(Map<String, dynamic> invoice) async {
    final id = (invoice['invoice_id'] as num).toInt();
    final month = _fmtMonth(invoice['invoice_month'] as String?);
    final balance = invoice['balance'] ?? invoice['total_amount'] ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Write Off?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text('Mark ${inr(balance)} due for $month as written off?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Write Off'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<AppState>().apiClient.post('/billing/invoices/$id/write-off', {});
      if (mounted) setState(() {
        _invoices!.removeWhere((i) => (i['invoice_id'] as num).toInt() == id);
        _payOpen.remove(id);
        _amountCtrl.remove(id)?.dispose();
        _payMode.remove(id);
      });
    } catch (e) {
      if (mounted) {
        AppToast.error(context, e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  Future<void> _pay(Map<String, dynamic> invoice) async {
    final id = (invoice['invoice_id'] as num).toInt();
    final ctrl = _amountCtrl[id];
    if (ctrl == null) return;
    final amount = double.tryParse(ctrl.text.trim());
    if (amount == null || amount <= 0) {
      AppToast.info(context, 'Enter a valid amount', title: 'Invalid Amount');
      return;
    }
    final mode = _payMode[id] ?? 'CASH';
    final key = '${widget.partyId}-$id-${DateTime.now().millisecondsSinceEpoch}';
    try {
      await context.read<AppState>().apiClient.post('/billing/payments', {
        'invoiceId': id, 'amount': amount, 'paymentMode': mode, 'idempotencyKey': key,
      });
      await _loadInvoices();
      if (mounted) {
        AppToast.success(context, 'Payment recorded',
            title: 'Payment Collected');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  Future<void> _pickTransferDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: today,
      lastDate: today,
      helpText: 'Transfer date (today only)',
    );
    if (picked != null) setState(() => _transferDate = picked);
  }

  String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _transfer() async {
    if (_selectedBed == null) return;
    setState(() => _transferring = true);
    final bedId = (_selectedBed!['bed_id'] as num).toInt();
    final messenger = ScaffoldMessenger.of(context);
    try {
      String message;
      String title;
      if (_mode == 'TEMPORARY') {
        final amt = double.tryParse(_tempAmountCtrl.text.trim()) ?? 0;
        await context.read<AppState>().apiClient.post('/occupancy/temp-stay', {
          'partyId': widget.partyId,
          'bedFacilityId': bedId,
          'fromDate': _iso(_transferDate),
          if (amt > 0) 'amount': amt,
        });
        message = 'Temporary stay started';
        title = 'Temporary Stay Started';
      } else {
        final rent = double.tryParse(_rentCtrl.text.trim());
        final body = <String, dynamic>{
          'partyId': widget.partyId,
          'newBedFacilityId': bedId,
        };
        // Same-sharing → immediate on the chosen date, rent unchanged (no override sent).
        // Different-sharing → send the new rent; omit the date so the backend schedules
        // it at the next billing cycle.
        if (_isSharingChange) {
          if (rent != null && rent > 0) body['monthlyRent'] = rent;
        } else {
          body['transferDate'] = _iso(_transferDate);
        }
        final res = await context.read<AppState>().apiClient.post('/occupancy/transfer-bed', body);
        if ('${res['mode']}' == 'SCHEDULED') {
          final eff = res['scheduled']?['effectiveDate'];
          message = 'Transfer scheduled for ${eff ?? 'the next billing date'}';
          title = 'Transfer Scheduled';
        } else {
          message = 'Bed transferred';
          title = 'Bed Transferred';
        }
      }
      if (mounted) {
        Navigator.pop(context, true);
        widget.onTransferred();
        AppToast.successOf(messenger, message, title: title);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _transferring = false);
        AppToast.errorOf(
            messenger, e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  Widget _sharingChip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: PgColors.primary.withValues(alpha: 0.15),
        labelStyle: TextStyle(
            color: selected ? PgColors.primary : const Color(0xFF4B5563),
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
              color: selected ? PgColors.primary : Colors.grey.shade300),
        ),
        backgroundColor: Colors.white,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _bedSelector() {
    if (widget.currentPropertyId == null) {
      return const Text('Property info unavailable — refresh the tenant detail and try again.',
          style: TextStyle(color: Colors.grey));
    }
    if (_vacantBeds == null && _bedsError == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_bedsError != null) {
      return Text('Failed to load beds: $_bedsError', style: const TextStyle(color: Colors.red));
    }
    if (_vacantBeds!.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Text('No vacant beds in this property.',
            style: TextStyle(color: Colors.grey), textAlign: TextAlign.center),
      );
    }

    final q = _bedQuery;
    // Distinct sharing types available among vacant beds (sorted numerically).
    final sharingTypes = _vacantBeds!
        .map((b) => '${b['sharing_type'] ?? ''}')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) =>
          (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));

    final beds = _vacantBeds!.where((b) {
      if (_bedSharing != null && '${b['sharing_type'] ?? ''}' != _bedSharing) {
        return false;
      }
      if (q.isEmpty) return true;
      final hay = [
        b['bed_name'],
        b['room_name'],
        b['floor_name'],
        b['sharing_type'],
      ].map((e) => '${e ?? ''}'.toLowerCase()).join(' ');
      return hay.contains(q);
    }).toList();

    final showFilters = _vacantBeds!.length > 4;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Filter — only worth showing when there are enough beds to warrant it.
        if (showFilters) ...[
          TextField(
            controller: _bedSearchCtrl,
            onChanged: (v) => setState(() => _bedQuery = v.toLowerCase().trim()),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Filter by bed, room, floor…',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _bedQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _bedSearchCtrl.clear();
                        setState(() => _bedQuery = '');
                      },
                    )
                  : null,
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          if (sharingTypes.length > 1) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _sharingChip('All', _bedSharing == null,
                      () => setState(() => _bedSharing = null)),
                  for (final s in sharingTypes)
                    _sharingChip('$s-Sharing', _bedSharing == s,
                        () => setState(() => _bedSharing = s)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
        ],
        if (beds.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: const Text('No beds match your filter.',
                style: TextStyle(color: Colors.grey), textAlign: TextAlign.center),
          )
        else
          // Bounded so a long list scrolls internally instead of pushing the
          // rent/amount fields and the confirm button off-screen.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: SingleChildScrollView(
              child: _BedPicker(
                  beds: beds, selected: _selectedBed, onSelect: _onBedSelected),
            ),
          ),
      ],
    );
  }

  Widget _sharingChangeCard() {
    final eff = _nextCycleDate;
    final newSharing = _selectedBed?['sharing_type'];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PgColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: PgColors.warning.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.event_repeat_outlined, color: PgColors.warning, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(
            'Sharing change (${widget.currentSharingType}-sharing → $newSharing-sharing)',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          )),
        ]),
        const SizedBox(height: 6),
        Text(
          eff != null
              ? 'Takes effect on ${_fmtDate(eff)} (the next billing date). '
                  'The new rent applies from then — the current month stays unchanged.'
              : 'Takes effect on the next billing date. The current month stays unchanged.',
          style: const TextStyle(fontSize: 12.5, color: Color(0xFF7A5B00)),
        ),
      ]),
    );
  }

  Widget _datePickerTile(String label) {
    return InkWell(
      onTap: _transferring ? null : _pickTransferDate,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.event_outlined),
          border: const OutlineInputBorder(),
        ),
        child: Text(_fmtDate(_transferDate)),
      ),
    );
  }

  List<Widget> _bedAndConfirm() {
    final isTemp = _mode == 'TEMPORARY';
    final sharingChange = !isTemp && _isSharingChange;
    final confirmLabel = isTemp
        ? 'Start Temporary Stay'
        : (sharingChange ? 'Schedule Transfer' : 'Confirm Transfer');
    return [
      Text(isTemp ? 'Select Bed' : 'Select New Bed',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      const SizedBox(height: 10),
      _bedSelector(),
      const SizedBox(height: 16),
      if (_selectedBed != null) ...[
        // Temporary → one-time charge. Sharing change → new rent (editable).
        // Same-sharing transfer → rent is unchanged, so no amount field is shown.
        if (isTemp) ...[
          TextField(
            controller: _tempAmountCtrl,
            decoration: const InputDecoration(
              labelText: 'Amount (₹)',
              prefixIcon: Icon(Icons.currency_rupee),
              helperText: 'One-time charge for this temporary stay',
              helperStyle: TextStyle(fontSize: 11),
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          ),
          const SizedBox(height: 16),
        ] else if (sharingChange) ...[
          TextField(
            controller: _rentCtrl,
            decoration: InputDecoration(
              labelText: 'New Monthly Rent (₹)',
              prefixIcon: const Icon(Icons.currency_rupee),
              helperText: _standardRent != null
                  ? 'Standard: ${inr(_standardRent)}/mo'
                  : null,
              helperStyle: const TextStyle(color: Color(0xFF2563EB), fontSize: 11),
              border: const OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          ),
          const SizedBox(height: 16),
        ],
        if (sharingChange)
          _sharingChangeCard()
        else
          _datePickerTile(isTemp ? 'Start Date' : 'Transfer Date'),
        const SizedBox(height: 16),
      ],
      FilledButton.icon(
        icon: _transferring
            ? const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Icon(isTemp ? Icons.timelapse_outlined : Icons.swap_horiz_rounded),
        label: Text(_transferring ? 'Working…' : confirmLabel),
        style: FilledButton.styleFrom(
          backgroundColor: PgColors.primary,
          minimumSize: const Size.fromHeight(48),
        ),
        onPressed: (_transferring || _selectedBed == null) ? null : _transfer,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final invoices = _invoices;
    final allSettled = invoices != null && invoices.isEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.swap_horiz_rounded, color: PgColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Transfer: ${widget.tenantName}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: FadeSlideIn(
            offset: 8,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Shift is a permanent bed transfer only — temporary stays are
                  // started from the Assign Bed flow, not here.
                  if (_mode == 'TEMPORARY') ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: PgColors.primary.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(children: [
                        Icon(Icons.info_outline, color: PgColors.primary, size: 18),
                        SizedBox(width: 8),
                        Expanded(child: Text(
                          'A single invoice is raised for the amount above. Make it permanent or move them back later.',
                          style: TextStyle(fontSize: 12.5, color: PgColors.primary),
                        )),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    ..._bedAndConfirm(),
                  ] else ...[
                    // ── Invoice settlement section ──────────────────────────
                    if (invoices == null && _loadError == null)
                      const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
                    if (_loadError != null)
                      Text('Failed to load dues: $_loadError', style: const TextStyle(color: Colors.red)),
                    if (invoices != null && invoices.isNotEmpty) ...[
                      const Text('Settle dues before transfer',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(height: 12),
                      for (final inv in invoices)
                        _InvoicePendingCard(
                          invoice: inv,
                          payOpen: _payOpen.contains((inv['invoice_id'] as num).toInt()),
                          amountCtrl: _getOrCreateCtrl(inv),
                          payMode: _payMode[(inv['invoice_id'] as num).toInt()] ?? 'CASH',
                          onTogglePay: () => _togglePay((inv['invoice_id'] as num).toInt()),
                          onPayModeChange: (m) => setState(() => _payMode[(inv['invoice_id'] as num).toInt()] = m),
                          onPay: () => _pay(inv),
                          onWriteOff: () => _writeOff(inv),
                          showWriteOff: false, // Shift: only Pay is allowed
                        ),
                    ],
                    if (allSettled) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: PgColors.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(children: [
                          Icon(Icons.check_circle_outline, color: PgColors.success, size: 18),
                          SizedBox(width: 8),
                          Text('No pending dues', style: TextStyle(color: PgColors.success, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                      const SizedBox(height: 20),
                      ..._bedAndConfirm(),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      );
  }
}

// ─── Bed Picker (grouped by room) ─────────────────────────────────────────────

class _BedPicker extends StatelessWidget {
  const _BedPicker({required this.beds, required this.selected, required this.onSelect});

  final List<Map<String, dynamic>> beds;
  final Map<String, dynamic>? selected;
  final ValueChanged<Map<String, dynamic>> onSelect;

  @override
  Widget build(BuildContext context) {
    // Group beds by room
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final bed in beds) {
      final roomLabel = '${bed['room_name'] ?? 'Room'}'
          '${bed['floor_name'] != null ? ' · ${bed['floor_name']}' : ''}';
      grouped.putIfAbsent(roomLabel, () => []).add(bed);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: grouped.entries.map((entry) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(entry.key,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: PgColors.primary)),
            ),
            ...entry.value.indexed.map((rec) {
              final i = rec.$1;
              final bed = rec.$2;
              final bedId = bed['bed_id'];
              final isSelected = selected != null && selected!['bed_id'] == bedId;
              return FadeSlideIn(
                delay: Duration(milliseconds: 40 * (i.clamp(0, 8))),
                offset: 8,
                child: GestureDetector(
                onTap: () => onSelect(bed),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? PgColors.lavender : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? PgColors.primary : Colors.grey.shade200,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(children: [
                    Icon(Icons.bed_outlined,
                        size: 18,
                        color: isSelected ? PgColors.primary : Colors.grey.shade600),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${bed['bed_name'] ?? 'Bed'}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isSelected ? PgColors.primary : const Color(0xFF1A1A2E),
                        ),
                      ),
                    ),
                    if (bed['sharing_type'] != null)
                      Text('${bed['sharing_type']}-Sharing',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    if (isSelected) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.check_circle_rounded, color: PgColors.primary, size: 18),
                    ],
                  ]),
                ),
                ),
              );
            }),
            const SizedBox(height: 8),
          ],
        );
      }).toList(),
    );
  }
}
