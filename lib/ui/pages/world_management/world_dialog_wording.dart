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

/// The World dialog's copy. A card with a parent is a place inside that
/// world, so it says "place" and names the parent; a top-level card keeps
/// the World wording. Read live from the draft so changing "Part of"
/// re-words the dialog on the next frame.
class WorldDialogWording {
  const WorldDialogWording({
    required this.isCreate,
    this.parentName,
    this.ancestorNames = const [],
    this.inheritedEntries = 0,
  });

  final bool isCreate;

  /// Display name of the draft's parent, or null for a top-level world.
  final String? parentName;

  /// The parent chain nearest-first; their lore reaches this place's chats.
  final List<String> ancestorNames;

  /// Switched-on lore entries across [ancestorNames].
  final int inheritedEntries;

  bool get isPlace => parentName != null;

  String get title {
    if (!isPlace) return isCreate ? 'Create World' : 'Edit World';
    return isCreate ? 'Add a place to $parentName' : 'Edit place';
  }

  /// One line under the title, only while adding a place.
  String? get subtitle => isCreate && isPlace
      ? "It shares $parentName's lore and climate unless you change it below."
      : null;

  String get nameLabel => isPlace ? 'Place name' : 'World Name';
  String get nameHint =>
      isPlace ? 'Enter a name for this place' : 'Enter a name for this world';

  String get descriptionLabel =>
      isPlace ? 'Description' : 'Description (place prose)';
  String get descriptionHint => isPlace
      ? 'What it feels like to stand here — reaches the story when enabled'
      : 'What it feels like to be here — reaches the story when enabled';

  String get saveLabel {
    if (!isCreate) return 'Save Changes';
    return isPlace ? 'Add place' : 'Create World';
  }

  String get savedMessage {
    if (isPlace) return isCreate ? 'Place added' : 'Place updated';
    return isCreate
        ? 'World created successfully'
        : 'World updated successfully';
  }

  String loreTitle(int count) =>
      isPlace ? "This place's lore ($count)" : 'Lorebook Entries ($count)';

  String get loreEmptyTitle =>
      isPlace ? 'No entries for this place yet' : 'No lorebook entries yet';

  String get loreEmptyBody => isPlace
      ? 'Add lore that only matters here, like who runs it or what the locals fear'
      : 'Add entries to define world lore that will be injected into conversations';

  /// Says the parent chain's lore is live here too; null when there is none.
  String? get inheritedLoreLine {
    if (!isPlace || inheritedEntries == 0 || ancestorNames.isEmpty) {
      return null;
    }
    final noun = inheritedEntries == 1 ? 'entry' : 'entries';
    return 'Also active here: $inheritedEntries lore $noun from '
        '${ancestorNames.join(' and ')}. When both books have an entry in '
        "the same group, this place's entry wins.";
  }
}
