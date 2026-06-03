// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

/// Structured result from the consolidated needs impact evaluation (Proposal A
/// semantics + declarative rules + modifiers pipeline in NeedsImpactEvaluator).
///
/// Deltas are the net changes to apply (after base table + modifiers).
/// startAfterglow / suppression / crash drive the erotic "net positive" buffers
/// in NeedsSimulation (preserving afterglow/lust-haze/post-crash behavior).
/// fulfillments drive restore only on *completed* clear acts (per existing
/// fulfillment contract).
/// detectedActivities / reason / intensity for logs, chips, debug, and future
/// injection context. intensity also used for crash duration scaling (climax path).
class NeedsImpact {
  final Map<String, int> deltas;
  final bool startAfterglow;
  final int? afterglowTurns;
  final int? suppressionTurns;
  final int? crashTurns;
  final Map<String, bool>? fulfillments;
  final String? reason;
  final int? intensity;
  final List<String> detectedActivities;

  const NeedsImpact({
    required this.deltas,
    this.startAfterglow = false,
    this.afterglowTurns,
    this.suppressionTurns,
    this.crashTurns,
    this.fulfillments,
    this.reason,
    this.intensity,
    this.detectedActivities = const <String>[],
  });

  @override
  String toString() =>
      'NeedsImpact(deltas: $deltas, startAfterglow: $startAfterglow, '
      'intensity: $intensity, reason: $reason, activities: $detectedActivities)';
}
