import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:pg_manager_owner_app/src/reports/expense_report_pdf.dart';
import 'package:pg_manager_owner_app/src/reports/outstanding_dues_pdf.dart';
import 'package:pg_manager_owner_app/src/reports/profit_loss_pdf.dart';
import 'package:pg_manager_owner_app/src/reports/rent_collection_pdf.dart';

/// The PDF builder is a pure function of the `/reports/rent-collection` payload,
/// so it can be rendered here without the `printing` plugin or a platform channel.
void main() {
  Map<String, dynamic> report({List<Map<String, dynamic>>? items}) => {
        'month': '2026-07',
        'propertyName': 'Sunrise PG',
        'organizationName': 'Sunrise Group',
        'summary': {
          'invoiceCount': items?.length ?? 0,
          'totalAmount': 24000,
          'paidAmount': 18000,
          'dueAmount': 6000,
          'paidCount': 2,
          'partialCount': 1,
          'pendingCount': 0,
          'collectionPct': 75,
        },
        'items': items ?? const [],
      };

  Map<String, dynamic> row({
    String invoiceNo = 'INV-1-1-202607',
    String tenant = 'Asha Rao',
    dynamic paymentDate = '2026-07-05',
    dynamic paymentMode = 'UPI',
    String status = 'Paid',
  }) =>
      {
        'invoiceId': 1,
        'invoiceNo': invoiceNo,
        'tenantName': tenant,
        'property': 'Sunrise PG',
        'roomBed': 'Room 101 / BED1',
        'rentMonth': '2026-07-01',
        'rentAmount': 7000,
        'discount': 0,
        'additionalCharges': 1000,
        'totalAmount': 8000,
        'paidAmount': 8000,
        'dueAmount': 0,
        'paymentDate': paymentDate,
        'paymentMode': paymentMode,
        'status': status,
      };

  test('renders a valid PDF for a populated month', () async {
    final bytes = await buildRentCollectionPdf(report(items: [
      row(),
      row(
          invoiceNo: 'INV-1-2-202607',
          tenant: 'Vikram Singh',
          status: 'Partial'),
      row(
          invoiceNo: 'INV-1-3-202607',
          tenant: 'Neha Kapoor',
          paymentDate: null,
          paymentMode: null,
          status: 'Pending'),
    ]));

    expect(bytes.lengthInBytes, greaterThan(1000));
    expect(utf8.decode(bytes.sublist(0, 5)), '%PDF-');
  });

  test('renders an empty-month PDF instead of failing', () async {
    final bytes = await buildRentCollectionPdf(report());

    expect(utf8.decode(bytes.sublist(0, 5)), '%PDF-');
    expect(bytes.lengthInBytes, greaterThan(500));
  });

  test('survives a payload with missing fields and string numbers', () async {
    // The dashboard can hand back nulls (no payment yet) and JSON numbers can
    // arrive as strings from the decimal columns — neither may throw.
    final bytes = await buildRentCollectionPdf({
      'month': '2026-07',
      'items': [
        {
          'invoiceNo': 'INV-X',
          'tenantName': 'No Bed Tenant',
          'totalAmount': '5000.00',
          'paidAmount': '0.00',
          'dueAmount': '5000.00',
          'status': 'Pending',
        },
      ],
    });

    expect(utf8.decode(bytes.sublist(0, 5)), '%PDF-');
  });

  group('Outstanding Due', () {
    Map<String, dynamic> dues({List<Map<String, dynamic>>? items}) => {
          'month': '2026-07',
          'propertyName': 'Sunrise PG',
          'summary': {
            'tenantCount': items?.length ?? 0,
            'totalDue': 12500,
            'overdueCount': 1,
            'asOf': '2026-07-26',
          },
          'items': items ?? const [],
        };

    test('renders tenants with dues', () async {
      final bytes = await buildOutstandingDuesPdf(dues(items: [
        {
          'tenantName': 'Asha Rao',
          'phone': '9876543210',
          'property': 'Sunrise PG',
          'roomBed': 'Room 101 / BED1',
          'dueAmount': 8000,
          'dueSince': '2026-06-05',
          'daysOverdue': 51,
          'lastPaymentDate': '2026-05-04',
          'nextDueDate': '2026-08-05',
          'reminderStatus': 'Sent',
        },
        {
          'tenantName': 'Never Paid',
          'phone': '',
          'property': 'Sunrise PG',
          'roomBed': '',
          'dueAmount': 4500,
          'dueSince': '2026-07-10',
          'daysOverdue': 0,
          'lastPaymentDate': null,
          'nextDueDate': null,
          'reminderStatus': 'Not sent',
        },
      ]));

      expect(utf8.decode(bytes.sublist(0, 5)), '%PDF-');
      expect(bytes.lengthInBytes, greaterThan(1000));
    });

    test('renders an all-settled month', () async {
      final bytes = await buildOutstandingDuesPdf(dues());
      expect(utf8.decode(bytes.sublist(0, 5)), '%PDF-');
    });
  });

  group('Expense Report', () {
    test('renders entries plus the category summary', () async {
      final bytes = await buildExpenseReportPdf({
        'month': '2026-07',
        'category': 'ALL',
        'propertyName': 'Sunrise PG',
        'summary': {'expenseCount': 2, 'totalAmount': 5200},
        'categories': [
          {'category': 'ELECTRICITY', 'total': 4000},
          {'category': 'WATER', 'total': 1200},
        ],
        'items': [
          {
            'expenseDate': '2026-07-04',
            'category': 'ELECTRICITY',
            'vendor': 'TSSPDCL',
            'description': 'June power bill',
            'property': 'Sunrise PG',
            'amount': 4000,
            'paymentMethod': 'BANK_TRANSFER',
            'paidBy': 'Ramesh',
          },
          {
            'expenseDate': '2026-07-11',
            'category': 'WATER',
            'vendor': '',
            'description': 'Tanker',
            'property': 'Sunrise PG',
            'amount': 1200,
            'paymentMethod': 'CASH',
            'paidBy': '',
          },
        ],
      });

      expect(utf8.decode(bytes.sublist(0, 5)), '%PDF-');
    });

    test('renders an empty month', () async {
      final bytes = await buildExpenseReportPdf({
        'month': '2026-07',
        'category': 'GAS',
        'summary': {'expenseCount': 0, 'totalAmount': 0},
        'categories': const [],
        'items': const [],
      });
      expect(utf8.decode(bytes.sublist(0, 5)), '%PDF-');
    });
  });

  group('Profit & Loss', () {
    test('renders the statement with month and category breakdowns', () async {
      final bytes = await buildProfitLossPdf({
        'fromDate': '2026-05-01',
        'toDate': '2026-07-31',
        'propertyName': 'Sunrise PG',
        'summary': {
          'totalRent': 180000,
          'otherIncome': 12000,
          'totalIncome': 192000,
          'totalExpenses': 74000,
          'netProfit': 118000,
          'profitMarginPct': 61.5,
        },
        'months': [
          {'month': '2026-05', 'income': 64000, 'expenses': 25000, 'net': 39000},
          {'month': '2026-06', 'income': 64000, 'expenses': 24000, 'net': 40000},
          {'month': '2026-07', 'income': 64000, 'expenses': 25000, 'net': 39000},
        ],
        'expenseByCategory': [
          {'category': 'SALARY', 'total': 45000},
          {'category': 'FOOD', 'total': 29000},
        ],
      });

      expect(utf8.decode(bytes.sublist(0, 5)), '%PDF-');
    });

    test('renders a loss-making period without a breakdown', () async {
      final bytes = await buildProfitLossPdf({
        'fromDate': '2026-07-01',
        'toDate': '2026-07-31',
        'summary': {
          'totalRent': 0,
          'otherIncome': 0,
          'totalIncome': 0,
          'totalExpenses': 8000,
          'netProfit': -8000,
          'profitMarginPct': 0,
        },
        'months': const [],
        'expenseByCategory': const [],
      });

      expect(utf8.decode(bytes.sublist(0, 5)), '%PDF-');
    });
  });
}
