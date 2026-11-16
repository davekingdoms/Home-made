import 'package:flutter_test/flutter_test.dart';
import 'package:homemade/core/money/money.dart';

/// [amount] in euro as [Money.format] writes it: a no-break space before the
/// symbol.
String euro(String amount) => '$amount €';

/// Typographic minus, U+2212.
const minus = '−';

void main() {
  group('format', () {
    test('zero', () {
      expect(const Money(0).format(), euro('0,00'));
    });

    test('cents', () {
      expect(const Money(5).format(), euro('0,05'));
      expect(const Money(50).format(), euro('0,50'));
      expect(const Money(99).format(), euro('0,99'));
      expect(const Money(1250).format(), euro('12,50'));
      expect(const Money(99999).format(), euro('999,99'));
    });

    test('thousands', () {
      expect(const Money(100000).format(), euro('1.000,00'));
      expect(const Money(123456).format(), euro('1.234,56'));
      expect(const Money(1234567).format(), euro('12.345,67'));
      expect(const Money(99999999).format(), euro('999.999,99'));
    });

    test('millions', () {
      expect(const Money(100000000).format(), euro('1.000.000,00'));
      expect(const Money(123456789).format(), euro('1.234.567,89'));
      expect(const Money(123456789012).format(), euro('1.234.567.890,12'));
    });

    test('negative amounts take the typographic minus', () {
      expect(const Money(-5).format(), euro('${minus}0,05'));
      expect(const Money(-1250).format(), euro('${minus}12,50'));
      expect(const Money(-123456).format(), euro('${minus}1.234,56'));
      expect(const Money(-100000000).format(), euro('${minus}1.000.000,00'));
      // Not the hyphen of the keyboard.
      expect(const Money(-1250).format(), isNot(contains('-')));
    });

    test('explicit sign, for credits and debts', () {
      const always = MoneySign.always;
      expect(const Money(1250).format(sign: always), euro('+12,50'));
      expect(const Money(123456).format(sign: always), euro('+1.234,56'));
      expect(const Money(-1250).format(sign: always), euro('${minus}12,50'));
      // Zero is neither a credit nor a debt.
      expect(const Money(0).format(sign: always), euro('0,00'));
    });

    test('the symbol follows the amount after a no-break space', () {
      expect(const Money(1250).format(), '12,50${Money.symbolSeparator}€');
      expect(Money.symbolSeparator, ' ');
      expect(Money.minus, minus);
    });

    test('a currency without a symbol shows its ISO 4217 code', () {
      const francs = Money(1250, currency: 'CHF');
      expect(francs.symbol, 'CHF');
      expect(francs.format(), '12,50 CHF');
    });
  });

  group('value', () {
    test('is euro by default', () {
      expect(const Money(1).currency, 'EUR');
      expect(const Money(1).symbol, '€');
    });

    test('compares by cents and currency', () {
      expect(const Money(1250), const Money(1250));
      expect(const Money(1250).hashCode, const Money(1250).hashCode);
      expect(const Money(1250), isNot(const Money(1251)));
      expect(const Money(1250), isNot(const Money(1250, currency: 'CHF')));
      expect(const Money(1).compareTo(const Money(2)), isNegative);
      expect(const Money(0).isZero, isTrue);
      expect(const Money(-1).isNegative, isTrue);
      expect(const Money(1).isNegative, isFalse);
    });

    test('adds and subtracts whole cents', () {
      expect(const Money(10) + const Money(20), const Money(30));
      expect(const Money(10) - const Money(20), const Money(-10));
      expect(-const Money(10), const Money(-10));
      expect(const Money(-10).abs(), const Money(10));
      // 0,10 + 0,20 is exactly 0,30: no floating point.
      expect((const Money(10) + const Money(20)).format(), euro('0,30'));
    });

    test('does not mix currencies', () {
      const euros = Money(10);
      const francs = Money(10, currency: 'CHF');
      expect(() => euros + francs, throwsArgumentError);
      expect(() => euros - francs, throwsArgumentError);
      expect(() => euros.compareTo(francs), throwsArgumentError);
    });
  });
}
