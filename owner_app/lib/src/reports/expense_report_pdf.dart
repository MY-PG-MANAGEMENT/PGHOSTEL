import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../utils/expense_categories.dart';
import 'report_pdf_common.dart';

/// Expense Report — the month's operational spend, from `GET /reports/expenses`.
/// Only APPROVED/PAID rows are included (a pending expense is not money out yet),
/// which keeps the total equal to the expenses dashboard for the same month.
Future<Uint8List> buildExpenseReportPdf(Map<String, dynamic> report) {
  final items = [
    for (final e in (report['items'] as List? ?? const []))
      Map<String, dynamic>.from(e as Map),
  ];
  final categories = [
    for (final e in (report['categories'] as List? ?? const []))
      Map<String, dynamic>.from(e as Map),
  ];
  final s = Map<String, dynamic>.from((report['summary'] as Map?) ?? const {});
  final monthLabel = pdfMonthLabel('${report['month'] ?? ''}');
  final scope = '${report['propertyName'] ?? report['organizationName'] ?? ''}';
  final filtered = '${report['category'] ?? 'ALL'}';
  final categoryLine =
      filtered == 'ALL' ? '' : ' | ${expenseCategoryLabel(filtered)} only';

  return buildReportDocument(
    title: 'Expense Report',
    scopeLine: '${pdfScopeLine(scope, monthLabel)}$categoryLine',
    summary: [
      ['Entries', '${s['expenseCount'] ?? 0}'],
      ['Total spend', pdfMoney(s['totalAmount'])],
      ['Categories', '${categories.length}'],
    ],
    body: (context) => [
      if (items.isEmpty)
        pdfEmptyState('No approved expenses recorded for $monthLabel.')
      else ...[
        pdfTable(
          fontSize: 8,
          headers: const [
            'Date', 'Category', 'Vendor', 'Description', 'Property',
            'Amount', 'Payment Method', 'Paid By',
          ],
          columnWidths: const {
            0: pw.FlexColumnWidth(1.5),
            1: pw.FlexColumnWidth(1.8),
            2: pw.FlexColumnWidth(2.0),
            3: pw.FlexColumnWidth(3.4),
            4: pw.FlexColumnWidth(2.0),
            5: pw.FlexColumnWidth(1.7),
            6: pw.FlexColumnWidth(1.7),
            7: pw.FlexColumnWidth(2.0),
          },
          rightAlign: const {5},
          rows: [
            for (final i in items)
              [
                pdfDate(i['expenseDate']),
                expenseCategoryLabel('${i['category']}'),
                '${i['vendor'] ?? ''}',
                '${i['description'] ?? ''}',
                '${i['property'] ?? ''}',
                pdfMoney(i['amount']),
                _method('${i['paymentMethod'] ?? ''}'),
                '${i['paidBy'] ?? ''}',
              ],
          ],
        ),
        if (categories.length > 1) ...[
          pw.SizedBox(height: 18),
          pdfSectionTitle('Category Summary'),
          pdfTable(
            fontSize: 8.5,
            headers: const ['Category', 'Amount', 'Share'],
            columnWidths: const {
              0: pw.FlexColumnWidth(4),
              1: pw.FlexColumnWidth(2),
              2: pw.FlexColumnWidth(1.4),
            },
            rightAlign: const {1, 2},
            rows: [
              for (final c in categories)
                [
                  expenseCategoryLabel('${c['category']}'),
                  pdfMoney(c['total']),
                  _share(c['total'], s['totalAmount']),
                ],
            ],
          ),
        ],
      ],
    ],
  );
}

String _method(String code) => switch (code) {
      'CASH' => 'Cash',
      'UPI' => 'UPI',
      'CARD' => 'Card',
      'BANK_TRANSFER' => 'Bank Transfer',
      _ => code,
    };

String _share(dynamic part, dynamic total) {
  final p = pdfNum(part) ?? 0;
  final t = pdfNum(total) ?? 0;
  if (t <= 0) return '-';
  return '${(p / t * 100).round()}%';
}
