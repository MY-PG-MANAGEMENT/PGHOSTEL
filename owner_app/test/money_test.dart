import 'package:flutter_test/flutter_test.dart';
import 'package:pg_manager_owner_app/src/utils/money.dart';

void main() {
  group('inr (Indian grouping)', () {
    test('groups thousands and lakhs', () {
      expect(inr(0), '₹0');
      expect(inr(100), '₹100');
      expect(inr(1000), '₹1,000');
      expect(inr(10000), '₹10,000');
      expect(inr(100000), '₹1,00,000');
      expect(inr(120500), '₹1,20,500');
      expect(inr(10450000), '₹1,04,50,000');
    });

    test('keeps paise only when present', () {
      expect(inr(8500), '₹8,500');
      expect(inr(8500.5), '₹8,500.50');
      expect(inr(8500.50), '₹8,500.50');
    });

    test('handles numeric strings and negatives', () {
      expect(inr('10000'), '₹10,000');
      expect(inr(-4000), '-₹4,000');
    });

    test('null shows the fallback', () {
      expect(inr(null), '—');
      expect(inr(null, nullText: '₹0'), '₹0');
    });
  });
}
