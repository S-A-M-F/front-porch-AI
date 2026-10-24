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
import 'package:front_porch_ai/utils/utils.dart';

/// Pairs a downloaded vision projector with the models downloaded from the
/// same repo, so a vision model works without picking its projector by
/// hand. A model that already has a projector chosen keeps it.
class ProjectorPairing {
  ProjectorPairing._();

  /// Model path → projector path for every completed model task whose repo
  /// also has a completed projector task, skipping models in [existing].
  static Map<String, String> pairs(
    Iterable<DownloadTask> completed, {
    required Map<String, String> existing,
  }) {
    final projectors = <String, String>{};
    for (final t in completed) {
      if (t.repoId != null && GgufSplit.isProjector(t.filename)) {
        projectors[t.repoId!] = t.targetPath;
      }
    }
    return {
      for (final t in completed)
        if (t.repoId != null &&
            projectors.containsKey(t.repoId) &&
            GgufSplit.isListedModel(t.filename) &&
            !existing.containsKey(t.targetPath))
          t.targetPath: projectors[t.repoId]!,
    };
  }
}
