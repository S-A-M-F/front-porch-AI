// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// World from Character on the phone: the Book step's second card lists the
// library, picking a character lists that character's 1:1 chats with the
// short-chat chips, picking a short chat shows the one warning line, the
// mode tiles follow the pick, and Next is "Skim chat" with a chat picked.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../api/client', () => ({
  api: { get, post, avatarUrl: (p: string) => p },
  ApiError: class extends Error {},
}));
vi.mock('../api/ws', () => ({
  ChatSocket: class {
    connect() {}
    close() {}
  },
}));

import { WorldFromWikiPage } from './WorldFromWikiPage';

let container: HTMLDivElement;
let root: Root;

const STATUS = {
  available: true,
  toolsAdvertised: true,
  toolsGate: 'ready',
  savedWikis: [],
  depth: 0,
  sources: ['wiki', 'character'],
};

const CHARACTERS = [
  { id: 'c1', name: 'Ines Calder', hasAvatar: false },
  { id: 'c2', name: 'Tomas Reyes', hasAvatar: false },
];

const CHATS = {
  chats: [
    { character_id: 'c1', character_name: 'Ines Calder', session_id: 's-long', session_name: 'The quarantine winter', date: '2026-10-12T00:00:00Z', message_count: 212 },
    { character_id: 'c1', character_name: 'Ines Calder', session_id: 's-short', session_name: 'First tea', date: '2026-09-02T00:00:00Z', message_count: 76 },
    { character_id: 'c1', character_name: 'Ines Calder', session_id: 's-tiny', session_name: 'Market day', date: '2026-08-30T00:00:00Z', message_count: 14 },
    { character_id: 'c2', character_name: 'Tomas Reyes', session_id: 's-tomas', session_name: 'Docks', date: '2026-09-01T00:00:00Z', message_count: 50 },
  ],
};

async function show() {
  get.mockImplementation((url: string) => {
    if (url.startsWith('/api/worlds/from-wiki/status')) return Promise.resolve(STATUS);
    if (url === '/api/characters') return Promise.resolve(CHARACTERS);
    if (url === '/api/stories/chat-sources') return Promise.resolve(CHATS);
    return Promise.reject(new Error(`unexpected ${url}`));
  });
  await act(async () => {
    root.render(
      createElement(MemoryRouter, null, createElement(WorldFromWikiPage, { source: 'character' })),
    );
  });
  // The library and the chats arrive after the first paint.
  await act(async () => {
    await Promise.resolve();
  });
}

const byId = (id: string) => container.querySelector<HTMLElement>(`[data-testid="${id}"]`);
const next = () =>
  Array.from(container.querySelectorAll('button')).find((b) =>
    /Scout card|Skim chat/.test(b.textContent ?? ''),
  )!;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  get.mockReset();
  post.mockReset();
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('World from Character on the phone', () => {
  it('names itself, lists the library, and locks Next until a character is picked', async () => {
    await show();
    expect(container.querySelector('h2')?.textContent).toContain('World from Character');
    expect(byId('world-source-card')).not.toBeNull();
    expect(byId('world-character-pick-c1')?.textContent).toContain('Ines Calder');
    expect(byId('world-character-pick-c1')?.textContent).toContain('3 chats');
    expect(byId('world-character-pick-c2')?.textContent).toContain('1 chat');
    expect(next().disabled).toBe(true);
    // No wiki tiles on this source.
    expect(container.textContent).not.toContain('The wiki');
  });

  it("picking a character lists that character's chats with the short-chat chips, Card only first", async () => {
    await show();
    await act(async () => {
      byId('world-character-pick-c1')!.click();
    });
    expect(byId('world-character-chat-card-only')).not.toBeNull();
    expect(byId('world-character-chat-s-long')?.textContent).toContain('212 messages');
    expect(byId('world-character-chat-s-short')?.textContent).toContain('short chat');
    expect(byId('world-character-chat-s-tiny')?.textContent).toContain('too short to skim');
    expect(byId('world-character-chat-s-tomas')).toBeNull();
    expect(next().textContent).toContain('Scout card');
    expect(next().disabled).toBe(false);
    // Card only defaults to Creative; the tiles say so.
    expect(byId('world-character-mode-creative')?.getAttribute('aria-checked')).toBe('true');
  });

  it('picking a short chat shows the one warning line and flips the default to Facts only', async () => {
    await show();
    await act(async () => {
      byId('world-character-pick-c1')!.click();
    });
    await act(async () => {
      byId('world-character-chat-s-short')!.click();
    });
    expect(byId('world-character-length-warning')?.textContent).toContain('76 messages (about 38 turns)');
    expect(byId('world-character-length-warning')?.textContent).toContain('Facts only will give a thin shelf');
    expect(byId('world-character-mode-factsOnly')?.getAttribute('aria-checked')).toBe('true');
    expect(next().textContent).toContain('Skim chat');
    // Deep is not offered for a chat.
    expect(byId('world-wiki-depth-2')).toBeNull();
    expect(byId('world-wiki-depth-0')).not.toBeNull();
  });

  it('sends the character source on scout', async () => {
    post.mockResolvedValue({ proposed: [], titles: 0 });
    await show();
    await act(async () => {
      byId('world-character-pick-c1')!.click();
    });
    await act(async () => {
      byId('world-character-chat-s-long')!.click();
    });
    await act(async () => {
      byId('world-character-mode-faithful')!.click();
    });
    await act(async () => {
      next().click();
    });
    expect(post).toHaveBeenCalledWith(
      '/api/worlds/from-wiki/scout',
      expect.objectContaining({
        source: { kind: 'character', characterId: 'c1', sessionId: 's-long', mode: 'faithful', copyCardLore: false },
      }),
    );
  });
});
