// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Story days cool a journal card too, not only maintenance passes. A card
// from the last scene must not burn at full heat ("the truer guide") two
// weeks of story later just because no pass ran across a skip. Applied at
// read time from the card's own story stamp, so nothing is written: regen,
// swipe and delete rewind the clock, and the heat follows it back.

import 'dart:convert';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/journal_physics.dart';
import 'package:front_porch_ai/services/chat/journal_store.dart';

/// Metadata key: the story day the card was last lived, when that is later
/// than the day it is stamped with (retrieval re-warmed it, or a clock-out
/// crumb whose shift ended after midnight).
const String kJournalLivedDayMeta = 'livedDay';

/// Maintenance passes one story day is worth. A mild card leaves the hot set
/// after a day or two, a strong one after about ten (flashbulb resistance
/// still holds); pinned, ledger and birthday cards never cool.
const int kCoolingPassesPerStoryDay = 3;

/// The story day [card] was last lived: the later of its stamp and
/// [kJournalLivedDayMeta]. Null for unstamped cards.
int? lastLivedDayOf(JournalMemoryData card) {
  final day = JournalStore.stampOf(card).$1;
  if (day == null) return null;
  int? lived;
  final raw = card.metadata;
  if (raw != null && raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        lived = (decoded[kJournalLivedDayMeta] as num?)?.toInt();
      }
    } on FormatException {
      lived = null;
    }
  }
  return lived != null && lived > day ? lived : day;
}

/// [card] as it reads on story day [today]: its heat cooled by
/// [kCoolingPassesPerStoryDay] passes for every story day since it was last
/// lived. Unstamped cards and same-day reads come back unchanged.
JournalMemoryData cooledForStoryDay(JournalMemoryData card, int today) {
  final since = lastLivedDayOf(card);
  if (since == null || today <= since) return card;
  var heat = card.heat;
  final passes = (today - since) * kCoolingPassesPerStoryDay;
  for (var i = 0; i < passes; i++) {
    final next = JournalPhysics.cooledHeat(card.copyWith(heat: heat));
    if (next == heat) break;
    heat = next;
  }
  return heat == card.heat ? card : card.copyWith(heat: heat);
}
