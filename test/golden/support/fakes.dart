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

import 'package:front_porch_ai/database/database.dart' show Objective;
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/chat/chaos_mode_service.dart';
import 'package:front_porch_ai/services/chat/needs_simulation.dart';
import 'package:front_porch_ai/services/chat/nsfw_service.dart';
import 'package:front_porch_ai/services/chat/relationship_service.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/tts_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';

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
    this.authorNote = '',
    this.authorNoteStrength = 3,
    this.summary = '',
    this.summaryLastIndex = 0,
    this.summaryPaused = false,
    this.isSummaryGenerating = false,
    this.needsSimEnabled = true,
    this.characterEmotion = 'neutral',
    this.emotionIntensity = 'moderate',
    this.characterEvolutionCount = 0,
    this.activeCharacter,
    List<ChatMessage> messages = const [],
    String timeOfDay = 'evening',
    int dayCount = 3,
    int startDayOfWeek = 1,
    int shortTermBond = 120,
    int longTermBond = 60,
    int trustLevel = 40,
    Map<String, int> needs = const {
      'hunger': 70,
      'bladder': 55,
      'energy': 80,
      'social': 45,
      'fun': 65,
      'hygiene': 75,
      'comfort': 60,
    },
  }) : _messages = messages {
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
    _nsfw = NsfwService(
      getGroupInt: (_, _) => 0,
      getGroupValue: (_, _) => null,
      setGroupValue: (_, _, _) {},
    );
    _chaos = ChaosModeService(
      onNotify: () {},
      onSaveChat: () async {},
      onSetPendingRealismMetadata: (_, _) {},
    );
    _needs = NeedsSimulation(
      onNotify: () {},
      onSaveChat: () async {},
      getTimeOfDay: () => timeOfDay,
      getRealismEnabled: () => realismEnabled,
      getArousalLevel: () => 0,
      getNsfwCooldownEnabled: () => false,
      getCooldownTurnsRemaining: () => 0,
      getObserverMode: () => false,
      getCurrentSpeakerIdForRealism: () => '',
      getIsGroupNonObserverMode: () => false,
      getGroupNeeds: (_) => {},
      setGroupNeeds: (_, _) {},
      getEnjoysLowHygiene: () => false,
      getNeedsSimEnabled: () => needsSimEnabled,
      setArousalLevel: (_) {},
    )..restoreFromSnapshot(needs);
    _relationship = RelationshipService(
      onNotify: () {},
      onSaveChat: () async {},
      getIsGroupActive: () => false,
      getObserverMode: () => false,
      getGroupCharacterCount: () => 0,
      getShouldTrackInterCharacterRelationships: () => false,
      getCurrentSpeakerIdForRealism: () => '',
      getCurrentGroupMemberIds: () => <String>{},
      getOtherGroupMemberIds: (_) => const [],
      getOtherGroupMemberIdToLowerName: (_) => const {},
      getRecentExchangeLowerText: () => '',
      getMessageCount: () => 0,
      getIsGroupRealismActive: () => false,
      getGroupAffectionScore: (_, {int defaultValue = 0}) => defaultValue,
      setGroupAffectionScore: (_, _) {},
      getGroupLongTermScore: (_, {int defaultValue = 0}) => defaultValue,
      setGroupLongTermScore: (_, _) {},
      getGroupTrustLevel: (_, {int defaultValue = 0}) => defaultValue,
      setGroupTrustLevel: (_, _) {},
      getGroupFixation: (_, {String defaultValue = ''}) => defaultValue,
      setGroupFixation: (_, _) {},
      getGroupFixationLifespan: (_, {int defaultValue = 0}) => defaultValue,
      setGroupFixationLifespan: (_, _) {},
      getGroupRelationshipTier: (_, {int defaultValue = 0}) => defaultValue,
      setGroupRelationshipTier: (_, _) {},
      getGroupLongTermTier: (_, {int defaultValue = 0}) => defaultValue,
      setGroupLongTermTier: (_, _) {},
      getGroupSpatialStance: (_, {String defaultValue = ''}) => defaultValue,
      setGroupSpatialStance: (_, _) {},
      getGroupInterCharacterRelationships: (_) => <String, int>{},
      setGroupInterCharacterRelationships: (_, _) {},
    )..loadScalars(
        affectionScore: shortTermBond,
        longTermScore: longTermBond,
        trustLevel: trustLevel,
      );
  }

  final List<ChatMessage> _messages;
  late final TimeService _time;
  late final NsfwService _nsfw;
  late final ChaosModeService _chaos;
  late final NeedsSimulation _needs;
  late final RelationshipService _relationship;

  @override
  final bool realismEnabled;
  @override
  final bool isGenerating;
  @override
  final String authorNote;
  @override
  final int authorNoteStrength;
  @override
  final String summary;
  @override
  final int summaryLastIndex;
  @override
  final bool summaryPaused;
  @override
  final bool isSummaryGenerating;
  @override
  final bool needsSimEnabled;
  @override
  final String characterEmotion;
  @override
  final String emotionIntensity;
  @override
  final int characterEvolutionCount;
  @override
  final CharacterCard? activeCharacter;

  @override
  TimeService get timeService => _time;
  @override
  NsfwService get nsfwService => _nsfw;
  @override
  ChaosModeService get chaosModeService => _chaos;
  @override
  NeedsSimulation get needsSimulation => _needs;
  @override
  RelationshipService get relationshipService => _relationship;

  // 1:1 mode by default (no active group) for the simple sidebar sections.
  @override
  GroupChat? get activeGroup => null;
  @override
  bool get chaosNsfwEnabled => _chaos.chaosNsfwEnabled;

  // Objective surface — empty by default (renders the "propose an objective" UI).
  @override
  Objective? get primaryObjective => null;
  @override
  List<Objective> get secondaryObjectives => const [];
  @override
  bool get isCheckingCompletion => false;

  // Message bubble surface.
  @override
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  @override
  bool get isGroupMode => false;
  @override
  List<CharacterCard> get groupCharacters => const [];
  @override
  int get greetingIndex => 0;
  @override
  bool get isGeneratingActions => false;
  @override
  List<String> get suggestedActions => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// Timer-free [TtsService] double. Exposes only the four getters that
/// [MessageBubble]'s `Consumer2<TtsService, StorageService>` reads at build.
class FakeTtsService extends ChangeNotifier implements TtsService {
  @override
  bool get isSpeaking => false;
  @override
  bool get isGenerating => false;
  @override
  String? get currentMessageId => null;
  @override
  double get generationProgress => 0.0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Empty [UserPersonaService] double. [MessageBubble] uses a
/// `Consumer<UserPersonaService>` to filter personas by sender name; an empty
/// list renders the section as a no-op.
class FakeUserPersonaService extends ChangeNotifier
    implements UserPersonaService {
  @override
  List<UserPersona> get personas => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
