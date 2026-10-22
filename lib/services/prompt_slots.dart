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

// The two Settings prompt slots (one-to-one Fallback, Group) over one shared
// pool of saved prompts. Built-ins never sit in the pool: a slot reaches them
// only through Reset to built-in, so no Save can overwrite one. Shared by
// desktop Settings and the web relay so both name a slot's state alike.

import 'package:front_porch_ai/services/chat_service.dart'
    show
        defaultApiSystemPrompt,
        defaultGroupSystemPrompt,
        defaultKoboldSystemPrompt;
import 'package:front_porch_ai/services/storage/settings/generation_settings.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// A prompt FPAI ships. Read-only: a slot can be reset to it, never save
/// over it.
class BuiltInPrompt {
  const BuiltInPrompt(this.label, this.text);

  final String label;
  final String text;

  Map<String, String> toJson() => {'label': label, 'text': text};
}

/// The name the app seeds into the saved pool on first run. Left untouched it
/// is the built-in by another name, so the pool hides it.
const String kSeededPromptName = 'Immersive Roleplay';

const List<BuiltInPrompt> kOneToOneBuiltIns = [
  BuiltInPrompt(kSeededPromptName, GenerationSettings.defaultSystemPrompt),
  BuiltInPrompt('API default', defaultApiSystemPrompt),
  BuiltInPrompt('KoboldCpp default', defaultKoboldSystemPrompt),
];

/// The group slot stores blank for its built-in; [kGroupBuiltIn] is what the
/// box shows then.
const BuiltInPrompt kGroupBuiltIn = BuiltInPrompt(
  'Group default',
  defaultGroupSystemPrompt,
);

/// Where a slot's text came from, for its badge.
sealed class PromptSlotStatus {
  const PromptSlotStatus();
}

final class OnBuiltInPrompt extends PromptSlotStatus {
  const OnBuiltInPrompt(this.label);
  final String label;
}

final class OnSavedPrompt extends PromptSlotStatus {
  const OnSavedPrompt(this.name, {required this.edited});
  final String name;

  /// The box no longer matches the saved copy; Save would update it.
  final bool edited;
}

final class OnCustomPrompt extends PromptSlotStatus {
  const OnCustomPrompt();
}

enum PromptSlot { oneToOne, group }

extension PromptSlotStore on PromptSlot {
  List<BuiltInPrompt> get builtIns => switch (this) {
    PromptSlot.oneToOne => kOneToOneBuiltIns,
    PromptSlot.group => const [kGroupBuiltIn],
  };

  /// The text the slot's box shows. A blank group slot shows the built-in
  /// group prompt it stands for.
  String shownText(StorageService storage) {
    final g = storage.generationSettings;
    return switch (this) {
      PromptSlot.oneToOne => g.systemPrompt,
      PromptSlot.group =>
        g.groupSystemPrompt.trim().isEmpty
            ? kGroupBuiltIn.text
            : g.groupSystemPrompt,
    };
  }

  Future<void> writeText(StorageService storage, String text) {
    final g = storage.generationSettings;
    return switch (this) {
      PromptSlot.oneToOne => g.setSystemPrompt(text),
      PromptSlot.group => g.setGroupSystemPrompt(storedGroupText(text)),
    };
  }

  String? savedName(StorageService storage) => switch (this) {
    PromptSlot.oneToOne => storage.presetSettings.oneToOneSlotName,
    PromptSlot.group => storage.presetSettings.groupSlotName,
  };

  Future<void> writeSavedName(StorageService storage, String? name) =>
      switch (this) {
        PromptSlot.oneToOne => storage.presetSettings.setOneToOneSlotName(name),
        PromptSlot.group => storage.presetSettings.setGroupSlotName(name),
      };

  PromptSlotStatus status(StorageService storage) => promptSlotStatus(
    slot: this,
    text: shownText(storage),
    name: savedName(storage),
    saved: storage.presetSettings.savedPrompts,
  );
}

/// The group built-in, or a cleared box, is stored blank.
String storedGroupText(String text) =>
    text.trim().isEmpty || text == kGroupBuiltIn.text ? '' : text;

/// The user's own saved prompts: the pool minus an untouched seed copy.
List<Map<String, String>> userSavedPrompts(List<Map<String, String>> saved) => [
  for (final p in saved)
    if (!(p['name'] == kSeededPromptName &&
        p['content'] == GenerationSettings.defaultSystemPrompt))
      p,
];

PromptSlotStatus promptSlotStatus({
  required PromptSlot slot,
  required String text,
  required String? name,
  required List<Map<String, String>> saved,
}) {
  final named = name == null
      ? null
      : userSavedPrompts(saved).where((p) => p['name'] == name).firstOrNull;
  if (named != null && named['content'] == text) {
    return OnSavedPrompt(name!, edited: false);
  }
  for (final b in slot.builtIns) {
    if (b.text == text) return OnBuiltInPrompt(b.label);
  }
  if (named != null) return OnSavedPrompt(name!, edited: true);
  return const OnCustomPrompt();
}
