// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// A root change with no old root (asked for before the settings finished
// loading, which is every test that builds a StorageService and sets a
// temp root at once) used to build its sources as `Directory('tools')`,
// `Directory('models')`, … — relative paths, so the process's working
// directory — copy them to the new root and delete them. Under
// `flutter test` that was the repo's own tools/ folder; on a desktop launch
// it could be a home folder. No old root means nothing to move.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/storage/root_relocation.dart';

void main() {
  test(
    'no old root: nothing in the working directory is moved or deleted',
    () async {
      final cwd = Directory.systemTemp.createTempSync('fpai_cwd_');
      final newRoot = Directory.systemTemp.createTempSync('fpai_new_root_');
      final previous = Directory.current;
      addTearDown(() {
        Directory.current = previous;
        cwd.deleteSync(recursive: true);
        newRoot.deleteSync(recursive: true);
      });
      final bystander = File(p.join(cwd.path, 'tools', 'preflight.sh'))
        ..createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh\n');
      Directory.current = cwd;

      expect(await relocateRootDirectories(null, newRoot.path), isNull);

      expect(bystander.existsSync(), isTrue, reason: 'the cwd is not a root');
      expect(
        Directory(p.join(newRoot.path, 'tools')).existsSync(),
        isFalse,
        reason: 'nothing was copied in',
      );
    },
  );
}
