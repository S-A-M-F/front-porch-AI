// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The write-side rules from the maintainer's world-craft recipe, shared by
// the write prompt and the entry reviewer: chain, don't catalogue (a
// Seireitei card mentions the invasion so Yhwach can fire next); a faction
// or place carries its roster (the Royal Guard is one card that names its
// four, not four pages); keys are doorbells a player would type.

/// How many shelf names ride a prompt, so a card can name its neighbours.
const int kWorldShelfNamesInPrompt = 120;

/// The write prompt's rule.
const String kWorldWriteChainRule =
    'A place or faction (hub) also names one or two other cards from SHELF '
    'it should pull — the war, the king, the district — and the notable '
    'members or landmarks its article gives it, so one card leads to the '
    'next. Keys include the titles and accentless spellings a player would '
    'type ("Your Majesty"; "Kyoraku" and "Kyōraku").';

/// The entry reviewer's rule for the same.
const String kWorldEntryChainRule =
    'A place or faction fails too when it names no other card from SHELF '
    'and none of the members or landmarks its article lists.';

/// The SHELF line a prompt carries; '' when the run has no shelf yet.
String worldShelfLine(List<String> names) => names.isEmpty
    ? ''
    : 'SHELF (the other cards in this world): '
          '${names.take(kWorldShelfNamesInPrompt).join(', ')}\n';
