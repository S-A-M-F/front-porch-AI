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

import 'package:front_porch_ai/models/hf_model.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Why a repo's file list came back empty.
enum HfFilesProblem {
  /// 401/403: the repo is gated (licence to accept) or needs a token.
  gated,

  /// 404: the repo is gone or renamed.
  notFound,

  /// Anything else: offline, a server error, an unreadable reply.
  network,
}

/// One thing a user can download from a repo: a quant that may be split
/// into several `-0000k-of-0000n.gguf` parts, or a vision projector.
class HfQuant {
  HfQuant._(this.parts, this.partsExpected);

  /// The parts in order; a single-file quant has one.
  final List<HFModelFile> parts;

  /// How many parts the names say there are, or null for a single file.
  final int? partsExpected;

  static final RegExp _split = RegExp(
    r'-(\d{5})-of-(\d{5})\.gguf$',
    caseSensitive: false,
  );

  HFModelFile get primary => parts.first;
  String get repoId => primary.repoId;

  /// The first part's repo path; identifies the quant to the web relay.
  String get id => primary.filename;

  bool get isProjector => primary.isProjector;
  bool get isSplit => partsExpected != null;

  /// False when the repo is missing a part (an upload still in progress).
  bool get isComplete => partsExpected == null || parts.length == partsExpected;

  int get sizeBytes => parts.fold(0, (s, f) => s + f.sizeBytes);

  /// The basename without the part suffix, e.g. `Llama-3.3-70B-Q8_0.gguf`.
  String get title => primary.basename.replaceFirst(_split, '.gguf');

  List<String> get localFilenames => [for (final f in parts) f.localFilename];

  /// The whole quant as one file, for size and VRAM estimates.
  HFModelFile get combined => HFModelFile(
    filename: primary.filename,
    downloadUrl: primary.downloadUrl,
    sizeBytes: sizeBytes,
    repoId: repoId,
    paramCountB: primary.paramCountB,
    architecture: primary.architecture,
    sha256: isSplit ? null : primary.sha256,
  );

  /// Groups a repo's GGUF files into quants, smallest first. Parts are
  /// matched by their shared name; anything else stands alone.
  static List<HfQuant> group(List<HFModelFile> files) {
    final singles = <HfQuant>[];
    final splits = <String, List<HFModelFile>>{};
    final expected = <String, int>{};
    for (final f in files) {
      final m = _split.firstMatch(f.filename);
      if (m == null) {
        singles.add(HfQuant._([f], null));
        continue;
      }
      final key = f.filename.substring(0, m.start);
      splits.putIfAbsent(key, () => []).add(f);
      expected[key] = int.parse(m.group(2)!);
    }
    final quants = [
      ...singles,
      for (final e in splits.entries)
        HfQuant._(
          List.of(e.value)..sort((a, b) => a.filename.compareTo(b.filename)),
          expected[e.key],
        ),
    ];
    return quants..sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));
  }

  /// The largest complete model quant that fits [vramMb] at [contextSize]
  /// with headroom, else the largest that fits tightly, else null. Null too
  /// when the VRAM is unknown (0).
  static HfQuant? bestFit(
    List<HfQuant> quants, {
    required int vramMb,
    required int contextSize,
  }) {
    if (vramMb <= 0) return null;
    HfQuant? best(VramFitStatus wanted) {
      HfQuant? pick;
      for (final q in quants) {
        if (q.isProjector || !q.isComplete) continue;
        final needed = VramEstimator.estimateForHfFile(
          file: q.combined,
          contextSize: contextSize,
        );
        final status = VramEstimator.getFitStatus(
          neededMb: needed,
          availableMb: vramMb,
        );
        if (status == wanted &&
            (pick == null || q.sizeBytes > pick.sizeBytes)) {
          pick = q;
        }
      }
      return pick;
    }

    return best(VramFitStatus.fits) ?? best(VramFitStatus.tight);
  }
}
