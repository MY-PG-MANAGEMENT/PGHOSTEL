import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import 'report_download.dart';

/// Shared UI kit for every "pick a scope, get a PDF" screen.
///
/// Extracted from the owner-side Reports tab so the super-admin Reports screen
/// reuses the same card, month picker, download plumbing and result toast rather
/// than growing a second, slowly-diverging copy. Anything here is used by at
/// least two screens; anything used by one report only stays with that report.
// ─────────────────────────────────────────────────────────── download plumbing ──

/// What one download produced: how many rows it covered and where it landed.
typedef ReportDownloadResult = ({int rows, SavedReport saved});

/// Fetches [path], renders it with [build] and writes it straight to device
/// storage — no folder chooser, no share sheet.
Future<ReportDownloadResult> downloadReport(
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

/// One report: icon, title, inline filters and the download button. Filters sit
/// beside the button on a wide card and stack above it on a narrow one.
class ReportCard extends StatelessWidget {
  const ReportCard({
    super.key,
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
    final button = _ReportDownloadButton(busy: busy, onPressed: onDownload);
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

class _ReportDownloadButton extends StatelessWidget {
  const _ReportDownloadButton({required this.busy, required this.onPressed});
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
class ReportChoiceField extends StatelessWidget {
  const ReportChoiceField({
    super.key,
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

/// Month variant of [ReportChoiceField]. These reports are month-scoped, so the
/// picker offers **month and year only** — a day-grid date picker would ask for
/// a value the report does not use.
class ReportMonthField extends StatelessWidget {
  const ReportMonthField({
    super.key,
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
    return ReportChoiceField(
      label: label,
      value: DateFormat('MMM yyyy').format(value),
      icon: Icons.calendar_month_rounded,
      enabled: enabled,
      onTap: () async {
        final picked = await showDialog<DateTime>(
          context: context,
          builder: (_) => ReportMonthYearDialog(initial: value),
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

/// Year stepper over a 12-month grid. Future months are disabled — a report
/// cannot be run for a month that has not happened.
class ReportMonthYearDialog extends StatefulWidget {
  const ReportMonthYearDialog({super.key, required this.initial});
  final DateTime initial;

  @override
  State<ReportMonthYearDialog> createState() => _ReportMonthYearDialogState();
}

class _ReportMonthYearDialogState extends State<ReportMonthYearDialog> {
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
class ReportPickerSheet extends StatelessWidget {
  const ReportPickerSheet({
    super.key,
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
Future<void> runReportDownload(
  BuildContext context, {
  required void Function(bool) setBusy,
  required Future<ReportDownloadResult> Function() run,
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

DateTime reportThisMonth() => DateTime(DateTime.now().year, DateTime.now().month);

String reportMonthParam(DateTime m) =>
    '${m.year}-${m.month.toString().padLeft(2, '0')}';

String reportFileMonth(DateTime m) => DateFormat('MMM-yyyy').format(m);

String reportMonthLabel(DateTime m) => DateFormat('MMMM yyyy').format(m);

String reportDateParam(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
