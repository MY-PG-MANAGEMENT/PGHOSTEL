
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../reports/expense_report_pdf.dart';
import '../reports/report_ui.dart';
import '../reports/outstanding_dues_pdf.dart';
import '../reports/profit_loss_pdf.dart';
import '../reports/rent_collection_pdf.dart';
import '../theme/app_theme.dart';
import '../utils/expense_categories.dart';

/// Reports tab of the property workspace: pick filters, get a PDF.
///
/// Deliberately not an on-screen dashboard — every card is "choose a scope,
/// download". Each card owns its own filter state and busy flag so one download
/// never blocks another, and nothing is fetched until a download is requested.
class ReportsTab extends StatelessWidget {
  const ReportsTab({super.key, required this.propertyId, this.propertyName});

  final int propertyId;
  final String? propertyName;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
      children: [
        const Text('Reports',
            style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 26,
                color: PgColors.textPrimary)),
        const SizedBox(height: 6),
        Text('Generate and download reports with specific filters.',
            style: TextStyle(fontSize: 13.5, color: Colors.grey[600])),
        const SizedBox(height: 18),
        _RentCollectionCard(propertyId: propertyId),
        const SizedBox(height: 14),
        _OutstandingDueCard(propertyId: propertyId),
        const SizedBox(height: 14),
        _ExpenseCard(propertyId: propertyId),
        const SizedBox(height: 14),
        _ProfitLossCard(propertyId: propertyId),
      ],
    );
  }
}


// ─────────────────────────────────────────────────────────────────── the cards ──

class _RentCollectionCard extends StatefulWidget {
  const _RentCollectionCard({required this.propertyId});
  final int propertyId;

  @override
  State<_RentCollectionCard> createState() => _RentCollectionCardState();
}

class _RentCollectionCardState extends State<_RentCollectionCard> {
  DateTime _month = reportThisMonth();
  bool _busy = false;

  Future<void> _download() async {
    await runReportDownload(
      context,
      setBusy: (v) => setState(() => _busy = v),
      run: () => downloadReport(
        context,
        path: '/reports/rent-collection'
            '?propertyId=${widget.propertyId}&month=${reportMonthParam(_month)}',
        build: buildRentCollectionPdf,
        filename: 'rent-collection-${reportFileMonth(_month)}.pdf',
      ),
      emptyMessage: 'No invoices for ${reportMonthLabel(_month)}',
      okMessage: (n) => 'Rent Collection Report ready · $n invoice${n == 1 ? '' : 's'}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ReportCard(
      icon: Icons.bar_chart_rounded,
      iconBg: const Color(0xFFEDE9FE),
      iconColor: const Color(0xFF6D28D9),
      title: 'Rent Collection Report',
      subtitle: 'Monthly rent collection summary',
      busy: _busy,
      onDownload: _busy ? null : _download,
      filters: [
        ReportMonthField(
          label: 'Month',
          value: _month,
          enabled: !_busy,
          onChanged: (m) => setState(() => _month = m),
        ),
      ],
    );
  }
}

class _OutstandingDueCard extends StatefulWidget {
  const _OutstandingDueCard({required this.propertyId});
  final int propertyId;

  @override
  State<_OutstandingDueCard> createState() => _OutstandingDueCardState();
}

class _OutstandingDueCardState extends State<_OutstandingDueCard> {
  DateTime _month = reportThisMonth();
  bool _busy = false;

  // Month only: the report is the whole property's arrears list, so there is no
  // tenant filter and no tenant list is ever fetched here.
  Future<void> _download() async {
    await runReportDownload(
      context,
      setBusy: (v) => setState(() => _busy = v),
      run: () => downloadReport(
        context,
        path: '/reports/outstanding-dues'
            '?propertyId=${widget.propertyId}&month=${reportMonthParam(_month)}',
        build: buildOutstandingDuesPdf,
        filename: 'outstanding-dues-${reportFileMonth(_month)}.pdf',
      ),
      emptyMessage: 'No outstanding dues for ${reportMonthLabel(_month)}',
      okMessage: (n) => 'Outstanding Due Report ready · $n tenant${n == 1 ? '' : 's'}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ReportCard(
      icon: Icons.receipt_long_rounded,
      iconBg: const Color(0xFFFFEDD5),
      iconColor: const Color(0xFFEA580C),
      title: 'Outstanding Due Report',
      subtitle: 'Tenants with outstanding dues',
      busy: _busy,
      onDownload: _busy ? null : _download,
      filters: [
        ReportMonthField(
          label: 'Month',
          value: _month,
          enabled: !_busy,
          onChanged: (m) => setState(() => _month = m),
        ),
      ],
    );
  }
}

class _ExpenseCard extends StatefulWidget {
  const _ExpenseCard({required this.propertyId});
  final int propertyId;

  @override
  State<_ExpenseCard> createState() => _ExpenseCardState();
}

class _ExpenseCardState extends State<_ExpenseCard> {
  DateTime _month = reportThisMonth();
  String _category = 'ALL';
  bool _busy = false;

  Future<void> _pickCategory() async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => ReportPickerSheet(
        title: 'Select Category',
        options: [
          const {'id': 'ALL', 'label': 'All Categories'},
          for (final e in expenseCategoryMeta.entries)
            {'id': e.key, 'label': e.value.label},
        ],
        selectedId: _category,
        icon: Icons.grid_view_rounded,
      ),
    );
    if (picked != null) setState(() => _category = '${picked['id']}');
  }

  Future<void> _download() async {
    await runReportDownload(
      context,
      setBusy: (v) => setState(() => _busy = v),
      run: () => downloadReport(
        context,
        path: '/reports/expenses'
            '?propertyId=${widget.propertyId}&month=${reportMonthParam(_month)}'
            '${_category == 'ALL' ? '' : '&category=$_category'}',
        build: buildExpenseReportPdf,
        filename: 'expenses-${reportFileMonth(_month)}.pdf',
      ),
      emptyMessage: 'No approved expenses for ${reportMonthLabel(_month)}',
      okMessage: (n) => 'Expense Report ready · $n entr${n == 1 ? 'y' : 'ies'}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ReportCard(
      icon: Icons.account_balance_wallet_rounded,
      iconBg: const Color(0xFFDCFCE7),
      iconColor: const Color(0xFF16A34A),
      title: 'Expense Report',
      subtitle: 'Summary of all expenses',
      busy: _busy,
      onDownload: _busy ? null : _download,
      filters: [
        ReportMonthField(
          label: 'Month',
          value: _month,
          enabled: !_busy,
          onChanged: (m) => setState(() => _month = m),
        ),
        ReportChoiceField(
          label: 'Category',
          value: _category == 'ALL'
              ? 'All Categories'
              : expenseCategoryLabel(_category),
          icon: Icons.grid_view_rounded,
          enabled: !_busy,
          onTap: _pickCategory,
        ),
      ],
    );
  }
}

class _ProfitLossCard extends StatefulWidget {
  const _ProfitLossCard({required this.propertyId});
  final int propertyId;

  @override
  State<_ProfitLossCard> createState() => _ProfitLossCardState();
}

class _ProfitLossCardState extends State<_ProfitLossCard> {
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  bool _busy = false;

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final initial = isFrom ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: isFrom ? 'From date' : 'To date',
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (_to.isBefore(_from)) _to = _from; // keep the range valid
      } else {
        _to = picked;
        if (_to.isBefore(_from)) _from = _to;
      }
    });
  }

  Future<void> _download() async {
    await runReportDownload(
      context,
      setBusy: (v) => setState(() => _busy = v),
      run: () => downloadReport(
        context,
        path: '/reports/profit-loss'
            '?propertyId=${widget.propertyId}'
            '&from=${reportDateParam(_from)}&to=${reportDateParam(_to)}',
        build: buildProfitLossPdf,
        filename:
            'profit-loss-${reportDateParam(_from)}-to-${reportDateParam(_to)}.pdf',
        // A P&L is aggregates, not rows — count the month breakdown instead.
        rowsKey: 'months',
      ),
      emptyMessage: 'Profit & Loss Report ready',
      okMessage: (n) => 'Profit & Loss Report ready',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ReportCard(
      icon: Icons.swap_horiz_rounded,
      iconBg: const Color(0xFFDBEAFE),
      iconColor: const Color(0xFF2563EB),
      title: 'Profit & Loss Report',
      subtitle: 'Income, expenses and net profit',
      busy: _busy,
      onDownload: _busy ? null : _download,
      filters: [
        ReportChoiceField(
          label: 'From Date',
          value: DateFormat('dd MMM yyyy').format(_from),
          icon: Icons.calendar_today_rounded,
          enabled: !_busy,
          onTap: () => _pickDate(isFrom: true),
        ),
        ReportChoiceField(
          label: 'To Date',
          value: DateFormat('dd MMM yyyy').format(_to),
          icon: Icons.calendar_today_rounded,
          enabled: !_busy,
          onTap: () => _pickDate(isFrom: false),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────── shared widgets ──

