// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Where in the day a skip of a day or more lands. "Two weeks later, one
// bright morning" typed at 10:47 PM used to land at 10:47 PM, so the
// line, the bridge and the clock disagreed. The first time-of-day word
// in the skip line wins; with none the skip lands in the morning.

const _times = <(String, int, int)>[
  (r'dawn|daybreak|sunrise|first light', 6, 0),
  (r'late morning', 11, 30),
  (r'mornings?|breakfast', 9, 0),
  (r'noon|midday|lunchtime|lunch time', 12, 0),
  (r'afternoons?', 14, 30),
  (r'evenings?|dusk|sunset|twilight|supper|dinnertime', 18, 30),
  (r'nights?|nighttime|midnight|tonight', 22, 30),
];

final _patterns = [
  for (final (src, h, m) in _times) (RegExp('\\b(?:$src)\\b'), h, m),
];

/// Neutral landing when the line names no time of day: the representative
/// morning the "next month" rule and fresh chats already use.
const int kSkipLandingHour = 9;

/// [date]'s calendar day at the time of day [lower] names, else morning.
DateTime landSkipInDay(DateTime date, String lower) {
  (int, int)? best;
  var at = -1;
  for (final (re, h, m) in _patterns) {
    final match = re.firstMatch(lower);
    if (match == null) continue;
    if (at < 0 || match.start < at) {
      at = match.start;
      best = (h, m);
    }
  }
  final (hour, minute) = best ?? (kSkipLandingHour, 0);
  return DateTime.utc(date.year, date.month, date.day, hour, minute);
}
