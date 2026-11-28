import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'household_dates.g.dart';

/// Time of the device, from which A8 takes today: local dates, as the user
/// sees them. Tests override it with a fixed day.
@Riverpod(keepAlive: true)
DateTime Function() wallClock(Ref ref) => DateTime.now;

/// The day of [time], at midnight, in its own time zone.
DateTime dateOnly(DateTime time) => DateTime(time.year, time.month, time.day);

/// Whether [a] and [b] are the same day.
bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Start date A8 proposes on [today]: the first day of its month.
DateTime defaultStartDate(DateTime today) => DateTime(today.year, today.month);

/// Earliest start date on [today]: 90 days before.
DateTime firstStartDate(DateTime today) =>
    DateTime(today.year, today.month, today.day - 90);

/// Latest start date on [today]: 12 months after, on the same day of the
/// month, or on the last day of a shorter month, as Postgres adds months.
DateTime lastStartDate(DateTime today) {
  final year = today.year + 1;
  final lastDay = DateTime(year, today.month + 1, 0).day;
  return DateTime(year, today.month, today.day > lastDay ? lastDay : today.day);
}

/// [date] limited to the range of the start dates on [today].
DateTime clampStartDate(DateTime date, DateTime today) {
  final first = firstStartDate(today);
  final last = lastStartDate(today);
  if (date.isBefore(first)) return first;
  if (date.isAfter(last)) return last;
  return date;
}

/// Names of the months, in Italian.
const _months = [
  'gennaio',
  'febbraio',
  'marzo',
  'aprile',
  'maggio',
  'giugno',
  'luglio',
  'agosto',
  'settembre',
  'ottobre',
  'novembre',
  'dicembre',
];

/// [date] as Italian writes it: "1° marzo 2031", with the ordinal sign on
/// the first day of the month only; "15 marzo 2031".
String formatItalianDate(DateTime date) {
  final day = date.day == 1 ? '1°' : '${date.day}';
  return '$day ${_months[date.month - 1]} ${date.year}';
}

/// [date] as Italian writes it within the year of [today]: "24 novembre",
/// "1° dicembre"; with the year when it is another one, "3 gennaio 2032".
String formatItalianDayInYear(DateTime date, DateTime today) {
  final day = date.day == 1 ? '1°' : '${date.day}';
  final text = '$day ${_months[date.month - 1]}';
  return date.year == today.year ? text : '$text ${date.year}';
}

/// The text of the start date in A8: the date, followed by "· oggi" when it
/// is [today].
String formatStartDate(DateTime date, DateTime today) {
  final text = formatItalianDate(date);
  return isSameDay(date, today) ? '$text · oggi' : text;
}

/// [date] as Postgres reads a `date`: `yyyy-mm-dd`.
String isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
