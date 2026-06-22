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

// Shared, timer-free service doubles for provider-backed widget goldens.
//
// The real services are unsuitable for static pixel goldens: a real LLMProvider
// builds a KoboldService whose readiness probe schedules a recurring timer, so
// `pumpAndSettle` never returns. These doubles construct nothing and implement
// only the surface the widgets actually read (everything else throws via
// noSuchMethod), following the established `_Fake*` pattern in `test/ui/`.

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';

/// A timer-free, IO-free [LLMProvider] double. Exposes the backend-type surface
/// screens read (e.g. ReviewAvatarPanel checks `activeBackend`) without
/// constructing any backend service.
class FakeLLMProvider extends ChangeNotifier implements LLMProvider {
  FakeLLMProvider({this.activeBackend = BackendType.kobold});

  @override
  final BackendType activeBackend;

  @override
  bool get isLocal => activeBackend == BackendType.kobold;

  @override
  bool get hasManagedProcess =>
      activeBackend == BackendType.kobold ||
      activeBackend == BackendType.pseudoRemote;

  @override
  bool get hasAnyManagedProcessRunning => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// A `ChatService` double for sidebar/chat/overlay goldens. `ChatService` is a
/// large god class, so this implements only the surface a rendered widget reads
/// and grows as new surfaces are covered; everything else throws via
/// noSuchMethod. Sub-services (e.g. [timeService]) are seeded deterministically.
class FakeChatService extends ChangeNotifier implements ChatService {
  FakeChatService({
    this.realismEnabled = true,
    this.isGenerating = false,
    String timeOfDay = 'evening',
    int dayCount = 3,
    int startDayOfWeek = 1,
  }) {
    _time = TimeService(
      onNotify: () {},
      onSaveChat: () async {},
      onSetPendingRealismMetadata: (_, _) {},
      onNudgePatchLastMessageRealismState: (_, _) {},
    )..loadTimeScalars(
        timeOfDay: timeOfDay,
        dayCount: dayCount,
        startDayOfWeek: startDayOfWeek,
        passageOfTimeEnabled: true,
      );
  }

  late final TimeService _time;

  @override
  final bool realismEnabled;

  @override
  final bool isGenerating;

  @override
  TimeService get timeService => _time;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
