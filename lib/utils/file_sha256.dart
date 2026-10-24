// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:crypto/crypto.dart';

/// Lowercase hex SHA-256 of the file at [path], read as a stream so a
/// multi-gigabyte model never sits in memory.
Future<String> fileSha256(String path) async {
  final digest = await sha256.bind(File(path).openRead()).first;
  return digest.toString();
}
