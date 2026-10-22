/// Calendar arithmetic must use date components, not 24-hour local durations.
class Calendar {
  Calendar._();

  static DateTime day(DateTime time) =>
      DateTime(time.year, time.month, time.day);
  static DateTime addDays(DateTime time, int days) =>
      DateTime(time.year, time.month, time.day + days);
  static DateTime monday(DateTime time) => addDays(time, 1 - time.weekday);
  static int daysBetween(DateTime a, DateTime b) => DateTime.utc(
    a.year,
    a.month,
    a.day,
  ).difference(DateTime.utc(b.year, b.month, b.day)).inDays;
}
