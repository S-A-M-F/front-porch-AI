// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

/// Lightweight summary of key GGUF architecture values needed for VRAM/layer
/// calculations. Returned by `getModelArchitectureInfo`.
class GGUFModelInfo {
  final int nLayers;
  final int nHeads;
  final int nKvHeads;
  final int nEmbd;
  final int kvBytesPerToken; // FP16 assumption, sum across all layers

  // MoE fields
  final int? expertCount;
  final int? expertUsedCount;
  final int? expertFfnDim; // expert_feed_forward_length
  final int? expertSharedFfnDim; // expert_shared_feed_forward_length
  final int? ffnDim; // feed_forward_length (dense FFN)
  final int? nVocab; // tokenizer.ggml.tokens array length
  final int? slidingWindow; // {arch}.sliding_window

  // Per-layer attention fields (for mixed-attention models like Gemma 4)
  final List<int>? nKvHeadsPerLayer; // per-layer head_count_kv array
  final int? keyLength;               // {arch}.attention.key_length (full-attn head dim)
  final int? swaHeadDim;              // SWA head dim (gemma4: keyLength/2)
  final int? fullAttentionInterval;   // {arch}.full_attention_interval (qwen)
  final int? leadingDenseBlockCount;  // {arch}.leading_dense_block_count (lfm)

  const GGUFModelInfo({
    required this.nLayers,
    required this.nHeads,
    required this.nKvHeads,
    required this.nEmbd,
    required this.kvBytesPerToken,
    this.expertCount,
    this.expertUsedCount,
    this.expertFfnDim,
    this.expertSharedFfnDim,
    this.ffnDim,
    this.nVocab,
    this.slidingWindow,
    this.nKvHeadsPerLayer,
    this.keyLength,
    this.swaHeadDim,
    this.fullAttentionInterval,
    this.leadingDenseBlockCount,
  });

  bool get isMoe => (expertCount ?? 0) > 1;

  int get headDim => nHeads > 0 ? (nEmbd / nHeads).round() : 0;

  /// Whether this model has mixed KV head counts across layers
  /// (e.g. some layers use full attention with more heads, others use SWA).
  bool get hasMixedKvHeads {
    final perLayer = nKvHeadsPerLayer;
    if (perLayer == null || perLayer.length != nLayers) return false;
    if (perLayer.length <= 1) return false;
    final first = perLayer.first;
    return perLayer.any((v) => v != first);
  }

  /// Ratio of active (attention + used experts) to total params per layer.
  double get activeWeightRatio {
    if (!isMoe) return 1.0;
    final e = nEmbd.toDouble();
    final h = nHeads.toDouble();
    final kh = nKvHeads.toDouble();
    final ec = expertCount!.toDouble();
    final eu = expertUsedCount!.toDouble();
    final ef = (expertFfnDim ?? 0).toDouble();
    final df = (ffnDim ?? 0).toDouble();
    final se = (expertSharedFfnDim ?? 0).toDouble();

    final attn = 2 * e * e * (1 + kh / h);
    final denseFfn = 3 * e * df;
    final sharedExp = 3 * e * se;
    final router = e * ec;
    final expFfn = 3 * e * ef;

    final total = attn + denseFfn + sharedExp + router + ec * expFfn;
    final active = attn + denseFfn + sharedExp + router + eu * expFfn;
    if (total <= 0) return 1.0;
    return active / total;
  }

  /// GPU-resident weight ratio when MoE experts are offloaded to CPU.
  ///
  /// Includes attention weights, shared experts, router, used experts,
  /// AND non-layer tensors (embeddings + output projection) that always
  /// stay on GPU regardless of expert offloading.
  double get gpuWeightRatioWhenOffloadingExperts {
    if (!isMoe) return 1.0;
    final e = nEmbd.toDouble();
    final h = nHeads.toDouble();
    final kh = nKvHeads.toDouble();
    final ec = expertCount!.toDouble();
    final eu = expertUsedCount!.toDouble();
    final ef = (expertFfnDim ?? 0).toDouble();
    final df = (ffnDim ?? 0).toDouble();
    final se = (expertSharedFfnDim ?? 0).toDouble();
    final v = (nVocab ?? 0).toDouble();

    final attn = 2 * e * e * (1 + kh / h);
    final denseFfn = 3 * e * df;
    final sharedExp = 3 * e * se;
    final router = e * ec;
    final expFfn = 3 * e * ef;

    // Non-layer tensors always on GPU: token embeddings + lm_head
    final embeddingParams = 2 * v * e;

    final perLayerTotal = attn + denseFfn + sharedExp + router + ec * expFfn;
    final activePerLayer = attn + denseFfn + sharedExp + router + eu * expFfn;

    final total = nLayers * perLayerTotal + embeddingParams;
    final gpuResident = nLayers * activePerLayer + embeddingParams;

    if (total <= 0) return 1.0;
    return gpuResident / total;
  }

  /// Pragmatic approximation of bytes per layer for the model weights.
  /// This is what most client-side solvers (and what KoboldCPP effectively uses
  /// for uniform GGUF quants) rely on: total file size divided by layer count
  /// (after a small header/metadata allowance).
  int estimateBytesPerLayer(int fileSizeBytes) {
    if (nLayers <= 0) return 0;
    // Rough allowance for header + non-layer tensors (embeddings, norms, etc.)
    const int headerOverhead = 50 * 1024 * 1024; // 50 MB conservative
    final weightsSize = (fileSizeBytes - headerOverhead).clamp(
      0,
      fileSizeBytes,
    );
    return (weightsSize / nLayers).round();
  }
}

/// A lightweight parser to extract architectural parameters from GGUF files
/// without loading the full model tensors into memory.
class GGUFParser {
  /// Extracts the exact number of bytes required per token for KV cache.
  /// Uses a basic heuristic for KV cache calculation assuming FP16 precision.
  ///
  /// Formula: 2 (Key, Value) * 2 (bytes for fp16) * layers * kv_heads * head_dim
  /// `head_dim` typically equals (embedding_length / head_count).
  static Future<int?> getKvCacheBytesPerToken(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;

    final raf = await file.open(mode: FileMode.read);
    try {
      // Read the first 4 MB, which usually contains all the metadata.
      // We don't need to read the massive tensor data.
      final bytes = await raf.read(4 * 1024 * 1024);
      final data = ByteData.sublistView(bytes);
      int offset = 0;

      // Magic "GGUF"
      if (bytes.length < 4) return null;
      final magic = utf8.decode(bytes.sublist(0, 4), allowMalformed: true);
      if (magic != 'GGUF') return null;
      offset += 4;

      // Version (uint32)
      if (offset + 4 > bytes.length) return null;
      final version = data.getUint32(offset, Endian.little);
      offset += 4;
      if (version > 3) return null; // We support up to version 3

      // Tensor Count (uint64)
      if (offset + 8 > bytes.length) return null;
      offset += 8;

      // KV Count (uint64)
      if (offset + 8 > bytes.length) return null;
      final kvCount = data.getUint64(offset, Endian.little);
      offset += 8;

      final meta = <String, dynamic>{};

      for (var i = 0; i < kvCount; i++) {
        if (offset + 8 > bytes.length) break;
        final keyLen = data.getUint64(offset, Endian.little);
        offset += 8;

        if (offset + keyLen > bytes.length) break;
        final key = utf8.decode(
          bytes.sublist(offset, offset + keyLen.toInt()),
          allowMalformed: true,
        );
        offset += keyLen.toInt();

        if (offset + 4 > bytes.length) break;
        final valType = data.getUint32(offset, Endian.little);
        offset += 4;

        dynamic value;
        switch (valType) {
          case 0: // uint8
            if (offset + 1 > bytes.length) break;
            value = data.getUint8(offset);
            offset += 1;
            break;
          case 1: // int8
            if (offset + 1 > bytes.length) break;
            value = data.getInt8(offset);
            offset += 1;
            break;
          case 2: // uint16
            if (offset + 2 > bytes.length) break;
            value = data.getUint16(offset, Endian.little);
            offset += 2;
            break;
          case 3: // int16
            if (offset + 2 > bytes.length) break;
            value = data.getInt16(offset, Endian.little);
            offset += 2;
            break;
          case 4: // uint32
            if (offset + 4 > bytes.length) break;
            value = data.getUint32(offset, Endian.little);
            offset += 4;
            break;
          case 5: // int32
            if (offset + 4 > bytes.length) break;
            value = data.getInt32(offset, Endian.little);
            offset += 4;
            break;
          case 6: // float32
            if (offset + 4 > bytes.length) break;
            value = data.getFloat32(offset, Endian.little);
            offset += 4;
            break;
          case 7: // bool
            if (offset + 1 > bytes.length) break;
            value = data.getUint8(offset) != 0;
            offset += 1;
            break;
          case 8: // string
            if (offset + 8 > bytes.length) break;
            final strLen = data.getUint64(offset, Endian.little).toInt();
            offset += 8;
            if (offset + strLen > bytes.length) break;
            value = utf8.decode(
              bytes.sublist(offset, offset + strLen),
              allowMalformed: true,
            );
            offset += strLen;
            break;
          case 9: // array
            if (offset + 4 > bytes.length) break;
            final arrType = data.getUint32(offset, Endian.little);
            offset += 4;
            if (offset + 8 > bytes.length) break;
            final arrLen = data.getUint64(offset, Endian.little).toInt();
            offset += 8;

            if (key.endsWith('.attention.head_count_kv') &&
                arrType >= 0 && arrType <= 6) {
              final values = <int>[];
              for (var j = 0; j < arrLen; j++) {
                int v;
                if (arrType == 0) { v = data.getUint8(offset); offset += 1; }
                else if (arrType == 1) { v = data.getInt8(offset); offset += 1; }
                else if (arrType == 2) { v = data.getUint16(offset, Endian.little); offset += 2; }
                else if (arrType == 3) { v = data.getInt16(offset, Endian.little); offset += 2; }
                else if (arrType == 4) { v = data.getUint32(offset, Endian.little); offset += 4; }
                else if (arrType == 5) { v = data.getInt32(offset, Endian.little); offset += 4; }
                else { v = (data.getFloat32(offset, Endian.little) as num).toInt(); offset += 4; }
                values.add(v);
              }
              value = values;
            } else if (arrType == 8) {
              // string array
              for (var j = 0; j < arrLen; j++) {
                if (offset + 8 > bytes.length) break;
                final strLen = data.getUint64(offset, Endian.little).toInt();
                offset += 8;
                offset += strLen;
              }
            } else {
              int size = 0;
              if (arrType == 0 || arrType == 1 || arrType == 7) {
                size = 1;
              } else if (arrType == 2 || arrType == 3) {
                size = 2;
              } else if (arrType >= 4 && arrType <= 6) {
                size = 4;
              } else if (arrType >= 10 && arrType <= 12) {
                size = 8;
              }
              offset += arrLen * size;
            }
            break;
          case 10: // uint64
            if (offset + 8 > bytes.length) break;
            value = data.getUint64(offset, Endian.little);
            offset += 8;
            break;
          case 11: // int64
            if (offset + 8 > bytes.length) break;
            value = data.getInt64(offset, Endian.little);
            offset += 8;
            break;
          case 12: // float64
            if (offset + 8 > bytes.length) break;
            value = data.getFloat64(offset, Endian.little);
            offset += 8;
            break;
        }

        // We only care about a few specific keys, storing others is a waste of memory
        if (value != null &&
            (key == 'general.architecture' ||
                key.endsWith('.block_count') ||
                key.endsWith('.attention.head_count') ||
                key.endsWith('.attention.head_count_kv') ||
                key.endsWith('.embedding_length'))) {
          meta[key] = value;
        }
      }

      final arch = meta['general.architecture'] as String? ?? 'llama';
      final dynamic nLayersDyn = meta['$arch.block_count'];
      final dynamic nHeadsDyn = meta['$arch.attention.head_count'];
      final dynamic nKvHeadsDyn =
          meta['$arch.attention.head_count_kv'] ?? nHeadsDyn;
      final dynamic nEmbdDyn = meta['$arch.embedding_length'];

      if (nLayersDyn != null && nHeadsDyn != null && nEmbdDyn != null) {
        // Convert to int safely (might be uint32 or uint64 depending on file)
        final int nLayers = nLayersDyn is int
            ? nLayersDyn
            : int.tryParse(nLayersDyn.toString()) ?? 0;
        final int nHeads = nHeadsDyn is int
            ? nHeadsDyn
            : int.tryParse(nHeadsDyn.toString()) ?? 0;
        final int nEmbd = nEmbdDyn is int
            ? nEmbdDyn
            : int.tryParse(nEmbdDyn.toString()) ?? 0;

        // Handle per-layer head_count_kv array
        int nKvHeads;
        List<int>? nKvHeadsPerLayer;
        if (nKvHeadsDyn is List<int>) {
          nKvHeadsPerLayer = nKvHeadsDyn;
          nKvHeads = nKvHeadsDyn.reduce((a, b) => a > b ? a : b);
        } else {
          nKvHeadsPerLayer = null;
          nKvHeads = nKvHeadsDyn is int
              ? nKvHeadsDyn
              : int.tryParse(nKvHeadsDyn.toString()) ?? nHeads;
        }

        if (nHeads > 0) {
          final headDim = nEmbd / nHeads;
          // Handle per-layer head_count_kv array for mixed-attention models
          int totalBytes;
          if (nKvHeadsPerLayer != null && nKvHeadsPerLayer.length == nLayers) {
            totalBytes = 0;
            for (final kv in nKvHeadsPerLayer) {
              final effectiveKv = kv > 0 ? kv : nHeads;
              totalBytes += (4 * effectiveKv * headDim).round();
            }
          } else {
            // Uniform case: 4 bytes per parameter (2 for Key, 2 for Value in FP16)
            totalBytes = (4 * nLayers * nKvHeads * headDim).round();
          }
          return totalBytes;
        }
      }
    } catch (e) {
      // Fall through to return null if file is unreadable or truncated
      print('Failed to parse GGUF KV data: $e');
    } finally {
      await raf.close();
    }
    return null;
  }

  /// Returns richer architectural metadata from the GGUF file, including the
  /// real layer count (`nLayers` / block_count). This is the preferred API
  /// for any code that needs to solve for GPU layers (Auto-Configure, VRAM
  /// gauges, etc.).
  ///
  /// Returns null if the file cannot be read or is not a supported GGUF.
  static Future<GGUFModelInfo?> getModelArchitectureInfo(
    String filePath,
  ) async {
    final file = File(filePath);
    if (!await file.exists()) return null;

    final raf = await file.open(mode: FileMode.read);
    try {
      final bytes = await raf.read(16 * 1024 * 1024);
      final data = ByteData.sublistView(bytes);
      int offset = 0;

      if (bytes.length < 4) return null;
      final magic = utf8.decode(bytes.sublist(0, 4), allowMalformed: true);
      if (magic != 'GGUF') return null;
      offset += 4;

      if (offset + 4 > bytes.length) return null;
      final version = data.getUint32(offset, Endian.little);
      offset += 4;
      if (version > 3) return null;

      if (offset + 8 > bytes.length) return null;
      offset += 8; // tensor count
      if (offset + 8 > bytes.length) return null;
      final kvCount = data.getUint64(offset, Endian.little);
      offset += 8;

      final meta = <String, dynamic>{};

      for (var i = 0; i < kvCount; i++) {
        if (offset + 8 > bytes.length) break;
        final keyLen = data.getUint64(offset, Endian.little);
        offset += 8;

        if (offset + keyLen > bytes.length) break;
        final key = utf8.decode(
          bytes.sublist(offset, offset + keyLen.toInt()),
          allowMalformed: true,
        );
        offset += keyLen.toInt();

        if (offset + 4 > bytes.length) break;
        final valType = data.getUint32(offset, Endian.little);
        offset += 4;

        dynamic value;
        // (Same compact switch as getKvCacheBytesPerToken — kept in sync for now)
        switch (valType) {
          case 0:
            value = data.getUint8(offset);
            offset += 1;
            break;
          case 1:
            value = data.getInt8(offset);
            offset += 1;
            break;
          case 2:
            value = data.getUint16(offset, Endian.little);
            offset += 2;
            break;
          case 3:
            value = data.getInt16(offset, Endian.little);
            offset += 2;
            break;
          case 4:
            value = data.getUint32(offset, Endian.little);
            offset += 4;
            break;
          case 5:
            value = data.getInt32(offset, Endian.little);
            offset += 4;
            break;
          case 6:
            value = data.getFloat32(offset, Endian.little);
            offset += 4;
            break;
          case 7:
            value = data.getUint8(offset) != 0;
            offset += 1;
            break;
          case 8:
            final strLen = data.getUint64(offset, Endian.little).toInt();
            offset += 8;
            value = utf8.decode(
              bytes.sublist(offset, offset + strLen),
              allowMalformed: true,
            );
            offset += strLen;
            break;
          case 9:
            final arrType = data.getUint32(offset, Endian.little);
            offset += 4;
            final arrLen = data.getUint64(offset, Endian.little).toInt();
            offset += 8;
            if (key == 'tokenizer.ggml.tokens') {
              value = arrLen; // vocab size = array length
              for (var j = 0; j < arrLen; j++) {
                final l = data.getUint64(offset, Endian.little).toInt();
                offset += 8 + l;
              }
            } else if (key.endsWith('.attention.head_count_kv') &&
                arrType >= 0 && arrType <= 6) {
              final values = <int>[];
              for (var j = 0; j < arrLen; j++) {
                int v;
                if (arrType == 0) { v = data.getUint8(offset); offset += 1; }
                else if (arrType == 1) { v = data.getInt8(offset); offset += 1; }
                else if (arrType == 2) { v = data.getUint16(offset, Endian.little); offset += 2; }
                else if (arrType == 3) { v = data.getInt16(offset, Endian.little); offset += 2; }
                else if (arrType == 4) { v = data.getUint32(offset, Endian.little); offset += 4; }
                else if (arrType == 5) { v = data.getInt32(offset, Endian.little); offset += 4; }
                else { v = (data.getFloat32(offset, Endian.little) as num).toInt(); offset += 4; }
                values.add(v);
              }
              value = values;
            } else {
              if (arrType == 8) {
                for (var j = 0; j < arrLen; j++) {
                  final l = data.getUint64(offset, Endian.little).toInt();
                  offset += 8 + l;
                }
              } else {
                int size = 0;
                if (arrType == 0 || arrType == 1 || arrType == 7) {
                  size = 1;
                } else if (arrType == 2 || arrType == 3) {
                  size = 2;
                } else if (arrType >= 4 && arrType <= 6) {
                  size = 4;
                } else if (arrType >= 10 && arrType <= 12) {
                  size = 8;
                }
                offset += arrLen * size;
              }
            }
            break;
          case 10:
            value = data.getUint64(offset, Endian.little);
            offset += 8;
            break;
          case 11:
            value = data.getInt64(offset, Endian.little);
            offset += 8;
            break;
          case 12:
            value = data.getFloat64(offset, Endian.little);
            offset += 8;
            break;
        }

        if (value != null &&
            (key == 'general.architecture' ||
                key == 'tokenizer.ggml.tokens' ||
                key.endsWith('.block_count') ||
                key.endsWith('.attention.head_count') ||
                key.endsWith('.attention.head_count_kv') ||
                key.endsWith('.attention.key_length') ||
                key.endsWith('.attention.value_length') ||
                key.endsWith('.embedding_length') ||
                key.endsWith('.expert_count') ||
                key.endsWith('.expert_used_count') ||
                key.endsWith('.expert_feed_forward_length') ||
                key.endsWith('.expert_shared_feed_forward_length') ||
                key.endsWith('.feed_forward_length') ||
                key.endsWith('.sliding_window') ||
                key.endsWith('.full_attention_interval') ||
                key.endsWith('.leading_dense_block_count'))) {
          meta[key] = value;
        }
      }

      final arch = meta['general.architecture'] as String? ?? 'llama';
      final dynamic nLayersDyn = meta['$arch.block_count'];
      final dynamic nHeadsDyn = meta['$arch.attention.head_count'];
      final dynamic nKvHeadsDyn =
          meta['$arch.attention.head_count_kv'] ?? nHeadsDyn;
      final dynamic nEmbdDyn = meta['$arch.embedding_length'];
      final dynamic expertCountDyn = meta['$arch.expert_count'];
      final dynamic expertUsedDyn = meta['$arch.expert_used_count'];
      final dynamic expertFfnDyn = meta['$arch.expert_feed_forward_length'];
      final dynamic expertSharedFfnDyn =
          meta['$arch.expert_shared_feed_forward_length'];
      final dynamic ffnDimDyn = meta['$arch.feed_forward_length'];
      final dynamic slidingWindowDyn = meta['$arch.sliding_window'];
      final dynamic nVocabDyn = meta['tokenizer.ggml.tokens'];
      final dynamic keyLengthDyn = meta['$arch.attention.key_length'];
      final dynamic fullAttentionIntervalDyn =
          meta['$arch.full_attention_interval'];
      final dynamic leadingDenseBlockCountDyn =
          meta['$arch.leading_dense_block_count'];

      if (nLayersDyn != null && nHeadsDyn != null && nEmbdDyn != null) {
        int _toInt(dynamic v) =>
            v is int ? v : int.tryParse(v.toString()) ?? 0;

        List<int> _toIntList(dynamic v) {
          if (v is List<int>) return v;
          if (v is List) {
            // Handle non-uniform arrays (Gemma 4, LFM, etc.)
            if (v.every((e) => e is int)) return List<int>.from(v);
            // Handle value 0 = default (use head_count)
            return v.map((e) {
              final i = e is int ? e : int.tryParse(e.toString()) ?? 0;
              return i;
            }).toList();
          }
          return [];
        }

        final int nLayers = _toInt(nLayersDyn);
        final int nHeads = _toInt(nHeadsDyn);

        // Handle per-layer head_count_kv array
        final List<int>? nKvHeadsPerLayer;
        int nKvHeads;
        if (nKvHeadsDyn is List) {
          final list = _toIntList(nKvHeadsDyn);
          if (list.length == nLayers) {
            nKvHeadsPerLayer = list;
            // Use max (for full-attention layers) as the scalar representative
            nKvHeads = list.reduce((a, b) => a > b ? a : b);
          } else {
            nKvHeadsPerLayer = null;
            nKvHeads = _toInt(nKvHeadsDyn);
          }
        } else {
          nKvHeadsPerLayer = null;
          nKvHeads = nKvHeadsDyn != null ? _toInt(nKvHeadsDyn) : nHeads;
        }

        final int nEmbd = _toInt(nEmbdDyn);

        // Use key_length as head_dim if available (more accurate for KV cache)
        final int headDim;
        final int keyLength;
        if (keyLengthDyn != null) {
          keyLength = _toInt(keyLengthDyn);
          headDim = keyLength;
        } else {
          keyLength = nHeads > 0 ? (nEmbd / nHeads).round() : 0;
          headDim = (nEmbd / nHeads).round();
        }

        // Compute kvBytesPerToken with per-layer awareness
        final int kvBytesPerToken;
        if (nKvHeadsPerLayer != null && nKvHeadsPerLayer.length == nLayers) {
          // Sum across layers: 4 * n_kv_heads * head_dim per layer
          int total = 0;
          for (final kv in nKvHeadsPerLayer) {
            final effectiveKv = kv > 0 ? kv : nHeads; // 0 = use head_count
            total += (4 * effectiveKv * headDim).round();
          }
          kvBytesPerToken = total;
        } else {
          kvBytesPerToken = (4 * nLayers * nKvHeads * headDim).round();
        }

        final int? expertCount =
            expertCountDyn != null ? _toInt(expertCountDyn) : null;
        final int? expertUsedCount =
            expertUsedDyn != null ? _toInt(expertUsedDyn) : null;
        final int? expertFfnDim =
            expertFfnDyn != null ? _toInt(expertFfnDyn) : null;
        final int? expertSharedFfnDim =
            expertSharedFfnDyn != null ? _toInt(expertSharedFfnDyn) : null;
        final int? ffnDim =
            ffnDimDyn != null ? _toInt(ffnDimDyn) : null;
        final int? slidingWindow =
            slidingWindowDyn != null ? _toInt(slidingWindowDyn) : null;
        final int? nVocab =
            nVocabDyn != null ? _toInt(nVocabDyn) : null;
        final int? fullAttentionInterval =
            fullAttentionIntervalDyn != null
                ? _toInt(fullAttentionIntervalDyn)
                : null;
        final int? leadingDenseBlockCount =
            leadingDenseBlockCountDyn != null
                ? _toInt(leadingDenseBlockCountDyn)
                : null;

        if (nHeads > 0) {
          // SWA head dim: gemma4 uses key_length / 2; other archs use full dim
          final int? swaHeadDim;
          if (arch.toLowerCase().contains('gemma4') && headDim > 0) {
            swaHeadDim = headDim ~/ 2;
          } else {
            swaHeadDim = null;
          }

          return GGUFModelInfo(
            nLayers: nLayers,
            nHeads: nHeads,
            nKvHeads: nKvHeads,
            nEmbd: nEmbd,
            kvBytesPerToken: kvBytesPerToken,
            expertCount: expertCount,
            expertUsedCount: expertUsedCount,
            expertFfnDim: expertFfnDim,
            expertSharedFfnDim: expertSharedFfnDim,
            ffnDim: ffnDim,
            slidingWindow: slidingWindow,
            nVocab: nVocab,
            nKvHeadsPerLayer: nKvHeadsPerLayer,
            keyLength: headDim > 0 ? headDim : null,
            swaHeadDim: swaHeadDim,
            fullAttentionInterval: fullAttentionInterval,
            leadingDenseBlockCount: leadingDenseBlockCount,
          );
        }
      }
    } catch (e) {
      print('Failed to parse GGUF architecture info: $e');
    } finally {
      await raf.close();
    }
    return null;
  }
}
