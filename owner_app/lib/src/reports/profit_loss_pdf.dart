import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../utils/expense_categories.dart';
import 'report_pdf_common.dart';

/// Profit & Loss for a date range, from `GET /reports/profit-loss`.
///
/// Cash basis — money actually received and actually spent, not what was
/// invoiced — so it reconciles with the transactions ledger. Portrait A4: this
/// is a statement, not a wide table.
Future<Uint8List> buildProfitLossPdf(Map<String, dynamic> report) {
  final s = Map<String, dynamic>.from((report['summary'] as Map?) ?? const {});
  final months = [
    for (final e in (report['months'] as List? ?? const []))
      Map<String, dynamic>.from(e as Map),
  ];
  final byCategory = [
    for (final e in (report['expenseByCategory'] as List? ?? const []))
      Map<String, dynamic>.from(e as Map),
  ];
  final scope = '${report['propertyName'] ?? report['organizationName'] ?? ''}';
  final range =
      '${pdfDate(report['fromDate'])} to ${pdfDate(report['toDate'])}';
  final net = pdfNum(s['netProfit']) ?? 0;

  return buildReportDocument(
    title: 'Profit & Loss Report',
    scopeLine: pdfScopeLine(scope, range),
    pageFormat: PdfPageFormat.a4,
    summary: const [],
    body: (context) => [
      // The six headline figures, as a statement rather than a table row.
      _statement([
        ['Total Rent', pdfMoney(s['totalRent']), false],
        ['Other Income', pdfMoney(s['otherIncome']), false],
        ['Total Income', pdfMoney(s['totalIncome']), true],
        ['Total Expenses', pdfMoney(s['totalExpenses']), false],
        ['Net Profit', pdfMoney(s['netProfit']), true],
        ['Profit Margin', '${pdfPlain(s['profitMarginPct'], pattern: '#,##0.0')}%', false],
      ], net),
      pw.SizedBox(height: 8),
      pw.Text(
          'Cash basis: income is payments received in the period; expenses are approved '
          'or paid entries dated in it. Total Rent is the part of receipts applied to '
          'invoices, Other Income the remainder (advances and unallocated receipts).',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      if (months.length > 1) ...[
        pw.SizedBox(height: 20),
        pdfSectionTitle('Month by Month'),
        pdfTable(
          fontSize: 9,
          headers: const ['Month', 'Income', 'Expenses', 'Net'],
          columnWidths: const {
            0: pw.FlexColumnWidth(2.4),
            1: pw.FlexColumnWidth(2),
            2: pw.FlexColumnWidth(2),
            3: pw.FlexColumnWidth(2),
          },
          rightAlign: const {1, 2, 3},
          rows: [
            for (final m in months)
              [
                pdfMonthLabel('${m['month'] ?? ''}'),
                pdfMoney(m['income']),
                pdfMoney(m['expenses']),
                pdfMoney(m['net']),
              ],
          ],
        ),
      ],
      if (byCategory.isNotEmpty) ...[
        pw.SizedBox(height: 20),
        pdfSectionTitle('Where the Expenses Went'),
        pdfTable(
          fontSize: 9,
          headers: const ['Category', 'Amount', 'Share of Expenses'],
          columnWidths: const {
            0: pw.FlexColumnWidth(3.4),
            1: pw.FlexColumnWidth(2),
            2: pw.FlexColumnWidth(2),
          },
          rightAlign: const {1, 2},
          rows: [
            for (final c in byCategory)
              [
                expenseCategoryLabel('${c['category']}'),
                pdfMoney(c['total']),
                _share(c['total'], s['totalExpenses']),
              ],
          ],
        ),
      ],
    ],
  );
}

/// Label/amount rows; `emphasised` rows get a rule above and bold type, and the
/// net line is coloured by whether the period made money.
pw.Widget _statement(List<List<Object>> rows, num net) {
  return pw.Container(
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: pw.BoxDecoration(
              color: rows[i][2] == true ? PdfColors.grey100 : null,
              border: i == 0
                  ? null
                  : const pw.Border(
                      top: pw.BorderSide(color: PdfColors.grey300, width: 0.4)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('${rows[i][0]}',
                    style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: rows[i][2] == true
                            ? pw.FontWeight.bold
                            : pw.FontWeight.normal)),
                pw.Text('${rows[i][1]}',
                    style: pw.TextStyle(
                        fontSize: 11.5,
                        fontWeight: rows[i][2] == true
                            ? pw.FontWeight.bold
                            : pw.FontWeight.normal,
                        color: rows[i][0] == 'Net Profit'
                            ? (net < 0 ? PdfColors.red800 : PdfColors.green800)
                            : PdfColors.black)),
              ],
            ),
          ),
      ],
    ),
  );
}

String _share(dynamic part, dynamic total) {
  final p = pdfNum(part) ?? 0;
  final t = pdfNum(total) ?? 0;
  if (t <= 0) return '-';
  return '${(p / t * 100).round()}%';
}
