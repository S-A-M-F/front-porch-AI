// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → Backend → HuggingFace token on the desktop: Save writes the
// token once even on a fast double click, the saved token is never shown
// back, and Clear removes it. (The web twin and its step-up live in
// test/services/web/settings_step_up_test.dart.)

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/settings/tabs/backend/hf_token_section.dart';

import '../../helpers/double_tap.dart';

void main() {
  late Directory root;
  late StorageService storage;
  var writes = 0;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fpai_hf_token_ui_');
    storage = StorageService.sandbox(root.path);
    writes = 0;
    storage.addListener(() => writes++);
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    ChangeNotifierProvider<StorageService>.value(
      value: storage,
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: HfTokenSection())),
      ),
    ),
  );

  testWidgets('a double-clicked Save writes the token once and does not '
      'show it again', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), '  hf_abc123  ');
    await doubleTapNoFrame(
      tester,
      find.widgetWithText(ElevatedButton, 'Save token'),
    );
    await tester.pumpAndSettle();

    expect(writes, 1);
    expect(storage.backendSettings.hf.token, 'hf_abc123');
    expect(find.text('hf_abc123'), findsNothing);
    expect(find.text('Clear token'), findsOneWidget);
  });

  testWidgets('Clear removes a saved token', (tester) async {
    await storage.backendSettings.hf.setToken('hf_old');
    await pump(tester);
    await tester.tap(find.text('Clear token'));
    await tester.pumpAndSettle();

    expect(storage.backendSettings.hf.hasToken, isFalse);
    expect(find.text('Clear token'), findsNothing);
  });
}
