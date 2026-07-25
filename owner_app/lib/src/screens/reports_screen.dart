import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../reports/expense_report_pdf.dart';
import '../reports/report_download.dart';
import '../reports/outstanding_dues_pdf.dart';
import '../reports/profit_loss_pdf.dart';
import '../reports/rent_collection_pdf.dart';
import '../theme/app_theme.dart';
import '../utils/expense_categories.dart';
import '../widgets/app_toast.dart';

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

// ─────────────────────────────────────────────────────────── download plumbing ──

/// What one download produced: how many rows it covered and where it landed.
typedef _DownloadResult = ({int rows, SavedReport saved});

/// Fetches [path], renders it with [build] and writes it straight to device
/// storage — no folder chooser, no share sheet.
Future<_DownloadResult> _downloadReport(
  BuildContext context, {
  required String path,
  required Future<Uint8List> Function(Map<String, dynamic>) build,
  required String filename,
  String rowsKey = 'items',
}) async {
  final report = await context.read<AppState>().apiClient.get(path);
  final data = Map<String, dynamic>.from(report);
  final bytes = await build(data);
  final saved = await savePdfToDevice(bytes, filename);
  return (rows: (data[rowsKey] as List?)?.length ?? 0, saved: saved);
}

// ─────────────────────────────────────────────────────────────────── the cards ──

class _RentCollectionCard extends StatefulWidget {
  const _RentCollectionCard({required this.propertyId});
  final int propertyId;

  @override
  State<_RentCollectionCard> createState() => _RentCollectionCardState();
}

class _RentCollectionCardState extends State<_RentCollectionCard> {
  DateTime _month = _thisMonth();
  bool _busy = false;

  Future<void> _download() async {
    await _runDownload(
      context,
      setBusy: (v) => setState(() => _busy = v),
      run: () => _downloadReport(
        context,
        path: '/reports/rent-collection'
            '?propertyId=${widget.propertyId}&month=${_monthParam(_month)}',
        build: buildRentCollectionPdf,
        filename: 'rent-collection-${_fileMonth(_month)}.pdf',
      ),
      emptyMessage: 'No invoices for ${_monthLabel(_month)}',
      okMessage: (n) => 'Rent Collection Report ready · $n invoice${n == 1 ? '' : 's'}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return _ReportCard(
      icon: Icons.bar_chart_rounded,
      iconBg: const Color(0xFFEDE9FE),
      iconColor: const Color(0xFF6D28D9),
      title: 'Rent Collection Report',
      subtitle: 'Monthly rent collection summary',
      busy: _busy,
      onDownload: _busy ? null : _download,
      filters: [
        _MonthField(
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
  DateTime _month = _thisMonth();
  bool _busy = false;

  // Month only: the report is the whole property's arrears list, so there is no
  // tenant filter and no tenant list is ever fetched here.
  Future<void> _download() async {
    await _runDownload(
      context,
      setBusy: (v) => setState(() => _busy = v),
      run: () => _downloadReport(
        context,
        path: '/reports/outstanding-dues'
            '?propertyId=${widget.propertyId}&month=${_monthParam(_month)}',
        build: buildOutstandingDuesPdf,
        filename: 'outstanding-dues-${_fileMonth(_month)}.pdf',
      ),
      emptyMessage: 'No outstanding dues for ${_monthLabel(_month)}',
      okMessage: (n) => 'Outstanding Due Report ready · $n tenant${n == 1 ? '' : 's'}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return _ReportCard(
      icon: Icons.receipt_long_rounded,
      iconBg: const Color(0xFFFFEDD5),
      iconColor: const Color(0xFFEA580C),
      title: 'Outstanding Due Report',
      subtitle: 'Tenants with outstanding dues',
      busy: _busy,
      onDownload: _busy ? null : _download,
      filters: [
        _MonthField(
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
  DateTime _month = _thisMonth();
  String _category = 'ALL';
  bool _busy = false;

  Future<void> _pickCategory() async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _PickerSheet(
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
    await _runDownload(
      context,
      setBusy: (v) => setState(() => _busy = v),
      run: () => _downloadReport(
        context,
        path: '/reports/expenses'
            '?propertyId=${widget.propertyId}&month=${_monthParam(_month)}'
            '${_category == 'ALL' ? '' : '&category=$_category'}',
        build: buildExpenseReportPdf,
        filename: 'expenses-${_fileMonth(_month)}.pdf',
      ),
      emptyMessage: 'No approved expenses for ${_monthLabel(_month)}',
      okMessage: (n) => 'Expense Report ready · $n entr${n == 1 ? 'y' : 'ies'}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return _ReportCard(
      icon: Icons.account_balance_wallet_rounded,
      iconBg: const Color(0xFFDCFCE7),
      iconColor: const Color(0xFF16A34A),
      title: 'Expense Report',
      subtitle: 'Summary of all expenses',
      busy: _busy,
      onDownload: _busy ? null : _download,
      filters: [
        _MonthField(
          label: 'Month',
          value: _month,
          enabled: !_busy,
          onChanged: (m) => setState(() => _month = m),
        ),
        _ChoiceField(
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
    await _runDownload(
      context,
      setBusy: (v) => setState(() => _busy = v),
      run: () => _downloadReport(
        context,
        path: '/reports/profit-loss'
            '?propertyId=${widget.propertyId}'
            '&from=${_dateParam(_from)}&to=${_dateParam(_to)}',
        build: buildProfitLossPdf,
        filename:
            'profit-loss-${_dateParam(_from)}-to-${_dateParam(_to)}.pdf',
        // A P&L is aggregates, not rows — count the month breakdown instead.
        rowsKey: 'months',
      ),
      emptyMessage: 'Profit & Loss Report ready',
      okMessage: (n) => 'Profit & Loss Report ready',
    );
  }

  @override
  Widget build(BuildContext context) {
    return _ReportCard(
      icon: Icons.swap_horiz_rounded,
      iconBg: const Color(0xFFDBEAFE),
      iconColor: const Color(0xFF2563EB),
      title: 'Profit & Loss Report',
      subtitle: 'Income, expenses and net profit',
      busy: _busy,
      onDownload: _busy ? null : _download,
      filters: [
        _ChoiceField(
          label: 'From Date',
          value: DateFormat('dd MMM yyyy').format(_from),
          icon: Icons.calendar_today_rounded,
          enabled: !_busy,
          onTap: () => _pickDate(isFrom: true),
        ),
        _ChoiceField(
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

/// One report: icon, title, inline filters and the download button. Filters sit
/// beside the button on a wide card and stack above it on a narrow one.
class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.filters,
    required this.busy,
    required this.onDownload,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final List<Widget> filters;
  final bool busy;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final button = _DownloadButton(busy: busy, onPressed: onDownload);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PgColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: iconColor, size: 23),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15.5,
                            color: PgColors.textPrimary)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style:
                            TextStyle(fontSize: 12.5, color: Colors.grey[600])),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, c) {
              // Two filters plus a 170px button need real estate; below that the
              // button drops to its own full-width row.
              final inline = c.maxWidth >= 150.0 * filters.length + 190;
              final filterRow = Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < filters.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(child: filters[i]),
                  ],
                ],
              );
              if (inline) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: filterRow),
                    const SizedBox(width: 12),
                    button,
                  ],
                );
              }
              return Column(
                children: [
                  filterRow,
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, child: button),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DownloadButton extends StatelessWidget {
  const _DownloadButton({required this.busy, required this.onPressed});
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child:
                  CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.picture_as_pdf_rounded, size: 18),
      label: Text(busy ? 'Preparing…' : 'Download PDF',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
      style: FilledButton.styleFrom(
        backgroundColor: PgColors.primary,
        disabledBackgroundColor: PgColors.primary.withValues(alpha: 0.6),
        disabledForegroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        minimumSize: const Size(0, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

/// Labelled, bordered field that opens a picker — the visual unit from the
/// design (small grey label over a rounded box with a leading icon).
class _ChoiceField extends StatelessWidget {
  const _ChoiceField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
        const SizedBox(height: 5),
        InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: PgColors.border),
            ),
            child: Row(
              children: [
                Icon(icon, size: 17, color: PgColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: PgColors.textPrimary)),
                ),
                Icon(Icons.keyboard_arrow_down_rounded,
                    size: 19, color: Colors.grey[500]),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Month variant of [_ChoiceField]. These reports are month-scoped, so the
/// picker offers **month and year only** — a day-grid date picker would ask for
/// a value the report does not use.
class _MonthField extends StatelessWidget {
  const _MonthField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return _ChoiceField(
      label: label,
      value: DateFormat('MMM yyyy').format(value),
      icon: Icons.calendar_month_rounded,
      enabled: enabled,
      onTap: () async {
        final picked = await showDialog<DateTime>(
          context: context,
          builder: (_) => _MonthYearDialog(initial: value),
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

/// Year stepper over a 12-month grid. Future months are disabled — a report
/// cannot be run for a month that has not happened.
class _MonthYearDialog extends StatefulWidget {
  const _MonthYearDialog({required this.initial});
  final DateTime initial;

  @override
  State<_MonthYearDialog> createState() => _MonthYearDialogState();
}

class _MonthYearDialogState extends State<_MonthYearDialog> {
  static const _labels = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  late int _year = widget.initial.year;
  late int _month = widget.initial.month;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final firstYear = now.year - 5;
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('Select Month',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  tooltip: 'Previous year',
                  onPressed: _year > firstYear
                      ? () => setState(() => _year--)
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Text('$_year',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: PgColors.textPrimary)),
                IconButton(
                  tooltip: 'Next year',
                  onPressed:
                      _year < now.year ? () => setState(() => _year++) : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: 6),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.1,
              children: [
                for (var m = 1; m <= 12; m++)
                  _monthChip(m, enabled: !_isFuture(m, now)),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _isFuture(_month, now)
              ? null
              : () => Navigator.pop(context, DateTime(_year, _month)),
          style: FilledButton.styleFrom(backgroundColor: PgColors.primary),
          child: const Text('Select'),
        ),
      ],
    );
  }

  bool _isFuture(int month, DateTime now) =>
      _year > now.year || (_year == now.year && month > now.month);

  Widget _monthChip(int month, {required bool enabled}) {
    final selected = month == _month;
    return InkWell(
      onTap: enabled ? () => setState(() => _month = month) : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? PgColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? PgColors.primary : PgColors.border),
        ),
        child: Text(
          _labels[month - 1],
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: !enabled
                ? PgColors.textTertiary
                : selected
                    ? Colors.white
                    : PgColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// Bottom-sheet list picker used for the Tenant and Category filters.
class _PickerSheet extends StatelessWidget {
  const _PickerSheet({
    required this.title,
    required this.options,
    required this.selectedId,
    required this.icon,
  });

  final String title;
  final List<Map<String, dynamic>> options;
  final Object? selectedId;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: PgColors.textPrimary)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                children: [
                  for (final o in options)
                    ListTile(
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                            color: PgColors.lavender,
                            borderRadius: BorderRadius.circular(11)),
                        child:
                            Icon(icon, color: PgColors.primary, size: 19),
                      ),
                      title: Text('${o['label']}',
                          style: const TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w600)),
                      trailing: o['id'] == selectedId
                          ? const Icon(Icons.check_circle_rounded,
                              color: PgColors.primary, size: 21)
                          : null,
                      onTap: () => Navigator.pop(context, o),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────── helpers ──

/// Runs a download with the busy flag and the result toast handled in one
/// place. The messenger is captured before the await so the toast survives the
/// PDF viewer taking focus.
Future<void> _runDownload(
  BuildContext context, {
  required void Function(bool) setBusy,
  required Future<_DownloadResult> Function() run,
  required String emptyMessage,
  required String Function(int) okMessage,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  setBusy(true);
  try {
    final result = await run();
    final what = result.rows == 0 ? emptyMessage : okMessage(result.rows);
    // Always say where it went — the file is saved without a chooser, so the
    // toast is the only place the owner learns the location.
    AppToast.successOf(messenger, '$what · saved to ${result.saved.folder}',
        title: 'Report Downloaded');
  } catch (e) {
    AppToast.errorOf(messenger, e.toString().replaceFirst('Exception: ', ''));
  } finally {
    setBusy(false);
  }
}

DateTime _thisMonth() => DateTime(DateTime.now().year, DateTime.now().month);

String _monthParam(DateTime m) =>
    '${m.year}-${m.month.toString().padLeft(2, '0')}';

String _fileMonth(DateTime m) => DateFormat('MMM-yyyy').format(m);

String _monthLabel(DateTime m) => DateFormat('MMMM yyyy').format(m);

String _dateParam(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
