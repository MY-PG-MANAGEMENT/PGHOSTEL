import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import 'report_pdf_common.dart';

/// Rent Collection — one row per invoice raised in the month, from
/// `GET /reports/rent-collection`.
///
/// Pure function of the payload (no plugins, no BuildContext), so it renders in
/// a headless test. Landscape A4: fourteen columns do not fit portrait.
Future<Uint8List> buildRentCollectionPdf(Map<String, dynamic> report) {
  final items = [
    for (final e in (report['items'] as List? ?? const []))
      Map<String, dynamic>.from(e as Map),
  ];
  final s = Map<String, dynamic>.from((report['summary'] as Map?) ?? const {});
  final monthLabel = pdfMonthLabel('${report['month'] ?? ''}');
  final scope = '${report['propertyName'] ?? report['organizationName'] ?? ''}';

  return buildReportDocument(
    title: 'Rent Collection Report',
    scopeLine: pdfScopeLine(scope, monthLabel),
    summary: [
      ['Invoices', '${s['invoiceCount'] ?? 0}'],
      ['Billed', pdfMoney(s['totalAmount'])],
      ['Collected', pdfMoney(s['paidAmount'])],
      ['Outstanding', pdfMoney(s['dueAmount'])],
      ['Collection', '${pdfPlain(s['collectionPct'])}%'],
      [
        'Paid / Partial / Pending',
        '${s['paidCount'] ?? 0} / ${s['partialCount'] ?? 0} / ${s['pendingCount'] ?? 0}'
      ],
    ],
    body: (context) => [
      if (items.isEmpty)
        pdfEmptyState('No invoices raised for $monthLabel.')
      else
        pdfTable(
          fontSize: 7.5,
          headers: const [
            'Invoice No', 'Tenant', 'Property', 'Room/Bed', 'Rent Month',
            'Rent', 'Discount', 'Add. Chg', 'Total', 'Paid', 'Due',
            'Paid On', 'Mode', 'Status',
          ],
          // Text columns get the room; money columns stay narrow so all
          // fourteen fit one landscape page.
          columnWidths: const {
            0: pw.FlexColumnWidth(2.6),
            1: pw.FlexColumnWidth(2.6),
            2: pw.FlexColumnWidth(2.0),
            3: pw.FlexColumnWidth(1.9),
            4: pw.FlexColumnWidth(1.5),
            5: pw.FlexColumnWidth(1.4),
            6: pw.FlexColumnWidth(1.3),
            7: pw.FlexColumnWidth(1.4),
            8: pw.FlexColumnWidth(1.5),
            9: pw.FlexColumnWidth(1.5),
            10: pw.FlexColumnWidth(1.4),
            11: pw.FlexColumnWidth(1.6),
            12: pw.FlexColumnWidth(1.4),
            13: pw.FlexColumnWidth(1.4),
          },
          rightAlign: const {5, 6, 7, 8, 9, 10},
          rows: [
            for (final i in items)
              [
                '${i['invoiceNo'] ?? ''}',
                '${i['tenantName'] ?? ''}',
                '${i['property'] ?? ''}',
                '${i['roomBed'] ?? ''}',
                pdfMonthLabel('${i['rentMonth'] ?? ''}'),
                pdfMoney(i['rentAmount']),
                pdfMoney(i['discount']),
                pdfMoney(i['additionalCharges']),
                pdfMoney(i['totalAmount']),
                pdfMoney(i['paidAmount']),
                pdfMoney(i['dueAmount']),
                pdfDate(i['paymentDate']),
                '${i['paymentMode'] ?? '-'}',
                '${i['status'] ?? ''}',
              ],
          ],
        ),
    ],
  );
}
