import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme/app_theme.dart';
import '../utils/date_utils.dart';

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
  final _checkoutDate = TextEditingController();
  bool _checkingOut = false;

  @override
  void initState() {
    super.initState();
    _checkoutDate.text = todayDmy();
    _load();
  }

  @override
  void dispose() {
    _checkoutDate.dispose();
    for (final c in _amountCtrl.values) {
      c.dispose();
    }
    super.dispose();
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
    try {
      await context.read<AppState>().apiClient.post('/occupancy/checkout', {
        'partyId': widget.partyId,
        if (_checkoutDate.text.isNotEmpty)
          'checkoutDate': dmyToIso(_checkoutDate.text.trim()),
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
                    TextFormField(
                      controller: _checkoutDate,
                      decoration: const InputDecoration(
                        labelText: 'Checkout Date (DD-MM-YYYY)',
                        prefixIcon: Icon(Icons.event_outlined),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.datetime,
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
