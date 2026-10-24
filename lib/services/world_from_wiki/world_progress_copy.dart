// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Progress lines for the wizard: what it is doing right now, in plain words
// with a bit of cheek, so a twenty-minute run reads as work and not as a
// spinner that says "scouting". One source for the desktop and the phone
// (the relay forwards these lines as they come).

/// Before the catalog is read.
String worldProgressRummaging() => 'Rummaging through the wiki…';

/// The catalog is in; the scout is about to pick.
String worldProgressCatalog(int pages, {required bool ranked}) => ranked
    ? 'Found the $pages pages this wiki links to most. Picking the ones '
          'that matter…'
    : 'Found $pages pages. Picking the ones that matter…';

/// One part of a split index, asked on its own.
String worldProgressScoutPart(int index, int total, int titles) =>
    'Picking the ones that matter (part $index of $total, $titles pages)…';

/// The parts of a split index, all out at once on a remote provider.
String worldProgressScoutPartsOut(int parts, int pages) =>
    'Picking the ones that matter: $parts parts of about $pages pages, '
    'asked together…';

/// A part came back.
String worldProgressScoutPartDone(
  int index,
  int total,
  int cards,
  int places,
) =>
    'Part $index of $total answered: $cards cards'
    '${places > 0 ? ', $places places' : ''}.';

/// The shelf is in and signed off.
String worldProgressShelfReady(int cards, int places) =>
    'Shelf ready: $cards cards, $places places. Sign the ones to write.';

/// A review loop's stage passed.
String worldProgressStagePassed(String stage) => '$stage — passed.';

/// One fill gap came back.
String worldProgressFillDone(String what, int added) => added == 0
    ? 'Nothing new for $what.'
    : '$what: +$added card${added == 1 ? '' : 's'}.';

/// The entry reviewer's count for a batch.
String worldProgressReviewed(int passed, int back, String why) => back == 0
    ? 'All $passed ${_entries(passed)} passed.'
    : '$passed passed, $back sent back: ${_clip(why, 110)}';

/// A place's book is finished.
String worldProgressBookDone(String book, int cards) =>
    '$book\'s book is done: $cards card${cards == 1 ? '' : 's'}.';

/// The world's climate came back.
String worldProgressWeatherDone(String name) => 'Weather written: $name.';

/// A part the model could not finish is asked again as two.
String worldProgressHalving(int a, int b) =>
    'That was too much at once. Asking again as two halves '
    '($a and $b pages)…';

/// Prose came back with the answer inside it.
String worldProgressProseRead() =>
    'The model told it in prose instead of calling the tool. Reading the '
    'answer out of the prose…';

/// Prose came back with nothing usable; the second ask has thinking off.
String worldProgressAskingAgain() =>
    'The model told a story instead of answering. Asking again with its '
    'thinking off…';

/// The call ran past its cutoff and was hung up on.
String worldProgressTimeout(Duration d) =>
    'No answer in ${worldProgressMinutes(d)}. Hanging up and asking again…';

/// The server threw (a 502, a closed connection).
String worldProgressStumble(Object e) =>
    'The server stumbled (${_clip('$e', 90)}). Asking again…';

/// The reviewer's second model call is in flight.
String worldProgressReviewerReading(String stage) =>
    '$stage — the reviewer is reading it…';

/// A revise, with the first finding it answers.
String worldProgressRevising(
  String stage,
  List<String> feedback,
  int attempt,
  int of,
) {
  final why = feedback.isEmpty ? '' : ': ${_clip(feedback.first, 110)}';
  return 'Sent back$why. Revising (try $attempt of $of)…';
}

/// One gap the fill loop works.
String worldProgressFill(String what, int round, int rounds, int candidates) =>
    'Hunting for what the shelf forgot: $what (round $round of $rounds, '
    '$candidates candidates)…';

/// The articles are being fetched.
String worldProgressReading(int pages) => 'Reading up on $pages pages…';

/// One write batch, in a place's book when [book] is given.
String worldProgressWriting(int from, int to, int of, {String book = ''}) {
  final span = from == to ? 'card $to' : 'cards $from–$to';
  return book.isEmpty
      ? 'Writing $span of $of…'
      : 'Writing the $book book: $span of $of…';
}

/// The entry reviewer's call.
String worldProgressEntriesReview(
  int n, {
  required int attempt,
  required int of,
}) => attempt == 1
    ? 'Reading $n fresh ${_entries(n)} against the story…'
    : 'Re-reading $n rewritten ${_entries(n)} (try $attempt of $of)…';

/// Entries the Dart gate refused before any reviewer saw them.
String worldProgressThin(int n, String firstProblem) =>
    '$n ${_entries(n)} came back thin ($firstProblem). Sending '
    '${n == 1 ? 'it' : 'them'} back…';

/// The revise call for entries a reviewer or the gate sent back.
String worldProgressRewrite(int n, int attempt, int of) =>
    'Rewriting $n ${_entries(n)} the reviewer sent back '
    '(try $attempt of $of)…';

/// A place's profile call.
String worldProgressProfile(String name) => 'Walking around $name…';

/// The Review step: the author's note is being sorted against the shelf.
String worldProgressTriage() => 'Reading your note against the shelf…';

/// The Review step: entries rewritten with the author's note as the finding.
String worldProgressDirected(int n) =>
    'Rewriting $n ${_entries(n)} the way you asked…';

/// The Review step: one card added by hand is written from its page.
String worldProgressAdding(String name) => 'Writing $name from its page…';

/// The world's climate call.
String worldProgressClimate() => 'Checking the weather…';

/// "6 minutes", "1 minute", "50 seconds".
String worldProgressMinutes(Duration d) {
  final m = d.inMinutes;
  if (m >= 1) return '$m minute${m == 1 ? '' : 's'}';
  return '${d.inSeconds} seconds';
}

/// Clock-face elapsed time for the panel: 0:42, 12:05, 1:03:09.
String worldElapsedLabel(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  final mm = h > 0 ? m.toString().padLeft(2, '0') : '$m';
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

String _entries(int n) => n == 1 ? 'entry' : 'entries';

String _clip(String s, int max) {
  final one = s.replaceAll('\n', ' ').trim();
  return one.length > max ? '${one.substring(0, max)}…' : one;
}

/// The three stages a scout goes through, for the progress card's chips.
const List<String> kWorldScoutStages = [
  'Scout the index',
  'Reviewer reads the shelf',
  'Fill what it forgot',
];

/// The three stages a write goes through.
const List<String> kWorldWriteStages = [
  'Write the cards',
  'Reviewer reads them',
  'Places and weather',
];

/// Which scout stage a progress line belongs to (0-based), from its words.
int worldScoutStageOf(String line) {
  final l = line.toLowerCase();
  if (l.startsWith('hunting') ||
      l.startsWith('nothing new') ||
      l.contains(': +') ||
      l.startsWith('shelf ready')) {
    return 2;
  }
  if (l.startsWith('reading the shelf') ||
      l.startsWith('sent back') ||
      l.contains('reviewer is reading') ||
      l.contains('— passed')) {
    return 1;
  }
  return 0;
}

/// Which write stage a progress line belongs to (0-based), from its words.
int worldWriteStageOf(String line) {
  final l = line.toLowerCase();
  if (l.startsWith('walking around') ||
      l.startsWith('checking the weather') ||
      l.startsWith('weather written') ||
      l.contains('book is done')) {
    return 2;
  }
  if (l.startsWith('reading ') ||
      l.startsWith('re-reading') ||
      l.startsWith('rewriting') ||
      l.contains('sent back') ||
      l.contains('passed')) {
    return 1;
  }
  return 0;
}

/// "MediaWiki", "Tiddly" or "Wiki" from the address alone, for a tile's
/// subtitle before any scout has read it.
String worldWikiKindGuess(String url) {
  final u = url.toLowerCase();
  if (u.contains('fandom.com') ||
      u.contains('wikipedia.org') ||
      u.contains('/wiki/') ||
      u.contains('wiki.')) {
    return 'MediaWiki';
  }
  if (u.contains('tiddly') || u.contains('github.io')) return 'Tiddly';
  return 'Wiki';
}
