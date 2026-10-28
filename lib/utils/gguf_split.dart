// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:path/path.dart' as p;

/// Split GGUF models (`name-00001-of-00003.gguf` …) and vision projectors
/// as they sit in the models folder. KoboldCpp loads a split model from
/// its first part and finds the rest beside it, so only part 1 is a model
/// the user picks; a projector is paired with a model, never loaded alone.
class GgufSplit {
  GgufSplit._();

  static final RegExp _part = RegExp(
    r'-(\d{5})-of-(\d{5})\.gguf$',
    caseSensitive: false,
  );

  /// Part 2 or later of a split model.
  static bool isLaterPart(String path) {
    final m = _part.firstMatch(p.basename(path));
    return m != null && int.parse(m.group(1)!) > 1;
  }

  static bool isProjector(String path) =>
      p.basename(path).toLowerCase().contains('mmproj');

  /// Whether the file belongs in the model list.
  static bool isListedModel(String path) =>
      !isLaterPart(path) && !isProjector(path);

  /// Total bytes of a split model's parts that are on disk, given its first
  /// part; a plain file's own size. Missing parts count as nothing.
  static int totalBytes(String firstPart, {int? plainSize}) {
    final m = _part.firstMatch(p.basename(firstPart));
    if (m == null) return plainSize ?? File(firstPart).lengthSync();
    final count = int.parse(m.group(2)!);
    final stem = firstPart.substring(0, firstPart.length - m.group(0)!.length);
    var total = 0;
    for (var i = 1; i <= count; i++) {
      final n = '$i'.padLeft(5, '0');
      final part = File('$stem-$n-of-${m.group(2)}.gguf');
      if (part.existsSync()) total += part.lengthSync();
    }
    return total;
  }
}
