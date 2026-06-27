import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme/app_theme.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _amountCtrl.values) {
      c.dispose();
    }
    super.dispose();
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
        content: Text('Mark ₹$balance due for $month as written off?'),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  Future<void> _pay(Map<String, dynamic> invoice) async {
    final id = (invoice['invoice_id'] as num).toInt();
    final ctrl = _amountCtrl[id];
    if (ctrl == null) return;
    final amount = double.tryParse(ctrl.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  Future<void> _checkout() async {
    setState(() => _checkingOut = true);
    final d = _checkoutDate;
    final iso =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    try {
      await context.read<AppState>().apiClient.post('/occupancy/checkout', {
        'partyId': widget.partyId,
        'checkoutDate': iso,
      });
      if (mounted) {
        Navigator.pop(context, true);
        widget.onCheckedOut();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _checkingOut = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', ''))));
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
  });

  final Map<String, dynamic> invoice;
  final bool payOpen;
  final TextEditingController amountCtrl;
  final String payMode;
  final VoidCallback onTogglePay;
  final ValueChanged<String> onPayModeChange;
  final VoidCallback onPay;
  final VoidCallback onWriteOff;

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
                _stat('Total', '₹${invoice['total_amount']}'),
                const SizedBox(width: 16),
                _stat('Paid', '₹${invoice['paid_amount']}',
                    color: PgColors.success),
                const SizedBox(width: 16),
                _stat('Balance', '₹${invoice['balance']}',
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

class TransferBedSheet extends StatefulWidget {
  const TransferBedSheet({
    required this.partyId,
    required this.tenantName,
    required this.currentPropertyId,
    required this.onTransferred,
    super.key,
  });

  final int partyId;
  final String tenantName;
  final int? currentPropertyId;
  final VoidCallback onTransferred;

  @override
  State<TransferBedSheet> createState() => _TransferBedSheetState();
}

class _TransferBedSheetState extends State<TransferBedSheet> {
  // ── invoice settlement (same as checkout) ──
  List<Map<String, dynamic>>? _invoices;
  String? _loadError;
  final Set<int> _payOpen = {};
  final Map<int, TextEditingController> _amountCtrl = {};
  final Map<int, String> _payMode = {};

  // ── bed selection ──
  List<Map<String, dynamic>>? _vacantBeds;
  String? _bedsError;
  Map<String, dynamic>? _selectedBed;
  DateTime _transferDate = DateTime.now();
  bool _transferring = false;
  final _rentCtrl = TextEditingController();
  double? _standardRent;

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
        content: Text('Mark ₹$balance due for $month as written off?'),
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
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  Future<void> _pay(Map<String, dynamic> invoice) async {
    final id = (invoice['invoice_id'] as num).toInt();
    final ctrl = _amountCtrl[id];
    if (ctrl == null) return;
    final amount = double.tryParse(ctrl.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
      return;
    }
    final mode = _payMode[id] ?? 'CASH';
    final key = '${widget.partyId}-$id-${DateTime.now().millisecondsSinceEpoch}';
    try {
      await context.read<AppState>().apiClient.post('/billing/payments', {
        'invoiceId': id, 'amount': amount, 'paymentMode': mode, 'idempotencyKey': key,
      });
      await _loadInvoices();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  Future<void> _pickTransferDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _transferDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
      helpText: 'Select transfer date',
    );
    if (picked != null) setState(() => _transferDate = picked);
  }

  Future<void> _transfer() async {
    if (_selectedBed == null) return;
    setState(() => _transferring = true);
    final d = _transferDate;
    final iso = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final rent = double.tryParse(_rentCtrl.text.trim());
    try {
      await context.read<AppState>().apiClient.post('/occupancy/transfer-bed', {
        'partyId': widget.partyId,
        'newBedFacilityId': (_selectedBed!['bed_id'] as num).toInt(),
        'transferDate': iso,
        if (rent != null && rent > 0) 'monthlyRent': rent,
      });
      if (mounted) {
        Navigator.pop(context, true);
        widget.onTransferred();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _transferring = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
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
            width: 40, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
            child: Row(
              children: [
                const Icon(Icons.swap_horiz_rounded, color: PgColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Transfer: ${widget.tenantName}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          const Divider(height: 1),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.78),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                      ),
                  ],

                  // ── Bed selection + confirm (shown only when dues cleared) ──
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

                    // Bed picker
                    const Text('Select New Bed',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 10),
                    if (widget.currentPropertyId == null)
                      const Text('Property info unavailable — refresh the tenant detail and try again.',
                          style: TextStyle(color: Colors.grey))
                    else if (_vacantBeds == null && _bedsError == null)
                      const Center(child: CircularProgressIndicator())
                    else if (_bedsError != null)
                      Text('Failed to load beds: $_bedsError', style: const TextStyle(color: Colors.red))
                    else if (_vacantBeds!.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: const Text('No vacant beds in this property.',
                            style: TextStyle(color: Colors.grey), textAlign: TextAlign.center),
                      )
                    else
                      _BedPicker(
                        beds: _vacantBeds!,
                        selected: _selectedBed,
                        onSelect: _onBedSelected,
                      ),
                    const SizedBox(height: 16),

                    // Rent field — shown once a bed is selected
                    if (_selectedBed != null) ...[
                      TextField(
                        controller: _rentCtrl,
                        decoration: InputDecoration(
                          labelText: 'Monthly Rent (₹)',
                          prefixIcon: const Icon(Icons.currency_rupee),
                          helperText: _standardRent != null
                              ? 'Standard: ₹${_standardRent!.toStringAsFixed(0)}/mo'
                              : null,
                          helperStyle: const TextStyle(color: Color(0xFF2563EB), fontSize: 11),
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Transfer date
                    InkWell(
                      onTap: _transferring ? null : _pickTransferDate,
                      borderRadius: BorderRadius.circular(8),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Transfer Date',
                          prefixIcon: Icon(Icons.event_outlined),
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          '${_transferDate.day.toString().padLeft(2, '0')}-'
                          '${_transferDate.month.toString().padLeft(2, '0')}-'
                          '${_transferDate.year}',
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    FilledButton.icon(
                      icon: _transferring
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.swap_horiz_rounded),
                      label: Text(_transferring ? 'Transferring…' : 'Confirm Transfer'),
                      style: FilledButton.styleFrom(
                        backgroundColor: PgColors.primary,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: (_transferring || _selectedBed == null) ? null : _transfer,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
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
            ...entry.value.map((bed) {
              final bedId = bed['bed_id'];
              final isSelected = selected != null && selected!['bed_id'] == bedId;
              return GestureDetector(
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
              );
            }),
            const SizedBox(height: 8),
          ],
        );
      }).toList(),
    );
  }
}
