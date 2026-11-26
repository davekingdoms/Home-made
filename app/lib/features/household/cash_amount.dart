import 'package:flutter/services.dart';

/// Largest amount of cash A8 accepts, in cents: 999.999,99 €.
const maxCashCents = 99999999;

/// The amount the user writes: up to six digits of euros, then a comma and
/// up to two digits of cents.
final _amount = RegExp(r'^\d{0,6}(,\d{0,2})?$');

/// The field of the cash in A8 (`docs/spec/accesso.md`, section 6): only
/// digits and one decimal separator, the comma; the point becomes a comma.
/// At most two decimals, no sign, at most 999.999,99. Any other edit is
/// refused and the text stays as it was.
class CashAmountFormatter extends TextInputFormatter {
  const new();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll('.', ',');
    if (!_amount.hasMatch(text)) return oldValue;
    return newValue.copyWith(text: text);
  }
}

/// The cents of [text], as [CashAmountFormatter] lets it be written: "12,5"
/// is 1250, ",5" is 50, "12," is 1200. Null without a digit: no balance.
int? parseCashCents(String text) {
  final normalized = text.replaceAll('.', ',');
  if (!_amount.hasMatch(normalized)) return null;
  final [euros, ...rest] = normalized.split(',');
  final cents = rest.isEmpty ? '' : rest.single;
  if (euros.isEmpty && cents.isEmpty) return null;
  return int.parse(euros.isEmpty ? '0' : euros) * 100 +
      int.parse(cents.padRight(2, '0'));
}
