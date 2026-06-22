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

// Golden snapshot of the emotion-classification lookup tables. Character
// expressions are selected from these maps; a silent edit (a remapped nuance,
// a dropped label) would change which avatar/expression a character shows. This
// freezes the full table so such drift is caught in review.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/utils/emotion_labels.dart';

import '../golden_harness.dart';

void main() {
  test('standard labels + emoji + ring color are stable', () {
    final table = {
      for (final label in EmotionLabels.all)
        label: {
          'emoji': EmotionLabels.emoji[label],
          // toString gives a stable ARGB hex; locks the color without importing
          // dart:ui specifics into the golden.
          'ringColor': EmotionLabels.ringColor(label).toString(),
        },
    };
    expectGoldenJson({
      'labels': EmotionLabels.all,
      'detail': table,
      'nullRingColor': EmotionLabels.ringColor(null).toString(),
    }, group: 'emotion', name: 'standard_labels');
  });

  test('nuanced -> standard mapping table is stable', () {
    expectGoldenJson(EmotionLabels.nuancedToStandard,
        group: 'emotion', name: 'nuanced_to_standard');
  });
}
