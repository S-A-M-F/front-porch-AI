// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Counted spans in skip narration: "6 hours", "two weeks", "a few days",
// "3 months", "a fortnight", "a week and a half", "fifteen years". [lower]
// is quote-stripped lowercase, as everywhere in the skip path.
//
// Before 2026-10-13 any "weeks later" counted as one week, and days only
// moved the clock with an OOC marker. Before 2026-10-20 "two weeks have
// passed", "a fortnight later", "days later", number words past twelve
// and the colon forms ("Time skip: two weeks") were missed, and a day-plus
// skip kept the hour it left (see skip_landing.dart).

import 'package:front_porch_ai/services/chat/skip_landing.dart';

/// The span a counted skip names, and where it lands.
class SkipSpan {
  SkipSpan._();

  static const _units = {
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
  };

  static const _teens = {
    'ten': 10,
    'eleven': 11,
    'twelve': 12,
    'thirteen': 13,
    'fourteen': 14,
    'fifteen': 15,
    'sixteen': 16,
    'seventeen': 17,
    'eighteen': 18,
    'nineteen': 19,
  };

  static const _tens = {
    'twenty': 20,
    'thirty': 30,
    'forty': 40,
    'fifty': 50,
    'sixty': 60,
    'seventy': 70,
    'eighty': 80,
    'ninety': 90,
  };

  /// Vague counts. "A few hours" keeps its own +2h bucket in StoryClock.
  static const _vague = {
    'a couple of': 2,
    'a couple': 2,
    'a few': 3,
    'several': 3,
  };

  /// "Days later", "many weeks later": no number, so a sensible one.
  static const _vagueByUnit = {'day': 3, 'week': 2, 'month': 3, 'year': 2};

  static final _vagueVerb = RegExp(r'\b(?:later|ha(?:ve|s) )');

  static final _word =
      '(?:${_tens.keys.join('|')})(?:[- ](?:${_units.keys.join('|')}))?'
      '|${_teens.keys.join('|')}|${_units.keys.join('|')}';

  static final _count =
      '(\\d+|a couple of|a couple|a few|several|many|some|$_word|an?)';

  static const _longUnit = r'(days?|weeks?|months?|years?|fortnights?)';
  static const _half = r'(\s+and\s+a\s+half)?';

  /// A long span said as narration: "two weeks later", "3 days pass",
  /// "a fortnight went by", "two weeks have passed". Backstory is not a
  /// skip: "for two weeks", "three years had passed since the accident".
  static final _narrated = RegExp(
    '\\b(?:$_count\\s*)?$_longUnit$_half\\s+'
    r'(?:later|(?:have|has|had)\s+(?:passed|gone\s+by|elapsed|flown\s+by|'
    r'slipped\s+by|come\s+and\s+gone)|pass(?:es|ed)?(?:\s+by)?|'
    r'go(?:es)?\s+by|went\s+by|elapse[sd]?|slip(?:s|ped)?\s+by|'
    r'fl(?:y|ies|ew)\s+by|roll(?:s|ed)?\s+by|drag(?:s|ged)?\s+by)'
    r'\b(?!\s+since\b)',
  );

  /// Or asked for: "skip ahead two weeks", "time skip: 3 days", "fast
  /// forward: 3 months". A bare skip needs a direction or an OOC marker:
  /// "I skip a day of school" is not one.
  static final _asked = RegExp(
    r'\b(?:(?:time.?skip(?:ped)?|fast.?forward(?:ed|s)?)'
    r'(?:\s+(?:ahead|forward))?'
    r'|(?:skip|jump)(?:s|ped|ed)?\s+(?:ahead|forward|by|to))'
    r'\s*(?:[:,\-–—]\s*)?(?:(?:by|to|of|about|around)\s+)?'
    '(?:$_count\\s*)?$_longUnit$_half\\b',
  );

  static final _oocBare = RegExp(
    '\\bskip\\s+(?:$_count\\s*)?$_longUnit$_half\\b',
  );

  static final _oocMarker = RegExp(r'\(ooc[:\s]|\[ooc|\*ooc\b|ooc:');

  /// Any day-plus unit at all, for the last-resort landing.
  static final _anyLong = RegExp('\\b(?:$_count\\s*)?$_longUnit$_half\\b');

  static final _shortDigit = RegExp(r'\b(\d+)\s*(minutes?|hours?|days?)\b');
  static final _shortWord = RegExp(
    '\\b($_word|an?)\\s*(minutes?|hours?|days?)\\b',
  );

  static Iterable<RegExpMatch> _longMatches(String lower) sync* {
    yield* _narrated.allMatches(lower);
    yield* _asked.allMatches(lower);
    if (_oocMarker.hasMatch(lower)) yield* _oocBare.allMatches(lower);
  }

  /// True when [lower] narrates or asks for a skip of a day or more.
  static bool namesLongSkip(String lower) =>
      _longMatches(lower).any((m) => _span(m) != null);

  /// Landing for a day-plus skip, or null when [lower] names none. The
  /// date moves the span; the time of day follows [landSkipInDay].
  static DateTime? longLanding(DateTime clock, String lower) {
    for (final m in _longMatches(lower)) {
      final span = _span(m);
      if (span != null) return _land(clock, span, lower);
    }
    return null;
  }

  /// Last resort for a line the skip gate already accepted: any day-plus
  /// unit ("time skip, it's been weeks") still lands days on, never +1h.
  static DateTime? anyLongLanding(DateTime clock, String lower) {
    for (final m in _anyLong.allMatches(lower)) {
      final span = _span(m);
      if (span != null) return _land(clock, span, lower);
    }
    return null;
  }

  /// Digit or word duration in minutes, hours or days ("6 hours", "six
  /// hours", "10 days" under an OOC marker). Null if none.
  static DateTime? shortLanding(DateTime clock, String lower) {
    final m = _shortDigit.firstMatch(lower) ?? _shortWord.firstMatch(lower);
    if (m == null) return null;
    final n = _countOf(m.group(1)!, m.group(2)!);
    if (n <= 0) return null;
    final unit = m.group(2)!;
    if (unit.startsWith('day')) {
      return _land(clock, (n: n, unit: 'day', half: false), lower);
    }
    if (unit.startsWith('hour')) {
      return clock.add(Duration(hours: n.clamp(1, 72)));
    }
    return clock.add(Duration(minutes: n.clamp(1, 24 * 60)));
  }

  static ({int n, String unit, bool half})? _span(RegExpMatch m) {
    final raw = m.group(1);
    final unitWord = m.group(2)!;
    final unit = unitWord.replaceAll(RegExp(r's$'), '');
    final half = m.group(3) != null;
    if (raw == null || raw == 'many' || raw == 'some') {
      if (unit == 'fortnight') return (n: 1, unit: unit, half: half);
      // "As the days passed" is mood, not a jump: no number needs "later",
      // "have passed" or an explicit skip ("time skip: weeks").
      final all = m.group(0)!;
      final tail = all.substring(all.lastIndexOf(unitWord) + unitWord.length);
      if (tail.trim().isNotEmpty && !_vagueVerb.hasMatch(tail)) return null;
      if (unitWord == unit) return null; // "week later": not a span
      return (n: _vagueByUnit[unit]!, unit: unit, half: false);
    }
    final n = _countOf(raw, unitWord);
    if (n <= 0) return null;
    return (n: n, unit: unit, half: half);
  }

  static int _countOf(String raw, String unitWord) {
    final digit = int.tryParse(raw);
    if (digit != null) return digit;
    final known = _units[raw] ?? _teens[raw] ?? _vague[raw];
    if (known != null) return known;
    if (raw == 'a' || raw == 'an') return 1;
    final parts = raw.split(RegExp(r'[- ]'));
    final tens = _tens[parts.first];
    if (tens == null) return 0;
    return tens + (parts.length > 1 ? _units[parts.last] ?? 0 : 0);
  }

  static DateTime _land(
    DateTime clock,
    ({int n, String unit, bool half}) span,
    String lower,
  ) {
    final n = span.n;
    final date = switch (span.unit) {
      'year' => _addMonths(clock, 12 * n.clamp(1, 10) + (span.half ? 6 : 0)),
      'month' => _addMonths(
        clock,
        n.clamp(1, 24),
      ).add(Duration(days: span.half ? 15 : 0)),
      'fortnight' => clock.add(
        Duration(days: 14 * n.clamp(1, 26) + (span.half ? 7 : 0)),
      ),
      'week' => clock.add(
        Duration(hours: 24 * 7 * n.clamp(1, 52) + (span.half ? 84 : 0)),
      ),
      _ => clock.add(
        Duration(hours: 24 * n.clamp(1, 365) + (span.half ? 12 : 0)),
      ),
    };
    return landSkipInDay(date, lower);
  }

  /// Same day of the month, pulled back to the month's last day when it is
  /// shorter (31 Jan + 1 month is 28 or 29 Feb, not 3 Mar).
  static DateTime _addMonths(DateTime clock, int months) {
    final first = DateTime.utc(clock.year, clock.month + months, 1);
    final last = DateTime.utc(first.year, first.month + 1, 0).day;
    return DateTime.utc(
      first.year,
      first.month,
      clock.day > last ? last : clock.day,
      clock.hour,
      clock.minute,
    );
  }
}
