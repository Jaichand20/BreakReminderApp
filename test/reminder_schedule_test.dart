import 'package:flutter_test/flutter_test.dart';

import 'package:break_reminder_app/core/schedule/reminder_schedule.dart';

void main() {
  // Mon + Wed, 9:00-18:00, hourly — the example schedule from the spec.
  const monWed = ReminderSchedule(
    activeDays: {DateTime.monday, DateTime.wednesday},
    startMinutes: 9 * 60,
    endMinutes: 18 * 60,
    intervalMinutes: 60,
  );

  test('inside the window, occurrences are one interval apart', () {
    // Monday 2026-07-13 10:00.
    final anchor = DateTime(2026, 7, 13, 10, 0);
    final next = monWed.nextOccurrences(anchor, count: 3);
    expect(next, [
      DateTime(2026, 7, 13, 11, 0),
      DateTime(2026, 7, 13, 12, 0),
      DateTime(2026, 7, 13, 13, 0),
    ]);
  });

  test('past the window end rolls to the next active day at window start', () {
    // Monday 17:30 → 18:30 candidate is past 18:00 → Wednesday 9:00.
    final anchor = DateTime(2026, 7, 13, 17, 30);
    final next = monWed.nextOccurrences(anchor, count: 2);
    expect(next.first, DateTime(2026, 7, 15, 9, 0));
    expect(next[1], DateTime(2026, 7, 15, 10, 0));
  });

  test('anchor on an inactive day rolls to the next active day', () {
    // Friday → next occurrence is Monday 9:00.
    final anchor = DateTime(2026, 7, 17, 12, 0);
    final next = monWed.nextOccurrences(anchor, count: 1);
    expect(next.single, DateTime(2026, 7, 20, 9, 0));
  });

  test('before the window start on an active day snaps to window start', () {
    // Monday 7:15 → candidate 8:15 is before 9:00 → snaps to 9:00.
    final anchor = DateTime(2026, 7, 13, 7, 15);
    final next = monWed.nextOccurrences(anchor, count: 1);
    expect(next.single, DateTime(2026, 7, 13, 9, 0));
  });

  test('exact window edges are inclusive', () {
    // Candidate exactly at 18:00 fires; 18:01 would not.
    const schedule = ReminderSchedule(
      activeDays: {DateTime.monday},
      startMinutes: 9 * 60,
      endMinutes: 18 * 60,
      intervalMinutes: 60,
    );
    final next =
        schedule.nextOccurrences(DateTime(2026, 7, 13, 17, 0), count: 1);
    expect(next.single, DateTime(2026, 7, 13, 18, 0));
  });

  test('no active days means no occurrences', () {
    const schedule = ReminderSchedule(
      activeDays: {},
      startMinutes: 9 * 60,
      endMinutes: 18 * 60,
      intervalMinutes: 60,
    );
    expect(schedule.nextOccurrences(DateTime(2026, 7, 13)), isEmpty);
    expect(schedule.isSchedulable, isFalse);
  });

  test('inverted window means no occurrences', () {
    const schedule = ReminderSchedule(
      activeDays: {DateTime.monday},
      startMinutes: 18 * 60,
      endMinutes: 9 * 60,
      intervalMinutes: 60,
    );
    expect(schedule.nextOccurrences(DateTime(2026, 7, 13)), isEmpty);
  });

  test('occurrences are strictly increasing across day rollovers', () {
    final next = monWed.nextOccurrences(DateTime(2026, 7, 13, 8, 0), count: 24);
    for (var i = 1; i < next.length; i++) {
      expect(next[i].isAfter(next[i - 1]), isTrue,
          reason: '${next[i - 1]} → ${next[i]}');
    }
    // 9:00..18:00 hourly = 10 slots per active day; 24 occurrences span
    // Mon (10) + Wed (10) + following Mon (4).
    expect(next.where((t) => t.weekday == DateTime.monday).length, 14);
    expect(next.where((t) => t.weekday == DateTime.wednesday).length, 10);
  });
}
