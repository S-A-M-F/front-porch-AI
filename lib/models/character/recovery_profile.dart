// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// The card's recovery profile — how its character comes down after climax
// (docs/design/afterglow-recovery-overhaul.md, decisions 2–3). Two stored
// values, each with one job: `recoveryMode` picks the KIND, `recoveryMinutes`
// fixes the LENGTH of a hard lock (null = the personality judge decides).
// The editor presents them as one preset dropdown, so there is no
// "which wins" branch at runtime: a fixed length replaces the judge's
// number, nothing else about the mechanic changes (PR 3 gives `soft` its
// own physics; until then it behaves as `hard` — stored, not acted on).
//
// Held by ONE field on FrontPorchExtensions (`recovery`) so the extensions
// class stays under the 500-line ratchet while later fields (PR 8's
// `pcdMood`) join here instead of inline. Since PR 3 the soft gate runs its
// own physics: peak costs, a tenderness window, and peak stamps on the
// story-minute ledger.

import 'pcd_mood.dart';

/// The preset values a card may store. `auto` = the structured sex decides
/// the kind and the judge the length (decision 2's prior; anything but a
/// female card resolves to today's hard lock — "no card gets surprised").
const String kRecoveryModeAuto = 'auto';
const String kRecoveryModeHard = 'hard';
const String kRecoveryModeSoft = 'soft';

/// Structured card sex — only ever the `auto` prior. Stored normalized;
/// see [normalizeCharacterSex].
const String kSexMale = 'male';
const String kSexFemale = 'female';
const String kSexOther = 'other';

/// The slider's span on the card (minutes of story time). The judge's own
/// ceiling (0–12 turns × 15) is the same 180 on purpose — the slider moves
/// within the numbers the judge can already produce.
const int kRecoveryMinutesMin = 0;
const int kRecoveryMinutesMax = 180;

/// One thing a preset dropdown entry stores. `key` is UI-only (never
/// persisted); `minutes` for `custom` is whatever the slider holds.
class RecoveryPreset {
  const RecoveryPreset({
    required this.key,
    required this.label,
    required this.recoveryMode,
    required this.recoveryMinutes,
  });

  final String key;
  final String label;
  final String recoveryMode;
  final int? recoveryMinutes;
}

/// Decision 3's table, in menu order. Mirrored in
/// `web_ui/src/components/realism/realismTypes.ts` (the browser cannot call
/// Dart — same precedent as the tier names); the vitest pins both against
/// the identical values.
const List<RecoveryPreset> kRecoveryPresets = [
  RecoveryPreset(
    key: 'auto',
    label: 'Auto — judge + physiology decide',
    recoveryMode: kRecoveryModeAuto,
    recoveryMinutes: null,
  ),
  RecoveryPreset(
    key: 'none',
    label: 'None / multiorgasmic',
    recoveryMode: kRecoveryModeSoft,
    recoveryMinutes: null,
  ),
  RecoveryPreset(
    key: 'personality',
    label: 'Lock, length by personality',
    recoveryMode: kRecoveryModeHard,
    recoveryMinutes: null,
  ),
  RecoveryPreset(
    key: 'short',
    label: 'Short (30)',
    recoveryMode: kRecoveryModeHard,
    recoveryMinutes: 30,
  ),
  RecoveryPreset(
    key: 'typical',
    label: 'Typical (90)',
    recoveryMode: kRecoveryModeHard,
    recoveryMinutes: 90,
  ),
  RecoveryPreset(
    key: 'long',
    label: 'Long (180)',
    recoveryMode: kRecoveryModeHard,
    recoveryMinutes: 180,
  ),
  RecoveryPreset(
    key: 'custom',
    label: 'Custom',
    recoveryMode: kRecoveryModeHard,
    recoveryMinutes: null,
  ),
];

/// Lenient structured-sex read (plan trap 4): case-insensitive token scan —
/// the same family of words `resolveNarrativePronouns` maps, checked in the
/// same order (they-first so "nonbinary female" does not read female,
/// female-before-masculine so "female" is not swallowed by "male"), the
/// bare `m` / `f` as whole words, blank stays blank (the author said
/// nothing). Any other non-blank value — futanari, shapeshifter, junk from
/// a hand-edited PNG — reads `other`, which the `auto` prior treats exactly
/// like blank: today's hard lock until the author chooses a mode. Never
/// throws.
String normalizeCharacterSex(Object? raw) {
  final s = (raw ?? '').toString().trim().toLowerCase();
  if (s.isEmpty) return '';
  bool has(Iterable<String> words) =>
      words.any((w) => RegExp('\\b${RegExp.escape(w)}\\b').hasMatch(s));
  if (has(const [
    'they',
    'them',
    'nonbinary',
    'non-binary',
    'non binary',
    'enby',
    'nb',
    'genderfluid',
    'agender',
    'genderless',
    'asexual',
    'ace',
    'futanari',
    'futa',
    'shapeshifter',
    'shapechanger',
    'herm',
  ])) {
    return kSexOther;
  }
  if (has(const [
    'female',
    'woman',
    'women',
    'girl',
    'lady',
    'feminine',
    'she',
    'her',
    'f',
  ])) {
    return kSexFemale;
  }
  if (has(const [
    'male',
    'man',
    'men',
    'boy',
    'guy',
    'masculine',
    'he',
    'him',
    'm',
  ])) {
    return kSexMale;
  }
  return kSexOther;
}

/// The card's stored recovery settings. Immutable value object: editors
/// replace it wholesale ([withMinutes], [fromPreset]), matching how
/// FrontPorchExtensions replaces its lists.
class RecoveryProfile {
  const RecoveryProfile({
    this.recoveryMode = kRecoveryModeAuto,
    this.recoveryMinutes,
    this.pcdMood = kPcdMoodOff,
  });

  final String recoveryMode;

  /// A hard-lock length the card authored, or null when the judge decides.
  /// Only ever non-null with mode `hard` ([fromJson] and the setters normalize
  /// the pair; the soft-gate tenderness window is fixed by decision 4).
  final int? recoveryMinutes;

  /// Post-coital dysphoria dial (PR 8): `off` / `rare` / `sometimes`.
  /// Opt-in by law — a card that never stores the key never rolls the grey
  /// beat, so no existing character gets a surprise tone-shift. The roll
  /// happens once per climax at first reading ([pcdRollHit]); the beat
  /// itself lives in the reply's metadata, not here.
  final String pcdMood;

  static const auto = RecoveryProfile();

  bool get isDefault =>
      recoveryMode == kRecoveryModeAuto &&
      recoveryMinutes == null &&
      pcdMood == kPcdMoodOff;

  /// The stored dial's per-climax roll rate (0 for off and for junk).
  double get pcdRate => switch (pcdMood) {
    kPcdMoodRare => kPcdRateRare,
    kPcdMoodSometimes => kPcdRateSometimes,
    _ => 0.0,
  };

  /// Roll a climax into the grey beat? [rand] is the injectable source
  /// (seeded in tests); off and junk never roll, and the roll consumes a
  /// draw only when a dial is set — an `off` card must not shift the
  /// sequence a later dial change would see.
  bool pcdRollHit(double Function() rand) => pcdRate > 0 && rand() < pcdRate;

  /// The kind this profile resolves to for a card whose structured sex is
  /// [sex] (decision 2): the author's explicit mode always beats the prior;
  /// `auto` maps a female card to the soft gate and everything else to the
  /// hard lock. The result is the same in 1:1 and groups — a member's card
  /// is read as the reply's speaker.
  String resolvedMode(String sex) => switch (recoveryMode) {
    kRecoveryModeHard => kRecoveryModeHard,
    kRecoveryModeSoft => kRecoveryModeSoft,
    _ =>
      normalizeCharacterSex(sex) == kSexFemale
          ? kRecoveryModeSoft
          : kRecoveryModeHard,
  };

  String get presetKey {
    if (recoveryMode == kRecoveryModeSoft) return 'none';
    if (recoveryMode != kRecoveryModeHard) return 'auto';
    return switch (recoveryMinutes) {
      null => 'personality',
      30 => 'short',
      90 => 'typical',
      180 => 'long',
      _ => 'custom',
    };
  }

  /// The dropdown's label for the stored pair (Custom for a slider value
  /// that matches no named preset).
  String get presetLabel =>
      kRecoveryPresets.firstWhere((p) => p.key == presetKey).label;

  /// The preset menu's stored pair for [key]. `custom` never routes here —
  /// it carries the slider's live value, so the block calls [withMinutes]
  /// for that selection instead. The pcd dial is orthogonal to the preset
  /// and rides through untouched ([PcdOption] has its own control).
  static RecoveryProfile fromPreset(
    String key, {
    String pcdMood = kPcdMoodOff,
  }) => switch (key) {
    'none' => RecoveryProfile(
      recoveryMode: kRecoveryModeSoft,
      pcdMood: pcdMood,
    ),
    'personality' => RecoveryProfile(
      recoveryMode: kRecoveryModeHard,
      pcdMood: pcdMood,
    ),
    'short' => RecoveryProfile(
      recoveryMode: kRecoveryModeHard,
      recoveryMinutes: 30,
      pcdMood: pcdMood,
    ),
    'typical' => RecoveryProfile(
      recoveryMode: kRecoveryModeHard,
      recoveryMinutes: 90,
      pcdMood: pcdMood,
    ),
    'long' => RecoveryProfile(
      recoveryMode: kRecoveryModeHard,
      recoveryMinutes: 180,
      pcdMood: pcdMood,
    ),
    _ => RecoveryProfile(pcdMood: pcdMood),
  };

  /// Moving the slider selects Custom (decision 3): a hard lock of exactly
  /// this many minutes. The pcd dial is orthogonal — it survives.
  RecoveryProfile withMinutes(int minutes) => RecoveryProfile(
    recoveryMode: kRecoveryModeHard,
    recoveryMinutes: minutes.clamp(kRecoveryMinutesMin, kRecoveryMinutesMax),
    pcdMood: pcdMood,
  );

  /// The pcd dial's setter. Junk normalizes to `off` (opt-in by law).
  RecoveryProfile withPcdMood(String mood) => RecoveryProfile(
    recoveryMode: recoveryMode,
    recoveryMinutes: recoveryMinutes,
    pcdMood: normalizePcdMood(mood),
  );

  /// Card JSON (`realism_engine.recovery`). Only written when non-default;
  /// the mode always rides with the minutes so the pair is never split by
  /// a half-write.
  Map<String, dynamic> toJson() => {
    'mode': recoveryMode,
    if (recoveryMinutes != null) 'minutes': recoveryMinutes,
    if (pcdMood != kPcdMoodOff) 'pcd': pcdMood,
  };

  /// The web bridge shape (`toFields` precedent from greeting seeds): the
  /// PWA's own camelCase field names, so the React form consumes the map
  /// without an intermediate mapping layer.
  Map<String, dynamic> toFields() => {
    'recoveryMode': recoveryMode,
    'recoveryMinutes': recoveryMinutes,
    'pcdMood': pcdMood,
  };

  static RecoveryProfile fromFields(Object? raw) => _read(
    raw,
    modeKey: 'recoveryMode',
    minutesKey: 'recoveryMinutes',
    pcdKey: 'pcdMood',
  );

  /// Lenient like every other card reader (a card comes from anywhere):
  /// absent/malformed reads defaults, junk mode reads `auto`, an
  /// out-of-span length clamps, and a length on `auto`/`soft` is dropped —
  /// decision 3 says those pairs carry no length, and keeping a stray one
  /// would make the preset menu lie about what it shows.
  static RecoveryProfile fromJson(Object? raw) =>
      _read(raw, modeKey: 'mode', minutesKey: 'minutes', pcdKey: 'pcd');

  static RecoveryProfile _read(
    Object? raw, {
    required String modeKey,
    required String minutesKey,
    required String pcdKey,
  }) {
    if (raw is! Map) return auto;
    final mode = switch (raw[modeKey]?.toString().trim().toLowerCase()) {
      kRecoveryModeHard => kRecoveryModeHard,
      kRecoveryModeSoft => kRecoveryModeSoft,
      _ => kRecoveryModeAuto,
    };
    final pcd = normalizePcdMood(raw[pcdKey]);
    if (mode != kRecoveryModeHard) {
      return RecoveryProfile(recoveryMode: mode, pcdMood: pcd);
    }
    final m = raw[minutesKey];
    final n = m is num
        ? m.toInt()
        : m is String
        ? int.tryParse(m.trim())
        : null;
    return RecoveryProfile(
      recoveryMode: mode,
      recoveryMinutes: (n ?? -1) < kRecoveryMinutesMin
          ? null
          : n!.clamp(kRecoveryMinutesMin, kRecoveryMinutesMax),
      pcdMood: pcd,
    );
  }
}

/// Chargen's PRESET SUGGESTION (plan PR 2: "suggests a preset from the
/// intimacy answer — the author confirms, never silent"). Read from the
/// authored intimate signals — the interview's intimacy answer lands in the
/// card's intimate preference lists — with a plain keyword scan, no model
/// call. Multi-capacity signals suggest the soft gate; reserved or slow-
/// recovery signals suggest the long lock; mixed or silent signal nothing.
/// The caller shows this as a line beside the dropdown and only applies it
/// when the author picks it. Mirrored in `realismTypes.ts`; both pinned.
String? suggestRecoveryPreset({
  required List<String> intimateInto,
  List<String> intimateNotInto = const [],
}) {
  final into = intimateInto.join(' · ').toLowerCase();
  final not = intimateNotInto.join(' · ').toLowerCase();
  final multi = [
    'multi-orgasm',
    'multi orgasm',
    'multiple orgasm',
    'insatiable',
    'always ready',
    'always up for',
    'high sex drive',
    'high libido',
    'very sexual',
    'again and again',
    'no refractory',
    'no cooldown',
    'recovers fast',
    'recovers quickly',
    'recovers in minutes',
    'go again',
    'endless',
    'non-stop',
    'nonstop',
    'all day long',
  ].any(into.contains);
  final reserved = [
    'slow to warm',
    'takes a while',
    'takes some time',
    'takes me a while',
    'low sex drive',
    'low libido',
    'hardly ever',
    'rarely',
    'rare ',
    'delicate',
    'slow burn',
    'hard to arouse',
    'once in a while',
    'after a long',
    'easily over',
    'quick to fade',
  ].any((k) => into.contains(k) || not.contains(k));
  if (multi && !reserved) return 'none';
  if (reserved && !multi) return 'long';
  return null;
}

/// The suggestion line the creator surfaces under the preset dropdown
/// (plan: "the author confirms, never silent", and it must say plainly what
/// the fixed presets do to the personality judge). Null = nothing to say.
String? recoverySuggestionLine(String? suggestionKey) {
  if (suggestionKey == null) return null;
  final label = kRecoveryPresets
      .firstWhere((p) => p.key == suggestionKey)
      .label;
  return 'Your intimacy notes read like "$label" may fit them — pick it '
      'above if you agree. Any preset except Auto or "Lock, length by '
      'personality" overrides the personality judge with a fixed length '
      'or a fixed window.';
}

/// The plain-English "resolves to" line under the block: the kind AND the
/// length this card's settings actually produce (plan PR 2 UI). Since PR 3
/// the soft gate is real physics — arousal stays up, a tenderness window
/// halves touch gains, peaks cost more within the hour — and the line says
/// what the engine does, nothing it does not.
String recoveryResolvesLine(RecoveryProfile profile, String sex) {
  final kind = profile.resolvedMode(sex);
  final minutes = profile.recoveryMinutes;
  final String kindLine;
  if (profile.recoveryMode == kRecoveryModeAuto) {
    final by = switch (normalizeCharacterSex(sex)) {
      kSexFemale => 'soft gate (card says female)',
      kSexMale => 'hard lock (card says male)',
      kSexOther => 'hard lock (sex not female — chosen here to change)',
      _ => 'hard lock (no structured sex — today\'s behavior)',
    };
    kindLine = 'Auto → $by';
  } else if (kind == kRecoveryModeSoft) {
    kindLine =
        'Soft gate — arousal stays up; a ~15 min tenderness window '
        'halves touch gains, and each peak within the hour costs more';
  } else {
    kindLine = 'Hard lock';
  }
  final length = minutes != null
      ? '$minutes min fixed (replaces the judge\'s number)'
      : 'length by the personality judge';
  return 'Resolves to: $kindLine — $length.';
}

/// The clock-off hint (decision 1's quantization floor, Needs precedent):
/// "With Passage of Time off, 90 min ≈ 6 replies (15 min per reply)."
String recoveryClockOffHint(int? minutes) => minutes == null
    ? 'With Passage of Time off, each reply of theirs is 15 minutes — '
          'the judge\'s length becomes that many replies.'
    : 'With Passage of Time off, $minutes min ≈ '
          '${(minutes + kRefractoryMinutesPerTurnHint - 1) ~/ kRefractoryMinutesPerTurnHint} '
          'replies (15 min per reply).';

/// The soft gate's replacement for the minutes slider and its clock-off
/// hint (maintainer ruling 2026-10-18): the gate has no length — decision 4
/// fixes its tenderness window at ~15 story minutes — so a slider parked
/// at the neutral 90 showed a number the mode never uses, and dragging it
/// into Custom silently flipped the card to a hard lock. Mirrored in
/// `realismTypes.ts`; both suites pin the same words.
String recoverySoftGateHint() =>
    'This gate has no length to set — the ~15 min tenderness window is '
    'fixed, about one reply of theirs with Passage of Time off.';

/// Local copy of the refractory's 15-minutes-per-reply constant — the
/// models layer does not import services. The reply-hint math is two lines;
/// an import cycle for it would be worse than the duplication, and both the
/// service test and this file's guard pin the number.
const int kRefractoryMinutesPerTurnHint = 15;
