// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// When something happened in story time, in the one register the state
// zone uses for it (story-calendar §4): "Day 5, Tuesday night — 9 days
// ago". The Journal, the recap, promises and RAG lines all stamp with
// these, so a two-week skip ages every channel the same way.

import 'package:front_porch_ai/services/chat/story_clock.dart';

/// "earlier today" / "yesterday" / "9 days ago" / "2 weeks ago", for a
/// story day [delta] days before today.
String storyDaysAgo(int delta) => switch (delta) {
  <= 0 => 'earlier today',
  1 => 'yesterday',
  < 14 => '$delta days ago',
  _ => '${(delta / 7).round()} weeks ago',
};

/// "Day 5, Tuesday night" for story [day] of a story that began on
/// [startDate]; the period only when [clock] is known.
String storyDayLabel(int day, DateTime startDate, {DateTime? clock}) {
  final date = StoryClock.dateOnly(startDate).add(Duration(days: day - 1));
  final period = clock == null
      ? ''
      : ' ${StoryClock.periodForHour(clock.hour).replaceAll('_', ' ')}';
  return 'Day $day, ${StoryClock.weekdayName(date)}$period';
}
