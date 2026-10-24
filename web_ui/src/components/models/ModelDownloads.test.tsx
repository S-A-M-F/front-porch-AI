// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The HuggingFace browser's "Roleplay" badge: the host marks roleplay-tagged
// repos (and lists them first); the phone shows the same badge the desktop
// card does. Renders the real component; the server's answers are supplied.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../../api/client', () => ({ api: { get, post }, ApiError: class extends Error {} }));

import { ModelDownloads } from './ModelDownloads';

const MODELS = [
  { id: 'ReadyArt/Dark-Scarlett-27B-v3.0-GGUF', name: 'Dark-Scarlett-27B-v3.0-GGUF', author: 'ReadyArt', likes: 40, downloads: 9000, description: null, roleplay: true },
  { id: 'bartowski/gemma-3-27b-it-GGUF', name: 'gemma-3-27b-it-GGUF', author: 'bartowski', likes: 90, downloads: 80000, description: null, roleplay: false },
  // An older host sends no flag at all.
  { id: 'TheBloke/Scarlett-7B-GGUF', name: 'Scarlett-7B-GGUF', author: 'TheBloke', likes: 5, downloads: 700, description: null },
];

let container: HTMLDivElement;
let root: Root;

async function search() {
  get.mockImplementation(async (path: string) =>
    path.startsWith('/api/backend/hf/search')
      ? { models: MODELS }
      : { downloads: [], overallProgress: 0, overallSpeed: 0, activeCount: 0 },
  );
  await act(async () => {
    root.render(
      createElement(ModelDownloads, { query: 'Scarlett', setQuery: () => {}, searchNonce: 1, onError: () => {} }),
    );
  });
}

const rowFor = (name: string) =>
  [...container.querySelectorAll('.hf-row')].find((li) => li.textContent?.includes(name));

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

describe('ModelDownloads roleplay badge', () => {
  it('badges the roleplay tune and nothing else', async () => {
    await search();
    expect(get).toHaveBeenCalledWith('/api/backend/hf/search?q=Scarlett');
    expect(rowFor('Dark-Scarlett-27B')?.querySelector('.hf-rp')?.textContent).toBe('Roleplay');
    expect(rowFor('gemma-3-27b-it')?.querySelector('.hf-rp')).toBeNull();
    expect(rowFor('Scarlett-7B')?.querySelector('.hf-rp')).toBeNull();
    expect(container.querySelectorAll('.hf-rp')).toHaveLength(1);
  });
});

describe('ModelDownloads search filters and stale replies', () => {
  it('sends the chosen filters and drops a reply overtaken by a newer search', async () => {
    let releaseFirst: (v: { models: typeof MODELS }) => void = () => {};
    const replies: string[] = [];
    get.mockImplementation((path: string) => {
      if (!path.startsWith('/api/backend/hf/search')) {
        return Promise.resolve({ downloads: [], overallProgress: 0, overallSpeed: 0, activeCount: 0 });
      }
      replies.push(path);
      // The first search hangs until released; later ones answer at once.
      if (replies.length === 1) return new Promise((res) => (releaseFirst = res));
      return Promise.resolve({ models: [MODELS[1]] });
    });
    await act(async () => {
      root.render(
        createElement(ModelDownloads, { query: 'Scarlett', setQuery: () => {}, searchNonce: 1, onError: () => {} }),
      );
    });

    const rpOnly = container.querySelector<HTMLInputElement>('.hf-rp-only input')!;
    await act(async () => {
      rpOnly.click();
    });
    expect(replies[1]).toBe('/api/backend/hf/search?q=Scarlett&rp=1');

    await act(async () => {
      releaseFirst({ models: MODELS });
    });
    // Only the newer answer (gemma) is on screen; the late first answer was dropped.
    expect(container.querySelectorAll('.hf-row')).toHaveLength(1);
    expect(rowFor('gemma-3-27b-it')).toBeTruthy();
  });
});
