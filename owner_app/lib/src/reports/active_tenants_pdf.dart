import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'report_pdf_common.dart';

/// Active Tenants Report — the platform's own monthly billing basis, one row per
/// organization, from `GET /super-admin/reports/active-tenants`.
///
/// A tenant counts for the month if their tenancy **overlapped** it, not just if
/// they are active today: someone who moved out on the 20th still consumed the
/// service that month. That also means a report for a past month keeps returning
/// the same figures as tenants come and go, which is what makes it invoiceable.
///
/// A pure function of the payload — no plugin, no `BuildContext` — so it renders
/// headlessly in tests.
Future<Uint8List> buildActiveTenantsPdf(Map<String, dynamic> report) {
  final items = [
    for (final e in (report['items'] as List? ?? const []))
      Map<String, dynamic>.from(e as Map),
  ];
  final s = Map<String, dynamic>.from((report['summary'] as Map?) ?? const {});
  final monthLabel = pdfMonthLabel('${report['month'] ?? ''}');

  // Portrait: six narrow columns fit comfortably, and an admin billing sheet is
  // more likely to be printed or emailed than the wide owner-side tables.
  return buildReportDocument(
    title: 'Active Tenants Report',
    scopeLine: pdfScopeLine('All Organizations', monthLabel),
    pageFormat: PdfPageFormat.a4,
    summary: [
      ['Organizations', pdfPlain(s['organizationCount'])],
      ['Active tenants', pdfPlain(s['totalActiveTenants'])],
      ['Properties', pdfPlain(s['totalProperties'])],
      ['Total amount', pdfMoney(s['totalAmount'])],
    ],
    body: (context) => [
      if (items.isEmpty)
        pdfEmptyState('No organizations found for $monthLabel.')
      else ...[
        pdfTable(
          fontSize: 8.5,
          headers: const [
            'Organization',
            'Properties',
            'Active Tenants',
            'Rate / Tenant',
            'Amount',
          ],
          columnWidths: const {
            0: pw.FlexColumnWidth(3.6),
            1: pw.FlexColumnWidth(1.3),
            2: pw.FlexColumnWidth(1.6),
            3: pw.FlexColumnWidth(1.7),
            4: pw.FlexColumnWidth(1.8),
          },
          rightAlign: const {1, 2, 3, 4},
          rows: [
            for (final i in items)
              [
                '${i['organizationName'] ?? 'Org #${i['organizationId'] ?? ''}'}'
                    // Flag negotiated rates so a total that does not match
                    // "tenants x default" is self-explanatory on the page.
                    '${i['customRate'] == true ? ' *' : ''}',
                pdfPlain(i['propertyCount']),
                pdfPlain(i['activeTenants']),
                pdfMoney(i['pricePerTenant']),
                pdfMoney(i['amount']),
              ],
            // Totals as a table row rather than a separate widget, so the figures
            // stay column-aligned with the data above them.
            [
              'TOTAL',
              pdfPlain(s['totalProperties']),
              pdfPlain(s['totalActiveTenants']),
              '',
              pdfMoney(s['totalAmount']),
            ],
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          'Billed at Rs. ${pdfPlain(s['defaultPricePerTenant'], pattern: '#,##0.00')}'
          ' per active tenant per month unless marked *.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          'A tenant is counted when their tenancy overlapped $monthLabel.'
          ' Deleted (archived) tenants are excluded.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ],
    ],
  );
}
