import 'dart:typed_data';

import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Shared page furniture and formatting for every downloadable report, so the
/// four PDFs read as one family.
///
/// **All text here must be ASCII.** The built-in Helvetica is a Type1 font with
/// no Unicode support, so an em dash, a middle dot or `₹` silently fails to
/// render — hence `Rs.` and `|` separators throughout. Bundling a Unicode TTF
/// is the fix if non-Latin tenant names ever need to print.

const pdfBrand = PdfColor.fromInt(0xFF4F2DE4);

/// Builds a report document with the standard title block, summary strip,
/// header/footer and body. [pageFormat] is landscape for wide tables.
Future<Uint8List> buildReportDocument({
  required String title,
  required String scopeLine,
  required List<List<String>> summary,
  required List<pw.Widget> Function(pw.Context context) body,
  PdfPageFormat? pageFormat,
}) async {
  final doc = pw.Document(title: title);
  doc.addPage(
    pw.MultiPage(
      pageFormat: pageFormat ?? PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 28),
      header: (context) => context.pageNumber == 1
          ? pw.SizedBox()
          : pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text('$title - $scopeLine',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
            ),
      footer: (context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
              'Generated ${DateFormat('d MMM yyyy, h:mm a').format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        ],
      ),
      build: (context) => [
        pdfTitleBlock(title, scopeLine),
        pw.SizedBox(height: 12),
        if (summary.isNotEmpty) ...[
          pdfSummaryStrip(summary),
          pw.SizedBox(height: 14),
        ],
        ...body(context),
      ],
    ),
  );
  return doc.save();
}

pw.Widget pdfTitleBlock(String title, String scopeLine) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title,
            style: const pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold)),
        if (scopeLine.isNotEmpty) ...[
          pw.SizedBox(height: 3),
          pw.Text(scopeLine,
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        ],
      ],
    );

/// Grey band of `[label, value]` pairs directly under the title.
pw.Widget pdfSummaryStrip(List<List<String>> cells) => pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          for (final c in cells)
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(c[0],
                    style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
                pw.SizedBox(height: 2),
                pw.Text(c[1],
                    style: const pw.TextStyle(
                        fontSize: 11, fontWeight: pw.FontWeight.bold)),
              ],
            ),
        ],
      ),
    );

/// Branded data table. [rightAlign] holds the column indexes that carry money.
pw.Widget pdfTable({
  required List<String> headers,
  required List<List<String>> rows,
  Map<int, pw.TableColumnWidth>? columnWidths,
  Set<int> rightAlign = const {},
  double fontSize = 8,
}) =>
    pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      columnWidths: columnWidths,
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.4),
      headerStyle: pw.TextStyle(
          fontSize: fontSize - 0.5,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: pdfBrand),
      cellStyle: pw.TextStyle(fontSize: fontSize),
      cellHeight: 16,
      headerAlignment: pw.Alignment.centerLeft,
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: {
        for (final c in rightAlign) c: pw.Alignment.centerRight,
      },
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
    );

pw.Widget pdfEmptyState(String message) => pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 28),
      alignment: pw.Alignment.center,
      child: pw.Text(message,
          style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey600)),
    );

pw.Widget pdfSectionTitle(String text) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Text(text,
          style: const pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
    );

// ─────────────────────────────────────────────────────────────── formatting ──

/// `Rs. 12,500.00` — see the ASCII note at the top of this file.
String pdfMoney(dynamic v) {
  final n = pdfNum(v);
  if (n == null) return '-';
  return 'Rs. ${NumberFormat('#,##0.00', 'en_IN').format(n)}';
}

String pdfPlain(dynamic v, {String pattern = '#,##0'}) {
  final n = pdfNum(v);
  return n == null ? '0' : NumberFormat(pattern).format(n);
}

num? pdfNum(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  return num.tryParse(v.toString());
}

String pdfDate(dynamic iso, {String pattern = 'd MMM yyyy'}) {
  if (iso == null) return '-';
  final d = DateTime.tryParse(iso.toString());
  return d == null ? '$iso' : DateFormat(pattern).format(d);
}

/// '2026-07' or '2026-07-01' -> 'July 2026'.
String pdfMonthLabel(String raw) {
  if (raw.isEmpty) return '';
  final d = DateTime.tryParse(raw.length == 7 ? '$raw-01' : raw);
  return d == null ? raw : DateFormat('MMMM yyyy').format(d);
}

/// 'Sunrise PG  |  July 2026', dropping whichever half is missing.
String pdfScopeLine(String? scope, String detail) {
  final s = (scope ?? '').trim();
  if (s.isEmpty) return detail;
  if (detail.isEmpty) return s;
  return '$s  |  $detail';
}
