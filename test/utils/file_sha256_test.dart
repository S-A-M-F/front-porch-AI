// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The download checksum runs on its own isolate (hashing a model on the UI
// isolate froze the window): its digest must match package:crypto's, it
// must report progress on a big file, and a missing file must fail rather
// than hang.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/utils/file_sha256.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fpai_sha_');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('a file over many blocks hashes the same as package:crypto, with '
      'progress along the way', () async {
    final rng = Random(7);
    final bytes = Uint8List(70 * 1024 * 1024 + 123);
    for (var i = 0; i < bytes.length; i += 4096) {
      bytes[i] = rng.nextInt(256);
    }
    final file = File(p.join(dir.path, 'big.gguf'))..writeAsBytesSync(bytes);

    final seen = <int>[];
    final digest = await fileSha256(file.path, onProgress: seen.add);

    expect(digest, sha256.convert(bytes).toString());
    expect(seen, isNotEmpty);
    expect(seen.last, lessThanOrEqualTo(bytes.length));
  });

  test('a missing file fails instead of hanging', () async {
    await expectLater(
      fileSha256(p.join(dir.path, 'gone.gguf')),
      throwsA(isA<FileSystemException>()),
    );
  }, timeout: const Timeout(Duration(seconds: 20)));
}
