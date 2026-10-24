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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/hf_repo_files.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// The phone's view of a repo's files: one entry per quant (split parts
/// joined), with the same fit line and Best fit the desktop card shows.
/// `filename`, `sizeBytes`, `repoId` and `quant` keep their old meaning for
/// an older PWA; `filename` is the first part's path, which the download
/// route resolves to the whole quant.
class HfFilesView {
  HfFilesView._();

  static Map<String, dynamic> toJson(
    HfFilesResult listed, {
    required int vramMb,
    required int contextSize,
  }) {
    final quants = HfQuant.group(listed.files);
    final best = HfQuant.bestFit(
      [
        for (final q in quants)
          if (!q.isProjector) q,
      ],
      vramMb: vramMb,
      contextSize: contextSize,
    );
    return {
      'files': [
        for (final q in quants)
          _quant(q, best: identical(q, best), vramMb, contextSize),
      ],
      'problem': listed.problem?.name,
    };
  }

  static Map<String, dynamic> _quant(
    HfQuant q,
    int vramMb,
    int contextSize, {
    required bool best,
  }) {
    final needed = VramEstimator.estimateForHfFile(
      file: q.combined,
      contextSize: contextSize,
    );
    final fit = vramMb > 0
        ? VramEstimator.getFitStatus(neededMb: needed, availableMb: vramMb)
        : null;
    return {
      'filename': q.id,
      'title': q.title,
      'sizeBytes': q.sizeBytes,
      'repoId': q.repoId,
      'quant': q.primary.quantType.name,
      'parts': q.parts.length,
      'complete': q.isComplete,
      'kind': q.isProjector ? 'projector' : 'model',
      'vramMb': needed,
      'fit': fit?.name ?? 'unknown',
      'fitText':
          fit?.description(needed, vramMb) ?? 'VRAM not detected — fit unknown',
      'bestFit': best,
    };
  }
}
