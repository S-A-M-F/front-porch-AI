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

import 'package:flutter/material.dart';

/// What the wizard builds a world from. The steps, the shelf and the
/// review are the same either way; only the Book step's second card and
/// the words change (docs/design/world-from-character.md §5).
enum WorldWizardSource { wiki, character }

extension WorldWizardSourceX on WorldWizardSource {
  bool get isCharacter => this == WorldWizardSource.character;

  String get title => switch (this) {
    WorldWizardSource.wiki => 'World from Wiki',
    WorldWizardSource.character => 'World from Character',
  };

  IconData get icon => switch (this) {
    WorldWizardSource.wiki => Icons.menu_book_outlined,
    WorldWizardSource.character => Icons.person_outline,
  };

  /// The Book step's one-line blurb under "The book".
  String get bookBlurb => switch (this) {
    WorldWizardSource.wiki =>
      'Name the world, pick its wiki, say how deep to dig. Scout proposes '
          'a shelf of cards from the wiki\'s index, not one card per page.',
    WorldWizardSource.character =>
      'Name the world, pick the character and one of their chats, say how '
          'deep to dig. The chat is skimmed into an index first; the scout '
          'proposes a shelf of cards from that, not one card per message.',
  };

  /// The Book step's resting subtitle in the title bar.
  String get restingSubtitle => switch (this) {
    WorldWizardSource.wiki =>
      'A whole place, with its people and its weather, from a wiki you name',
    WorldWizardSource.character =>
      'A whole place, with its people and its weather, from a character '
          'and one of their chats',
  };

  /// The route the web app opens for the same wizard.
  String get webRoute => switch (this) {
    WorldWizardSource.wiki => '/worlds/from-wiki',
    WorldWizardSource.character => '/worlds/from-character',
  };
}
