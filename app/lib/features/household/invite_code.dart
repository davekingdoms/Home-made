import 'package:flutter/services.dart';

/// Characters of the codes `create_invite` makes: digits and capitals
/// without the ambiguous `0 O 1 I L` (`docs/spec/schema.md`, section 3).
const inviteCodeAlphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';

/// Length of a code, without the space between its two groups.
const inviteCodeLength = 8;

/// Length of a group of the code as it is shown: "K7QM X2PA".
const _groupLength = 4;

final _notLetterOrDigit = RegExp('[^A-Z0-9]');

/// [text] as the server reads a code: letters and digits only, in
/// capitals. "k7qm-x2pa" and "K7QM X2PA" are both "K7QMX2PA".
String normalizeInviteCode(String text) =>
    text.toUpperCase().replaceAll(_notLetterOrDigit, '');

/// Whether [code] is a code of the alphabet of `create_invite`, without
/// the space and in capitals.
bool isInviteCode(String code) =>
    code.length == inviteCodeLength &&
    code.split('').every(inviteCodeAlphabet.contains);

/// [code] in two groups of 4, as A9 and A10 show it: "K7QM X2PA". A
/// shorter code, while it is being written, gets the space once it has
/// more than 4 characters.
String formatInviteCode(String code) => code.length <= _groupLength
    ? code
    : '${code.substring(0, _groupLength)} ${code.substring(_groupLength)}';

/// [code] as the screen reader says it: one character at a time, the
/// groups apart. "K7QMX2PA" is "K 7 Q M, X 2 P A".
String spokenInviteCode(String code) {
  final normalized = normalizeInviteCode(code);
  final groups = [
    normalized.substring(0, normalized.length.clamp(0, _groupLength)),
    if (normalized.length > _groupLength) normalized.substring(_groupLength),
  ];
  return groups.map((group) => group.split('').join(' ')).join(', ');
}

/// The field of the code in A10 (`docs/spec/accesso.md`, section 8): only
/// letters and digits, small letters made capitals, at most 8, shown in two
/// groups of 4 with the space put in by itself. Pasting "k7qm-x2pa" or
/// "K7QM X2PA" gives "K7QM X2PA".
class InviteCodeFormatter extends TextInputFormatter {
  const new();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final code = normalizeInviteCode(newValue.text);
    final kept = code.length > inviteCodeLength
        ? code.substring(0, inviteCodeLength)
        : code;
    final text = formatInviteCode(kept);
    // The caret stays after the same character of the code it followed.
    final end = newValue.selection.isValid
        ? newValue.selection.end.clamp(0, newValue.text.length)
        : newValue.text.length;
    final before = normalizeInviteCode(newValue.text.substring(0, end)).length
        .clamp(0, kept.length);
    final offset = before > _groupLength ? before + 1 : before;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}
