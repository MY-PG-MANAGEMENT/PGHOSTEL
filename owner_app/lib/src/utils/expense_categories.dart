import 'package:flutter/material.dart';

/// Display metadata for an expense category.
class ExpenseCategoryMeta {
  final String label;
  final Color color;
  final IconData icon;
  const ExpenseCategoryMeta(this.label, this.color, this.icon);
}

/// The expense category master, mirroring `ExpenseController.CATEGORIES` on the
/// backend. Shared by the expenses screen (entry + filter chips) and the reports
/// screen (report filter), so the two can never drift.
///
/// Categories are only ever **added** — an existing expense row must keep
/// resolving, and `DEPOSIT_REFUND` is written by the tenant-checkout refund flow
/// rather than chosen by hand.
const Map<String, ExpenseCategoryMeta> expenseCategoryMeta = {
  'ELECTRICITY': ExpenseCategoryMeta('Electricity', Color(0xFFE05C4B), Icons.bolt_rounded),
  'WATER': ExpenseCategoryMeta('Water', Color(0xFF0EA5E9), Icons.water_drop_rounded),
  'SALARY': ExpenseCategoryMeta('Salary', Color(0xFF16A085), Icons.payments_rounded),
  'FOOD': ExpenseCategoryMeta('Food & Groceries', Color(0xFFD9A514), Icons.restaurant_rounded),
  'CLEANING': ExpenseCategoryMeta('Cleaning', Color(0xFF14B8A6), Icons.cleaning_services_rounded),
  'REPAIRS': ExpenseCategoryMeta('Repairs', Color(0xFFB45309), Icons.handyman_rounded),
  'INTERNET': ExpenseCategoryMeta('Internet', Color(0xFF4F46E5), Icons.wifi_rounded),
  'GAS': ExpenseCategoryMeta('Gas', Color(0xFFEA580C), Icons.local_fire_department_rounded),
  'MAINTENANCE': ExpenseCategoryMeta('Maintenance', Color(0xFF9B59D0), Icons.build_rounded),
  'LAUNDRY': ExpenseCategoryMeta('Laundry', Color(0xFF0E9AAB), Icons.local_laundry_service_rounded),
  'TRANSPORT': ExpenseCategoryMeta('Transport', Color(0xFFE07B2A), Icons.local_shipping_rounded),
  'RENT': ExpenseCategoryMeta('Rent', Color(0xFFDB4A6B), Icons.home_rounded),
  'DEPOSIT_REFUND':
      ExpenseCategoryMeta('Deposit Refund', Color(0xFF3B7DD8), Icons.currency_exchange_rounded),
  'OTHERS': ExpenseCategoryMeta('Others', Color(0xFF6B7280), Icons.category_rounded),
};

const ExpenseCategoryMeta unknownExpenseCategory =
    ExpenseCategoryMeta('Others', Color(0xFF6B7280), Icons.category_rounded);

/// Never throws on an unknown code — a category retired from the picker must
/// still render for the rows already carrying it.
ExpenseCategoryMeta expenseCategory(String? code) =>
    expenseCategoryMeta[code] ?? unknownExpenseCategory;

/// Human label for a category code (`'FOOD'` → `'Food & Groceries'`).
String expenseCategoryLabel(String? code) => expenseCategory(code).label;
