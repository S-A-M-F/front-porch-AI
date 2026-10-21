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

import 'package:front_porch_ai/services/chat/scene_guest_prompt.dart';

String _safeName(String name) => clipGuestCite(name, max: 80);

/// Director Mode's own rules. They ride after whichever base prompt won —
/// the built-in one or a group's custom one — so a custom Group System
/// Prompt restyles the cast without putting {{user}} back in the scene.
/// No formatting words: style belongs to the base the user may replace.
const String kDirectorSceneRules =
    '[Director Mode]\n'
    '{{user}} is directing this scene from outside it and is not a '
    'character in it. No one can see, hear, address, mention or react to '
    '{{user}}.\n'
    'The characters talk to each other. They use each other\'s names, '
    'answer what was just said, and can argue, agree, tease, ask questions, '
    'tell stories or start side conversations.\n'
    'Lines marked [Director: …] and hidden notes from the director say where '
    'the scene should go. Act on them through the characters; never quote '
    'them or mention a director.';

/// [systemPrompt] with [kDirectorSceneRules] appended while [directing],
/// unchanged otherwise.
String withDirectorSceneRules(String systemPrompt, {required bool directing}) =>
    directing ? '$systemPrompt\n\n$kDirectorSceneRules' : systemPrompt;

/// Full-cast roll call for the system head. Same bytes every speaker.
String buildGroupRosterLine({
  required List<String> memberNames,
  required String userName,
  bool observerMode = false,
}) {
  final names = [
    for (final n in memberNames)
      if (_safeName(n).isNotEmpty) _safeName(n),
  ];
  if (!observerMode) {
    final user = _safeName(userName);
    if (user.isNotEmpty) names.add(user);
  }
  if (names.isEmpty) return '';
  return 'Also present: ${names.join(', ')}.';
}

/// Guest-weight slap for a soft group member (tier lite). Same identity
/// switch as a 1:1 Scene Guest — they are not a full realism-bearing member.
String buildLiteGroupTurnNote({
  required String speakerName,
  required List<String> otherMemberNames,
  required String userName,
  bool observerMode = false,
}) {
  final speaker = _safeName(speakerName);
  final others = <String>[
    for (final n in otherMemberNames)
      if (_safeName(n).isNotEmpty) _safeName(n),
  ];
  if (!observerMode) {
    final user = _safeName(userName);
    if (user.isNotEmpty) others.add(user);
  }
  final notClause = others.map((n) => 'You are not $n').join('. ');
  final ban = others.join(' or ');
  final notLine = notClause.isEmpty ? '' : ' $notClause.';
  final banLine = ban.isEmpty
      ? ''
      : ' Do NOT write, speak, or narrate anything for $ban.';
  return '[SCENE GUEST TURN. You are $speaker, a visitor in this group.$notLine\n'
      'Reply ONLY as $speaker: their own dialogue, actions, and thoughts.'
      '$banLine]\n';
}

/// Named identity slap for a full group member (not a Scene Guest).
String buildSpeakerTurnNote({
  required String speakerName,
  required List<String> otherMemberNames,
  required String userName,
  bool observerMode = false,
}) {
  final speaker = _safeName(speakerName);
  final others = <String>[
    for (final n in otherMemberNames)
      if (_safeName(n).isNotEmpty) _safeName(n),
  ];
  if (!observerMode) {
    final user = _safeName(userName);
    if (user.isNotEmpty) others.add(user);
  }
  final notClause = others.map((n) => 'You are not $n').join('. ');
  final ban = others.join(' or ');
  final notLine = notClause.isEmpty ? '' : ' $notClause.';
  final banLine = ban.isEmpty
      ? ''
      : ' Do NOT write, speak, or narrate anything for $ban.';
  return '[GROUP TURN. You are $speaker.$notLine\n'
      'Reply ONLY as $speaker: their own dialogue, actions, and thoughts.'
      '$banLine]\n';
}

/// `{name}'s Persona: {personality}` — speaker only.
String buildSpeakerPersonaLine({
  required String name,
  required String personality,
}) {
  return "${_safeName(name)}'s Persona: $personality";
}
