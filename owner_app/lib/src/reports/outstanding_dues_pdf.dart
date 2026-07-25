import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'report_pdf_common.dart';

/// Outstanding Dues — one row per tenant still owing money as of the selected
/// month, from `GET /reports/outstanding-dues`. Arrears are cumulative: a tenant
/// three months behind shows the whole balance, not just this month's slice.
Future<Uint8List> buildOutstandingDuesPdf(Map<String, dynamic> report) {
  final items = [
    for (final e in (report['items'] as List? ?? const []))
      Map<String, dynamic>.from(e as Map),
  ];
  final s = Map<String, dynamic>.from((report['summary'] as Map?) ?? const {});
  final monthLabel = pdfMonthLabel('${report['month'] ?? ''}');
  final scope = '${report['propertyName'] ?? report['organizationName'] ?? ''}';
  final asOf = s['asOf'] == null ? '' : ' (as of ${pdfDate(s['asOf'])})';

  return buildReportDocument(
    title: 'Outstanding Due Report',
    scopeLine: '${pdfScopeLine(scope, monthLabel)}$asOf',
    summary: [
      ['Tenants with dues', '${s['tenantCount'] ?? 0}'],
      ['Total outstanding', pdfMoney(s['totalDue'])],
      ['Overdue tenants', '${s['overdueCount'] ?? 0}'],
    ],
    body: (context) => [
      if (items.isEmpty)
        pdfEmptyState('No outstanding dues for $monthLabel. Everyone is settled.')
      else
        pdfTable(
          fontSize: 8,
          headers: const [
            'Tenant', 'Phone', 'Property', 'Room/Bed', 'Due Amount',
            'Due Since', 'Days Overdue', 'Last Payment', 'Next Due', 'Reminder',
          ],
          columnWidths: const {
            0: pw.FlexColumnWidth(2.4),
            1: pw.FlexColumnWidth(1.8),
            2: pw.FlexColumnWidth(2.0),
            3: pw.FlexColumnWidth(2.0),
            4: pw.FlexColumnWidth(1.7),
            5: pw.FlexColumnWidth(1.6),
            6: pw.FlexColumnWidth(1.3),
            7: pw.FlexColumnWidth(1.7),
            8: pw.FlexColumnWidth(1.6),
            9: pw.FlexColumnWidth(1.4),
          },
          rightAlign: const {4, 6},
          rows: [
            for (final i in items)
              [
                '${i['tenantName'] ?? ''}',
                '${i['phone'] ?? ''}',
                '${i['property'] ?? ''}',
                '${i['roomBed'] ?? ''}',
                pdfMoney(i['dueAmount']),
                pdfDate(i['dueSince']),
                '${pdfNum(i['daysOverdue'])?.toInt() ?? 0}',
                pdfDate(i['lastPaymentDate']),
                pdfDate(i['nextDueDate']),
                '${i['reminderStatus'] ?? 'Not sent'}',
              ],
          ],
        ),
      pw.SizedBox(height: 10),
      pw.Text(
          'Days Overdue counts from the oldest unpaid invoice. '
          'Reminder shows whether a rent reminder has been sent to the tenant.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
    ],
  );
}
