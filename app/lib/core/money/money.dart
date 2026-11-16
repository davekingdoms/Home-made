import 'package:flutter/foundation.dart';

/// When [Money.format] writes the sign.
enum MoneySign {
  /// Only the minus of negative amounts.
  negativeOnly,

  /// Minus or plus, for credits and debts; zero has no sign.
  always,
}

/// An amount of money: a whole number of [cents] and an ISO 4217 [currency]
/// code. No floating point anywhere, not even to format.
///
/// The minor unit is always a hundredth, as for the euro; currencies with a
/// different minor unit are not supported.
@immutable
class Money implements Comparable<Money> {
  const new(this.cents, {this.currency = euro})
    : assert(
        currency.length == 3,
        'An ISO 4217 code has three letters',
      );

  /// ISO 4217 code of the euro.
  static const euro = 'EUR';

  /// Typographic minus (U+2212), not the hyphen of the keyboard.
  static const minus = '−';

  /// No-break space (U+00A0) between the amount and the symbol, so that a
  /// line never ends between the two.
  static const symbolSeparator = ' ';

  static const _symbols = {euro: '€'};

  final int cents;

  /// ISO 4217 code, in capital letters.
  final String currency;

  bool get isZero => cents == 0;
  bool get isNegative => cents < 0;

  /// Symbol of the currency, or its code when it has none here.
  String get symbol => _symbols[currency] ?? currency;

  Money operator +(Money other) => Money(
    cents + _sameCurrency(other).cents,
    currency: currency,
  );

  Money operator -(Money other) => Money(
    cents - _sameCurrency(other).cents,
    currency: currency,
  );

  Money operator -() => Money(-cents, currency: currency);

  Money abs() => Money(cents.abs(), currency: currency);

  /// The amount in the Italian format: `.` between thousands, `,` before the
  /// cents, the symbol after the amount, a typographic minus.
  ///
  /// `1.234,56 €`, `−12,50 €`; with [MoneySign.always] also `+12,50 €`.
  String format({MoneySign sign = MoneySign.negativeOnly}) {
    final absolute = cents.abs();
    final units = (absolute ~/ 100).toString();
    final hundredths = (absolute % 100).toString().padLeft(2, '0');

    final grouped = StringBuffer();
    for (var i = 0; i < units.length; i++) {
      if (i > 0 && (units.length - i) % 3 == 0) grouped.write('.');
      grouped.write(units[i]);
    }

    final String prefix;
    if (isNegative) {
      prefix = minus;
    } else if (sign == MoneySign.always && !isZero) {
      prefix = '+';
    } else {
      prefix = '';
    }
    return '$prefix$grouped,$hundredths$symbolSeparator$symbol';
  }

  @override
  int compareTo(Money other) => cents.compareTo(_sameCurrency(other).cents);

  @override
  bool operator ==(Object other) =>
      other is Money && other.cents == cents && other.currency == currency;

  @override
  int get hashCode => Object.hash(cents, currency);

  @override
  String toString() => 'Money($cents, $currency)';

  Money _sameCurrency(Money other) {
    if (other.currency != currency) {
      throw ArgumentError.value(
        other.currency,
        'other',
        'Amounts in different currencies ($currency expected)',
      );
    }
    return other;
  }
}
