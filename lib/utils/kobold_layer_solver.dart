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

import 'package:front_porch_ai/utils/gguf_parser.dart';

/// Result of solving for the best GPU layer count for a target context size.
class KoboldLayerRecommendation {
  final int gpuLayers;
  final int contextSize;
  final int nLayers; // real layer count from GGUF (or 0 if unknown)
  final int bytesPerLayer; // estimated bytes per layer for weights
  final int estimatedContextVramMb;
  final int estimatedTotalVramMb;
  final int availableVramMb;
  final String reasoning;

  const KoboldLayerRecommendation({
    required this.gpuLayers,
    required this.contextSize,
    required this.nLayers,
    required this.bytesPerLayer,
    required this.estimatedContextVramMb,
    required this.estimatedTotalVramMb,
    required this.availableVramMb,
    required this.reasoning,
  });
}

/// Pure, deterministic solver that produces GPU layer recommendations
/// designed to achieve functional parity with what KoboldCPP's own loader
/// would select for the same model + target context + hardware.
///
/// The algorithm:
/// 1. Uses real `nLayers` and accurate `kvBytesPerToken` from GGUF metadata
///    when available (via GGUFModelInfo).
/// 2. Computes a pragmatic `bytesPerLayer` = (fileSize - small overhead) / nLayers.
/// 3. Applies KV quantization scaling.
/// 4. Adds a realistic overhead budget (KoboldCPP's compute graph + buffers).
/// 5. Searches (binary search) for the *maximum* gpuLayers value that still fits
///    within the supplied available VRAM (after shared-memory and user adjustments).
///
/// This is the single source of truth that both the Model Settings dialog and
/// the main Settings page should eventually call for the "respect user context"
/// Auto-Configure path.
class KoboldLayerSolver {
  /// Default conservative overhead for KoboldCPP (graph, batch buffers, etc.).
  /// Calibrated from real load logs; can be tuned via [overheadMb] parameter.
  static const int defaultOverheadMb = 1200;

  /// Solves for the highest safe `--gpulayers` value given a target context.
  ///
  /// [fileSizeBytes] — size of the .gguf on disk (best proxy for total weights).
  /// [targetContext] — the user's desired context size (never reduced by this solver).
  /// [availableVramMb] — hardware-reported (or manually overridden) VRAM.
  /// [kvBytesPerToken] — exact value from GGUFModelInfo when available.
  /// [nLayers] — real block_count from GGUF when available.
  /// [kvQuantizationLevel] — 0 = f16, 1 = Q8 (~0.5x), 2 = Q4 (~0.25x).
  /// [overheadMb] — extra headroom for KoboldCPP internals (default 1200 MB).
  /// [isSharedMemory] — applies the usual 60% conservative factor.
  static KoboldLayerRecommendation solve({
    required int fileSizeBytes,
    required int targetContext,
    required int availableVramMb,
    int? kvBytesPerToken,
    int? nLayers,
    int kvQuantizationLevel = 0,
    int overheadMb = defaultOverheadMb,
    bool isSharedMemory = false,
  }) {
    int vram = availableVramMb;

    if (isSharedMemory) {
      vram = (vram * 0.6).round();
    }

    // 1. Context VRAM cost (accurate path preferred)
    double contextVramMb;
    if (kvBytesPerToken != null && kvBytesPerToken > 0) {
      contextVramMb = targetContext * kvBytesPerToken / (1024 * 1024);
    } else {
      // Fallback heuristic (same as the old code for compatibility)
      contextVramMb = targetContext / 1024 * 100.0;
    }

    // Apply KV quant scaling (exact same factors used elsewhere in the app)
    if (kvQuantizationLevel == 1) {
      contextVramMb *= 0.5;
    } else if (kvQuantizationLevel == 2) {
      contextVramMb *= 0.25;
    }

    final contextCost = contextVramMb.round();

    // 2. Layer sizing (the key improvement for parity)
    int effectiveNLayers = nLayers ?? 0;
    int bytesPerLayer = 0;

    if (effectiveNLayers > 0) {
      // Use the pragmatic approximation from GGUFModelInfo
      final dummyInfo = GGUFModelInfo(
        nLayers: effectiveNLayers,
        nHeads: 0,
        nKvHeads: 0,
        nEmbd: 0,
        kvBytesPerToken: 0,
      );
      bytesPerLayer = dummyInfo.estimateBytesPerLayer(fileSizeBytes);
    } else {
      // No architecture data available yet.
      // We cannot do accurate per-layer math.
      // For the "full offload" decision we treat the entire file size as the
      // weight cost (minus small header). This prevents the terrible
      // over-estimation that the old "fileSize / 40" produced on large models.
      bytesPerLayer = 0; // special signal — see search logic below
      effectiveNLayers = 99;
    }

    // 3. Search for the maximum gpuLayers that still fits
    int bestLayers = 0;

    final bool hasRealLayerData = bytesPerLayer > 0;

    if (!hasRealLayerData) {
      // No real layer count — use a safe two-phase approach:
      // a) Check if the *entire* model weights + context + overhead fits.
      //    If yes → recommend full offload (99).
      // b) If not, be conservative on partial offload.
      final fullWeightsCost = ((fileSizeBytes - 50 * 1024 * 1024).clamp(0, fileSizeBytes) / (1024 * 1024)).round();
      final totalForFull = fullWeightsCost + contextCost + overheadMb;

      if (totalForFull <= vram) {
        bestLayers = 99;
      } else {
        // Conservative partial: allow up to roughly 40-50% of the model or a safe low number.
        // This is still better than the old wildly wrong /40 math.
        final safePartial = ((vram - contextCost - overheadMb) * 0.45 * 1024 * 1024 / fileSizeBytes * 99)
            .round()
            .clamp(0, 60);
        bestLayers = safePartial;
      }
    } else {
      // We have real nLayers → do proper binary search
      int low = 0;
      int high = effectiveNLayers.clamp(0, 99);

      while (low <= high) {
        final mid = (low + high) ~/ 2;

        final weightsCost = (bytesPerLayer * mid / (1024 * 1024)).round();
        final total = weightsCost + contextCost + overheadMb;

        if (total <= vram) {
          bestLayers = mid;
          low = mid + 1;
        } else {
          high = mid - 1;
        }
      }
    }

    // Build human-readable reasoning
    final String reasoning;
    if (!hasRealLayerData) {
      if (bestLayers >= 99) {
        reasoning =
            'Full GPU offload possible with $targetContext context '
            '(architecture data not yet loaded — using file size directly).';
      } else if (bestLayers > 0) {
        reasoning =
            'Partial offload (~$bestLayers layers) recommended for $targetContext context '
            '(no layer count available yet; conservative estimate).';
      } else {
        reasoning =
            'CPU-only fallback — even 0 layers + $targetContext context exceeds available VRAM.';
      }
    } else if (bestLayers >= effectiveNLayers.clamp(0, 99)) {
      reasoning =
          'Full GPU offload possible with $targetContext context '
          '($effectiveNLayers layers, ~${(bytesPerLayer / (1024 * 1024)).toStringAsFixed(0)} MB/layer).';
    } else if (bestLayers > 0) {
      reasoning =
          'Partial offload: $bestLayers / $effectiveNLayers layers '
          'to keep $targetContext context within available VRAM.';
    } else {
      reasoning =
          'CPU-only fallback — $targetContext context + model weights exceed '
          'available VRAM even with 0 GPU layers.';
    }

    return KoboldLayerRecommendation(
      gpuLayers: bestLayers,
      contextSize: targetContext,
      nLayers: effectiveNLayers,
      bytesPerLayer: bytesPerLayer,
      estimatedContextVramMb: contextCost,
      estimatedTotalVramMb: (bytesPerLayer * bestLayers / (1024 * 1024)).round() + contextCost + overheadMb,
      availableVramMb: vram,
      reasoning: reasoning,
    );
  }
}