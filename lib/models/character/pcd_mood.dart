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

// The post-coital dysphoria vocabulary (recovery overhaul PR 8): the dial's
// stored values, its roll rates, and the option copy the editors show.
// Lives apart from recovery_profile.dart so that file stays under the
// 500-line ratchet as the profile grows; same library family, exported
// beside it from models.dart.
//
// Copy law: `kPcdOptions` labels are byte-identical with `PCD_OPTIONS` in
// `web_ui/src/components/realism/realismTypes.ts`, and the percent numbers
// are pinned against the rate constants on both sides.

/// Post-coital dysphoria flavor dial. Real and transient (minutes to ~2h),
/// happens after WANTED sex and is not about the partner. The rates are
/// flavor dials, not prevalence: `rare` rolls ~15% of climaxes into the
/// grey beat, `sometimes` ~35%, `off` never.
const String kPcdMoodOff = 'off';
const String kPcdMoodRare = 'rare';
const String kPcdMoodSometimes = 'sometimes';

/// Roll rates per stored mood. Single source: the pass rolls through
/// [RecoveryProfile.pcdRollHit], the UI labels quote these, the web mirror
/// pins them.
const double kPcdRateRare = 0.15;
const double kPcdRateSometimes = 0.35;

/// Lenient parse shared by the card readers and the UI setters: trim,
/// lowercase, anything unknown reads `off` — opt-in by law.
String normalizePcdMood(Object? raw) =>
    switch (raw?.toString().trim().toLowerCase()) {
      kPcdMoodRare => kPcdMoodRare,
      kPcdMoodSometimes => kPcdMoodSometimes,
      _ => kPcdMoodOff,
    };

/// One dropdown entry for the pcd dial. `key` is the stored value. The
/// label is the whole copy — mirrors `PCD_OPTIONS` in `realismTypes.ts`,
/// pinned identical on both sides.
class PcdOption {
  const PcdOption(this.key, this.label);

  final String key;
  final String label;
}

const List<PcdOption> kPcdOptions = [
  PcdOption(kPcdMoodOff, 'Off'),
  // The percent numbers are literals (const bar) — guards pin them
  // against the rate constants, so a label can never drift from the
  // dial it names.
  PcdOption(kPcdMoodRare, 'Rare — a grey drift after some climaxes (~15%)'),
  PcdOption(kPcdMoodSometimes, 'Sometimes — often a grey drift after (~35%)'),
];
