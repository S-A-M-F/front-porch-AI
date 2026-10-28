// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// World from Character: the short-chat floor, the mode tiles and the relay
// payloads, as docs/design/world-from-character.md §3.3 and §3.5 state them.
// Twin of test/services/world_from_wiki/world_from_character_source_test.dart.

import { describe, expect, it } from 'vitest';
import {
  WORLD_BUILD_MODES,
  WORLD_CHARACTER_SCOUT_STAGES,
  characterDepthOptions,
  defaultModeFor,
  modeOptions,
  parseChatSourceRows,
  worldCharacterScoutStageOf,
  worldChatLengthChip,
  worldChatLengthWarning,
  worldChatRowsFor,
  worldSourceBody,
} from './worldFromWiki';

describe('the short-chat floor', () => {
  it('chips a chat under 40 as too short and under 100 as short', () => {
    expect(worldChatLengthChip(14)).toBe('too short to skim');
    expect(worldChatLengthChip(39)).toBe('too short to skim');
    expect(worldChatLengthChip(40)).toBe('short chat');
    expect(worldChatLengthChip(99)).toBe('short chat');
    expect(worldChatLengthChip(100)).toBe('');
    expect(worldChatLengthChip(0)).toBe('');
  });

  it('warns at 39, 99 and 199 messages and says nothing at 200', () => {
    expect(worldChatLengthWarning(39, 'factsOnly', 0)).toContain('almost nothing to skim');
    expect(worldChatLengthWarning(99, 'factsOnly', 0)).toContain('Facts only will give a thin shelf');
    expect(worldChatLengthWarning(99, 'creative', 0)).toContain('invents around it');
    expect(worldChatLengthWarning(199, 'factsOnly', 1)).toContain('Quick is the better fit');
    expect(worldChatLengthWarning(199, 'factsOnly', 0)).toBeNull();
    expect(worldChatLengthWarning(200, 'factsOnly', 1)).toBeNull();
    expect(worldChatLengthWarning(0, 'factsOnly', 1)).toBeNull();
  });

  it('counts in messages and says turns in brackets', () => {
    expect(worldChatLengthWarning(76, 'faithful', 0)).toContain('76 messages (about 38 turns)');
  });
});

describe('the three modes', () => {
  it('ships Facts only, Faithful and Creative, each saying what it does and never does', () => {
    expect(WORLD_BUILD_MODES.map((m) => m.value)).toEqual(['factsOnly', 'faithful', 'creative']);
    for (const m of WORLD_BUILD_MODES) {
      expect(m.does.length).toBeGreaterThan(20);
      expect(m.never.length).toBeGreaterThan(20);
    }
  });

  it('defaults to Facts only with a chat and Creative for Card only', () => {
    expect(defaultModeFor(true)).toBe('factsOnly');
    expect(defaultModeFor(false)).toBe('creative');
  });

  it("reads the relay's mode list and falls back to the shipped one", () => {
    expect(modeOptions(undefined)).toBe(WORLD_BUILD_MODES);
    expect(modeOptions([{ value: 'faithful', label: 'F', does: 'd', never: 'n' }, { value: 'nope' }])).toEqual([
      { value: 'faithful', label: 'F', does: 'd', never: 'n' },
    ]);
  });
});

describe('the chat depth tiles and stages', () => {
  it('offers Quick and Full only, never Deep', () => {
    expect(characterDepthOptions(undefined).map((d) => d.value)).toEqual([0, 1]);
    expect(
      characterDepthOptions([
        { value: 0, label: 'Quick', cards: 15 },
        { value: 1, label: 'Full', cards: 30 },
        { value: 2, label: 'Deep', cards: 200 },
      ]).map((d) => d.value),
    ).toEqual([0, 1]);
  });

  it('puts the Skim first and shifts the wiki stages after it', () => {
    expect(WORLD_CHARACTER_SCOUT_STAGES[0]).toBe('Skim the chat');
    expect(worldCharacterScoutStageOf('Skimming the chat · part 2 of 5 · messages 51 to 100…')).toBe(0);
    expect(worldCharacterScoutStageOf('Index ready: 31 named things. The scout reads the index, not the chat.')).toBe(0);
    expect(worldCharacterScoutStageOf('Reading the shelf as a roleplay world…')).toBe(2);
  });
});

describe('the relay payloads', () => {
  it('sends no source field for a wiki and a character source otherwise', () => {
    expect(worldSourceBody({ source: 'wiki', characterId: 'c1', sessionId: 's1', mode: 'factsOnly', copyCardLore: false })).toEqual({});
    expect(
      worldSourceBody({ source: 'character', characterId: 'c1', sessionId: '', mode: 'creative', copyCardLore: true }),
    ).toEqual({ source: { kind: 'character', characterId: 'c1', mode: 'creative', copyCardLore: true } });
    expect(
      worldSourceBody({ source: 'character', characterId: 'c1', sessionId: 's1', mode: 'factsOnly', copyCardLore: false })
        .source,
    ).toMatchObject({ sessionId: 's1' });
  });

  it('reads the story picker rows and keeps one character\'s chats, newest first as sent', () => {
    const rows = parseChatSourceRows({
      chats: [
        { character_id: 'c1', character_name: 'Ines', session_id: 's1', session_name: 'Winter', date: '2026-10-12', message_count: 212 },
        { character_id: 'c2', character_name: 'Tomas', session_id: 's2', session_name: 'Docks', date: '2026-09-01', message_count: 40 },
        { character_id: 'c1', character_name: 'Ines', session_id: '', message_count: 3 },
      ],
    });
    expect(rows).toHaveLength(2);
    expect(worldChatRowsFor(rows, 'c1').map((r) => r.session_id)).toEqual(['s1']);
  });
});
