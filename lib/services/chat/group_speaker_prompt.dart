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

/// FPAI's own group rules for a normal (non-Director) group turn. Like
/// [kDirectorSceneRules] they ride after whichever base prompt won, so a
/// custom Group System Prompt only restyles the cast. No formatting words:
/// style belongs to the base the user may replace.
const String kGroupSceneRules =
    '[Group scene]\n'
    'This is a group roleplay with {{user}}. Each reply is written by one '
    'character, named at the end of the prompt. Write only that character: '
    'never write lines, actions or thoughts for anyone else, {{user}} '
    'included. React to what the others just said, without putting words '
    'in their mouths.';

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

/// A group's base prompt with the mode's FPAI rules appended:
/// [kDirectorSceneRules] while [directing], [kGroupSceneRules] otherwise.
String withGroupSceneRules(String systemPrompt, {required bool directing}) =>
    '$systemPrompt\n\n${directing ? kDirectorSceneRules : kGroupSceneRules}';

/// Full-cast roll call for the system head. Same bytes every speaker.
/// [visitorNames] (soft members) are marked so the model knows who is
/// passing through.
String buildGroupRosterLine({
  required List<String> memberNames,
  required String userName,
  bool observerMode = false,
  Set<String> visitorNames = const {},
}) {
  final names = [
    for (final n in memberNames)
      if (_safeName(n).isNotEmpty)
        visitorNames.contains(n) ? '${_safeName(n)} (visitor)' : _safeName(n),
  ];
  if (!observerMode) {
    final user = _safeName(userName);
    if (user.isNotEmpty) names.add(user);
  }
  if (names.isEmpty) return '';
  return 'Also present: ${names.join(', ')}.';
}

/// Everyone the speaker must not write for: the other members, plus the
/// user unless they are directing from outside the scene.
List<String> groupTurnOthers({
  required List<String> otherMemberNames,
  required String userName,
  bool observerMode = false,
}) {
  final others = <String>[
    for (final n in otherMemberNames)
      if (_safeName(n).isNotEmpty) _safeName(n),
  ];
  if (!observerMode) {
    final user = _safeName(userName);
    if (user.isNotEmpty) others.add(user);
  }
  return others;
}

String _turnNote(String head, String speaker, List<String> others) {
  final ban = others.isEmpty
      ? ''
      : ' Do NOT write, speak, or narrate anything for ${others.join(' or ')}.';
  return '[$head Reply ONLY as $speaker: their own dialogue, actions, and '
      'thoughts.$ban]\n';
}

/// Identity line for a soft group member (tier lite).
String buildLiteGroupTurnNote({
  required String speakerName,
  required List<String> otherMemberNames,
  required String userName,
  bool observerMode = false,
}) {
  final speaker = _safeName(speakerName);
  return _turnNote(
    'SCENE GUEST TURN. You are $speaker, a visitor in this scene.',
    speaker,
    groupTurnOthers(
      otherMemberNames: otherMemberNames,
      userName: userName,
      observerMode: observerMode,
    ),
  );
}

/// Identity line for a full group member.
String buildSpeakerTurnNote({
  required String speakerName,
  required List<String> otherMemberNames,
  required String userName,
  bool observerMode = false,
}) {
  final speaker = _safeName(speakerName);
  return _turnNote(
    'GROUP TURN. You are $speaker.',
    speaker,
    groupTurnOthers(
      otherMemberNames: otherMemberNames,
      userName: userName,
      observerMode: observerMode,
    ),
  );
}

/// Continue's guard in a group: the partial below is [speakerName]'s alone,
/// and nobody in [others] may speak in the extension.
String groupContinueRule({
  required String speakerName,
  required List<String> others,
}) {
  final speaker = _safeName(speakerName);
  final ban = others.isEmpty ? 'anyone else' : others.join(' or ');
  return '\n[CRITICAL RULE: The text below is an incomplete reply from '
      '$speaker only. ONLY continue this exact reply, in $speaker\'s voice '
      'and perspective. NEVER write any dialogue, actions, thoughts or '
      'narration for $ban. NEVER add speaker labels or switch characters. '
      'Stop if it would need someone else to speak.]\n';
}

/// `{name}'s Persona: {personality}` — speaker only.
String buildSpeakerPersonaLine({
  required String name,
  required String personality,
}) {
  return "${_safeName(name)}'s Persona: $personality";
}

/// The speaker's example dialogue, framed so it cannot pass for the
/// newest lines of the chat it sits next to. `<START>` separators are
/// dropped: the transcript has its own.
String buildSpeakerExamplesBlock({
  required String name,
  required String examples,
}) {
  final lines = [
    for (final l in examples.split('\n'))
      if (l.trim().toUpperCase() != '<START>') l,
  ];
  final body = lines.join('\n').trim();
  if (body.isEmpty) return '';
  return '[How ${_safeName(name)} talks (example only, not part of this '
      'scene):\n$body]\n';
}

/// The speaker's own instructions: the group override or the card's
/// system prompt, then the card's post-history instructions.
String buildSpeakerInstructionsBlock({
  required String name,
  String instructions = '',
  String postHistory = '',
}) {
  final parts = [
    if (instructions.trim().isNotEmpty) instructions.trim(),
    if (postHistory.trim().isNotEmpty) postHistory.trim(),
  ];
  if (parts.isEmpty) return '';
  return '[Instructions for ${_safeName(name)}]\n${parts.join('\n')}\n';
}

/// One group turn card, after the transcript: this turn's hidden notes,
/// then who speaks and how. Starts on its own line so it never glues onto
/// the last message.
String buildGroupTurnCard({
  required String notes,
  required String turnNote,
  required String personaLine,
  String examplesBlock = '',
  String instructionsBlock = '',
}) {
  final buf = StringBuffer('\n')
    ..write(notes)
    ..write(turnNote)
    ..writeln(personaLine)
    ..write(examplesBlock)
    ..write(instructionsBlock);
  return buf.toString();
}
