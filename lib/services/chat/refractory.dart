// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The refractory on the story clock (docs/design/needs-on-the-clock.md,
// "Refractory on the clock"). It counts story minutes: the judge's turns at
// 15 minutes each, worn down by every clock advance, or a quarter hour per
// reply while Passage of Time is off. Pure; NsfwService and ChatService
// apply it.

/// One judge turn of refractory, and one reply with the clock off.
const int kRefractoryMinutesPerTurn = 15;

/// The soft gate's tenderness window (decision 4): a fixed stretch of story
/// minutes in which touch lands at half weight. Capacity never closes, so
/// this is not a lock — the chip says "Tender", the ladder says "flinch that
/// turns into leaning in", and a second climax inside it is legal.
const int kTendernessWindowMinutes = 15;

/// A peak stops counting one story hour after it (decision 5) — the same
/// ledger every other beat ages on, no reply counters.
const int kPeakHourMinutes = 60;

/// Soft-gate peak math (decision 4): a climax keeps at least 40% of the
/// distance above [kPeakFloor], and the peak count is capped at [kPeakCap],
/// which is what keeps a body that starts at or above the floor from ever
/// dropping below it. A climax that starts below the floor costs nothing.
const int kPeakFloor = 50;
const int kPeakCap = 3;

/// Decision 4's bite: `round(0.2 × max(arousal − 50, 0) × peaks)`. [peaks]
/// counts this story hour's peaks including this one.
int softPeakCost(int arousal, int peaks) {
  final above = arousal > kPeakFloor ? arousal - kPeakFloor : 0;
  return (0.2 * above * peaks.clamp(1, kPeakCap)).round();
}

/// Snapshot, member-map and receipt keys. The two turn keys are what chats
/// saved before minutes; they are read once, as turns × 15. The soft and
/// peak keys (PR 3) are only written when set — a body that reads today's
/// defaults means exactly what it meant before this PR.
abstract final class RefractoryKeys {
  static const minutes = 'refractoryMinutesRemaining';
  static const total = 'refractoryMinutesTotal';
  static const opened = 'refractoryOpened';
  static const soft = 'refractorySoft';

  /// "Story minutes since that peak", oldest first, under [kPeakHourMinutes].
  static const peaks = 'refractoryPeakMinutes';
  static const legacyTurns = 'cooldownTurnsRemaining';
  static const legacyTotal = 'cooldownTurnsTotal';
  static const all = [
    minutes,
    total,
    opened,
    soft,
    peaks,
    legacyTurns,
    legacyTotal,
  ];
}

/// One body's refractory: story minutes left, the length it started at,
/// whether its opening afterglow turn (the one reply that may show a limp,
/// spent body) has been spoken, and — the soft gate (PR 3) — whether this
/// body recovers through a tenderness window instead of a capacity lock,
/// with this hour's peak stamps beside them.
class Refractory {
  const Refractory({
    this.minutes = 0,
    this.total = 0,
    this.opened = false,
    this.soft = false,
    this.peaks = const [],
  });

  static const none = Refractory();

  final int minutes;
  final int total;
  final bool opened;

  /// Soft gate: the minutes count a tenderness window, not a lock. Arousal
  /// stays up; gains halve while the window runs; peaks cost per decision 4.
  final bool soft;

  /// Story minutes since each peak, oldest first, capped at [kPeakCap] and
  /// pruned at [kPeakHourMinutes] (decision 5). The soft body's warm-again
  /// beat holds while this list is non-empty.
  final List<int> peaks;

  bool get running => minutes > 0;

  /// Peaks counted this story hour — the chip's "· peak K" and the peak
  /// cost's multiplier source.
  int get peaksLastHour => peaks.length;

  /// The first reply after the climax reply, and only that one.
  bool get isOpeningTurn => running && !opened;

  /// Canonical constructor: the length in story minutes — a card's fixed
  /// recovery minutes (recovery overhaul PR 2) or any ledger-computed value.
  /// Zero or less starts no refractory; that is a real answer, not an error.
  factory Refractory.fromMinutes(int minutes, {bool soft = false}) =>
      minutes > 0
      ? Refractory(minutes: minutes, total: minutes, soft: soft)
      : none;

  /// A soft climax's window, carrying this hour's peak stamps forward.
  factory Refractory.tenderness(List<int> peaks) => Refractory(
    minutes: kTendernessWindowMinutes,
    total: kTendernessWindowMinutes,
    soft: true,
    peaks: peaks,
  );

  /// Set at climax from the judge's `refractory_turns` (each ≈ 15 story
  /// minutes). A wrapper over [fromMinutes] — the judge number is one
  /// possible length, and a card's fixed profile minutes bypass it.
  factory Refractory.fromJudgeTurns(int turns) =>
      Refractory.fromMinutes(turns * kRefractoryMinutesPerTurn);

  /// A count saved in replies before minutes existed. The opening turn was
  /// already spoken once a reply had ticked it (remaining below total).
  factory Refractory.fromLegacyTurns(int remaining, int total) {
    if (remaining <= 0) return none;
    final t = total > remaining ? total : remaining;
    return Refractory(
      minutes: remaining * kRefractoryMinutesPerTurn,
      total: t * kRefractoryMinutesPerTurn,
      opened: remaining < t,
    );
  }

  /// Reads [RefractoryKeys] from a snapshot, a member map or a session row.
  /// Minutes win; turns are read only where minutes were never written.
  /// Null when neither is there, so a restore keeps what it has. Soft and
  /// peaks are lenient: absent or junk reads today's defaults (a hard lock,
  /// no peaks), so every body saved before PR 3 means what it meant then.
  static Refractory? read(Map<dynamic, dynamic> src) {
    final m = src[RefractoryKeys.minutes];
    if (m is num) {
      final minutes = m.toInt();
      final soft = src[RefractoryKeys.soft] == true;
      final peaks = readPeakStamps(src[RefractoryKeys.peaks]);
      if (minutes <= 0) {
        if (!soft && peaks.isEmpty) return none;
        return Refractory(soft: soft, peaks: peaks);
      }
      final t = src[RefractoryKeys.total];
      final total = t is num ? t.toInt() : 0;
      return Refractory(
        minutes: minutes,
        total: total > minutes ? total : minutes,
        opened: src[RefractoryKeys.opened] == true,
        soft: soft,
        peaks: peaks,
      );
    }
    final turns = src[RefractoryKeys.legacyTurns];
    if (turns is! num) return null;
    final total = src[RefractoryKeys.legacyTotal];
    return Refractory.fromLegacyTurns(
      turns.toInt(),
      total is num ? total.toInt() : 0,
    );
  }

  /// Lenient read of peak stamps off untyped JSON: numbers only, in range,
  /// newest kept when a hand-edited file overflows the cap.
  static List<int> readPeakStamps(Object? raw) {
    if (raw is! Iterable) return const [];
    final stamps = raw
        .whereType<num>()
        .map((e) => e.toInt())
        .where((m) => m >= 0 && m < kPeakHourMinutes)
        .toList(growable: false);
    return stamps.length <= kPeakCap
        ? stamps
        : stamps.sublist(stamps.length - kPeakCap);
  }

  Map<String, Object> toSnapshot() => {
    RefractoryKeys.minutes: minutes,
    RefractoryKeys.total: total,
    RefractoryKeys.opened: opened,
    if (soft) RefractoryKeys.soft: true,
    if (peaks.isNotEmpty) RefractoryKeys.peaks: peaks,
  };

  /// [elapsed] story minutes on a body whose arousal is [arousal]. The
  /// window and every peak stamp age on the same beat. When a hard
  /// refractory ends the total clears and a negative arousal halves toward
  /// neutral, so nobody leaves it reading as cold or repelled; a soft window
  /// simply expires (decision 4 — a soft body's arousal was never crashed,
  /// so there is nothing to thaw).
  ({Refractory refractory, int arousal}) elapse(
    int elapsed, {
    required int arousal,
  }) {
    if (elapsed <= 0) return (refractory: this, arousal: arousal);
    final aged = peaks
        .map((m) => m + elapsed)
        .where((m) => m < kPeakHourMinutes)
        .toList(growable: false);
    if (!running) {
      if (peaks.isEmpty) return (refractory: this, arousal: arousal);
      return (
        refractory: Refractory(soft: soft, peaks: aged),
        arousal: arousal,
      );
    }
    final left = minutes - elapsed;
    if (left > 0) {
      return (
        refractory: Refractory(
          minutes: left,
          total: total,
          opened: opened,
          soft: soft,
          peaks: aged,
        ),
        arousal: arousal,
      );
    }
    if (soft) {
      return (
        refractory: Refractory(soft: true, peaks: aged),
        arousal: arousal,
      );
    }
    final rest = aged.isEmpty ? none : Refractory(peaks: aged);
    return (refractory: rest, arousal: arousal < 0 ? arousal ~/ 2 : arousal);
  }

  /// The opening turn has been spoken.
  Refractory markOpened() => isOpeningTurn
      ? Refractory(
          minutes: minutes,
          total: total,
          opened: true,
          soft: soft,
          peaks: peaks,
        )
      : this;

  @override
  bool operator ==(Object other) =>
      other is Refractory &&
      other.minutes == minutes &&
      other.total == total &&
      other.opened == opened &&
      other.soft == soft &&
      other.peaks.length == peaks.length &&
      other.peaks.asMap().entries.every((e) => e.value == peaks[e.key]);

  @override
  int get hashCode =>
      Object.hash(minutes, total, opened, soft, Object.hashAll(peaks));

  @override
  String toString() =>
      'Refractory($minutes/$total, opened: $opened, soft: $soft, '
      'peaks: $peaks)';
}

/// The countdown in the words the sidebar chip, the eval prompt and the phone
/// share. Clock on: story minutes, to the nearest 5. Clock off: replies, each
/// a quarter hour, rounded up. A soft window says "Tender" and names the
/// peak count (the mockup's rose chip); a hard lock keeps "Refractory".
({String chip, String prompt}) describeRefractory(
  int minutes, {
  required bool clockRunning,
  bool soft = false,
  int peaks = 0,
}) {
  if (minutes <= 0) return (chip: '', prompt: '');
  final String left;
  if (clockRunning) {
    final rounded = ((minutes + 2) ~/ 5) * 5;
    left = 'about ${rounded < 5 ? 5 : rounded} min';
  } else {
    final replies =
        (minutes + kRefractoryMinutesPerTurn - 1) ~/ kRefractoryMinutesPerTurn;
    left = replies == 1 ? '1 reply' : '$replies replies';
  }
  return soft
      ? (
          chip: 'Tender for $left · peak ${peaks < 1 ? 1 : peaks}',
          prompt: '($left left)',
        )
      : (chip: 'Refractory: $left', prompt: '($left left)');
}

/// Stamped on a reply: each body the beat moved, as the beat found it (regen
/// and a tail delete put it back) and as the beat left it (a swipe shows it).
const String kRefractoryPreBeat = 'refractory_pre_beat';
const String kRefractoryPostBeat = 'refractory_post_beat';

/// One body in a receipt. Arousal rides along because a refractory that ends
/// halves a negative arousal.
typedef RefractoryBody = ({Refractory refractory, int arousal});

/// Records [id] on the receipts in [meta]. The first record of a beat keeps
/// its "before"; the latest keeps its "after".
void noteRefractoryBeat(
  Map<String, dynamic> meta,
  String id, {
  required RefractoryBody before,
  required RefractoryBody after,
}) {
  final pre = Map<String, dynamic>.from(
    meta[kRefractoryPreBeat] as Map? ?? const {},
  );
  pre.putIfAbsent(id, () => _bodyJson(before));
  meta[kRefractoryPreBeat] = pre;
  final post = Map<String, dynamic>.from(
    meta[kRefractoryPostBeat] as Map? ?? const {},
  );
  post[id] = _bodyJson(after);
  meta[kRefractoryPostBeat] = post;
}

/// Reads one receipt off a message. Metadata comes back untyped.
Map<String, RefractoryBody> refractoryReceipt(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, RefractoryBody>{};
  for (final entry in raw.entries) {
    final body = entry.value;
    if (body is! Map) continue;
    final arousal = body['arousal'];
    out[entry.key.toString()] = (
      refractory: Refractory.read(body) ?? Refractory.none,
      arousal: arousal is num ? arousal.toInt() : 0,
    );
  }
  return out;
}

Map<String, Object> _bodyJson(RefractoryBody body) => {
  ...body.refractory.toSnapshot(),
  'arousal': body.arousal,
};
