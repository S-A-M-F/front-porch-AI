// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Lowercase hex SHA-256 of the file at [path].
///
/// The hashing runs on its own isolate: a model is many gigabytes, and on
/// the UI isolate it froze the window for the minute or more it takes.
/// [onProgress] gets the bytes hashed so far, about every 64 MB.
Future<String> fileSha256(
  String path, {
  void Function(int hashedBytes)? onProgress,
}) async {
  // Progress (int), the digest (String) and an uncaught error ([error,
  // stack]) all arrive on one port.
  final port = ReceivePort();
  await Isolate.spawn(
    _hashFile,
    (path, port.sendPort),
    onError: port.sendPort,
    errorsAreFatal: true,
  );
  try {
    await for (final message in port) {
      switch (message) {
        case int hashed:
          onProgress?.call(hashed);
        case String digest:
          return digest;
        case [final Object error, _]:
          throw FileSystemException('Could not check the file: $error', path);
      }
    }
    throw FileSystemException('The checksum worker stopped', path);
  } finally {
    port.close();
  }
}

const int _block = 4 * 1024 * 1024;
const int _reportEvery = 64 * 1024 * 1024;

/// Isolate entry: hashes the file in 4 MB blocks, posting the byte count
/// now and then and the hex digest at the end.
Future<void> _hashFile((String, SendPort) args) async {
  final (path, out) = args;
  final digest = _DigestSink();
  final input = sha256.startChunkedConversion(digest);
  final file = await File(path).open();
  try {
    final buffer = Uint8List(_block);
    var hashed = 0;
    var nextReport = _reportEvery;
    while (true) {
      final n = await file.readInto(buffer);
      if (n <= 0) break;
      input.add(Uint8List.sublistView(buffer, 0, n));
      hashed += n;
      if (hashed >= nextReport) {
        out.send(hashed);
        nextReport += _reportEvery;
      }
    }
  } finally {
    await file.close();
  }
  input.close();
  out.send(digest.value.toString());
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
