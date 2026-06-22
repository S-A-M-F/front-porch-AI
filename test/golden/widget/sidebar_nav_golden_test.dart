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

@Tags(['golden'])
@TestOn('linux')
library;

// Widget pixel goldens for the app-level navigation Sidebar widget
// (lib/ui/widgets/sidebar.dart).
//
// Sidebar reads two providers at build time:
//   AppState    — Provider.of<AppState>(context) → selectedIndex
//   UpdateService — Consumer<UpdateService> → version text + updateAvailable
//
// FakeAppState and FakeUpdateService (from support/fakes.dart) supply both.
//
// The Sidebar Column contains a Spacer(), which requires a bounded height
// constraint. Wrapping in SizedBox(height: 700) before pumpGolden provides
// the bound — the Scaffold body constrains the box, and the Spacer can
// distribute the remaining height correctly.
//
// Nav callback buttons (Navigator.push, url_launcher) are never invoked
// during a static golden — they fire only on tap.
//
// Cases:
//   sidebar_home     — selectedIndex 0 (Home highlighted)
//   sidebar_settings — selectedIndex 3 (Settings highlighted)
//   sidebar_update   — selectedIndex 0 with updateAvailable=true (badge shown)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/services/update_service.dart';
import 'package:front_porch_ai/ui/widgets/sidebar.dart';

import '../support/creator_test_support.dart';
import '../support/fakes.dart';
import '../support/golden_app.dart';

Widget _sidebarTree({
  int selectedIndex = 0,
  bool updateAvailable = false,
}) {
  final appState = FakeAppState(selectedIndex: selectedIndex);
  final updateService = FakeUpdateService(updateAvailable: updateAvailable);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppState>.value(value: appState),
      ChangeNotifierProvider<UpdateService>.value(value: updateService),
    ],
    // SizedBox constrains height so the Column's Spacer has a bounded extent.
    child: const SizedBox(
      width: 250,
      height: 700,
      child: Sidebar(),
    ),
  );
}

void main() {
  setupPathProviderMock();

  testWidgets('Sidebar — Home selected (index 0)', (tester) async {
    await expectThemedGoldens(
      tester,
      child: _sidebarTree(),
      group: 'sidebar_nav',
      name: 'sidebar_home',
      surface: const Size(290, 740),
    );
  });

  testWidgets('Sidebar — Settings selected (index 3)', (tester) async {
    await expectThemedGoldens(
      tester,
      child: _sidebarTree(selectedIndex: 3),
      group: 'sidebar_nav',
      name: 'sidebar_settings',
      surface: const Size(290, 740),
    );
  });

  testWidgets('Sidebar — update available badge', (tester) async {
    await expectThemedGoldens(
      tester,
      child: _sidebarTree(updateAvailable: true),
      group: 'sidebar_nav',
      name: 'sidebar_update_badge',
      surface: const Size(290, 740),
    );
  });
}
