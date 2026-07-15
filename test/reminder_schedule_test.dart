import 'package:break_reminder_app/core/schedule/reminder_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('occurrences are one interval apart starting after the anchor', () {
    const schedule = ReminderSchedule(intervalMinutes: 60);
    final anchor = DateTime(2026, 7, 13, 9, 0);
    final occurrences = schedule.nextOccurrences(anchor, count: 3);
    expect(occurrences, [
      DateTime(2026, 7, 13, 10, 0),
      DateTime(2026, 7, 13, 11, 0),
      DateTime(2026, 7, 13, 12, 0),
    ]);
  });

  test('occurrences cross midnight without gaps', () {
    const schedule = ReminderSchedule(intervalMinutes: 90);
    final anchor = DateTime(2026, 7, 13, 23, 0);
    final occurrences = schedule.nextOccurrences(anchor, count: 2);
    expect(occurrences, [
      DateTime(2026, 7, 14, 0, 30),
      DateTime(2026, 7, 14, 2, 0),
    ]);
  });

  test('requested count is honored and strictly increasing', () {
    const schedule = ReminderSchedule(intervalMinutes: 5);
    final occurrences =
        schedule.nextOccurrences(DateTime(2026, 7, 13), count: 24);
    expect(occurrences.length, 24);
    for (var i = 1; i < occurrences.length; i++) {
      expect(occurrences[i].isAfter(occurrences[i - 1]), isTrue);
    }
  });

  test('a non-positive interval yields no occurrences', () {
    const zero = ReminderSchedule(intervalMinutes: 0);
    const negative = ReminderSchedule(intervalMinutes: -15);
    expect(zero.nextOccurrences(DateTime(2026, 7, 13)), isEmpty);
    expect(negative.nextOccurrences(DateTime(2026, 7, 13)), isEmpty);
    expect(zero.isSchedulable, isFalse);
  });
}
