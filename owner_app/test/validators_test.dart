import 'package:flutter_test/flutter_test.dart';
import 'package:pg_manager_owner_app/src/utils/validators.dart';

void main() {
  group('Validators.mobile', () {
    test('accepts a 10-digit number', () {
      expect(Validators.mobile('9876543210'), isNull);
    });
    test('rejects too few digits', () {
      expect(Validators.mobile('98765'), isNotNull);
    });
    test('rejects non-digits', () {
      expect(Validators.mobile('98765abcd0'), isNotNull);
    });
    test('rejects empty', () {
      expect(Validators.mobile(''), isNotNull);
      expect(Validators.mobile(null), isNotNull);
    });
  });

  group('Validators.optionalMobile', () {
    test('accepts empty (optional)', () {
      expect(Validators.optionalMobile(''), isNull);
      expect(Validators.optionalMobile(null), isNull);
    });
    test('validates when present', () {
      expect(Validators.optionalMobile('123'), isNotNull);
    });
  });

  group('Validators.username', () {
    test('accepts valid username', () {
      expect(Validators.username('owner_01'), isNull);
    });
    test('rejects too short', () {
      expect(Validators.username('ab'), isNotNull);
    });
    test('rejects illegal characters', () {
      expect(Validators.username('bad name!'), isNotNull);
    });
  });

  group('Validators.password / confirmPassword', () {
    test('accepts 8+ chars', () {
      expect(Validators.password('secret12'), isNull);
    });
    test('rejects short password', () {
      expect(Validators.password('short'), isNotNull);
    });
    test('confirm matches', () {
      expect(Validators.confirmPassword('secret12', 'secret12'), isNull);
    });
    test('confirm mismatch', () {
      expect(Validators.confirmPassword('secret12', 'other123'), isNotNull);
    });
  });

  group('Validators.email', () {
    test('accepts valid email', () {
      expect(Validators.optionalEmail('a@b.com'), isNull);
    });
    test('rejects invalid email', () {
      expect(Validators.optionalEmail('not-an-email'), isNotNull);
    });
    test('optional email accepts empty', () {
      expect(Validators.optionalEmail(''), isNull);
    });
  });

  group('Validators.aadhaar', () {
    test('accepts 12 digits', () {
      expect(Validators.aadhaar('123456789012'), isNull);
    });
    test('rejects wrong length', () {
      expect(Validators.aadhaar('1234'), isNotNull);
    });
    test('optional - accepts empty', () {
      expect(Validators.aadhaar(''), isNull);
    });
  });

  group('Validators.positiveAmount', () {
    test('accepts positive', () {
      expect(Validators.positiveAmount('100.50'), isNull);
    });
    test('rejects zero', () {
      expect(Validators.positiveAmount('0'), isNotNull);
    });
    test('rejects negative', () {
      expect(Validators.positiveAmount('-5'), isNotNull);
    });
    test('rejects non-numeric', () {
      expect(Validators.positiveAmount('abc'), isNotNull);
    });
  });

  group('Validators.nonNegativeAmount', () {
    test('accepts empty (optional)', () {
      expect(Validators.nonNegativeAmount(''), isNull);
    });
    test('accepts zero', () {
      expect(Validators.nonNegativeAmount('0'), isNull);
    });
    test('rejects negative', () {
      expect(Validators.nonNegativeAmount('-1'), isNotNull);
    });
  });

  group('Validators.positiveInt', () {
    test('accepts 1+', () {
      expect(Validators.positiveInt('3'), isNull);
    });
    test('rejects zero', () {
      expect(Validators.positiveInt('0'), isNotNull);
    });
    test('rejects decimals', () {
      expect(Validators.positiveInt('2.5'), isNotNull);
    });
  });
}
