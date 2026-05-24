// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

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

            // Skip the actual array bytes, we don't need them for KV memory calculations
            if (arrType == 8) {
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
        final int nKvHeads = nKvHeadsDyn is int
            ? nKvHeadsDyn
            : int.tryParse(nKvHeadsDyn.toString()) ?? 0;
        final int nEmbd = nEmbdDyn is int
            ? nEmbdDyn
            : int.tryParse(nEmbdDyn.toString()) ?? 0;

        if (nHeads > 0) {
          final headDim = nEmbd / nHeads;
          // 4 bytes per parameter (2 for Key, 2 for Value in FP16/half precision)
          final bytesPerToken = 4 * nLayers * nKvHeads * headDim;
          return bytesPerToken.round();
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
}
