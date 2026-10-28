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

describe('ModelDownloads file list', () => {
  async function expandWith(answer: unknown) {
    get.mockImplementation(async (path: string) => {
      if (path.startsWith('/api/backend/hf/search')) return { models: [MODELS[0]] };
      if (path.startsWith('/api/backend/hf/files')) return answer;
      return { downloads: [], overallProgress: 0, overallSpeed: 0, activeCount: 0 };
    });
    await act(async () => {
      root.render(
        createElement(ModelDownloads, { query: 'Scarlett', setQuery: () => {}, searchNonce: 1, onError: () => {} }),
      );
    });
    await act(async () => {
      container.querySelector<HTMLButtonElement>('.hf-head')!.click();
    });
  }

  it('shows a split quant once with its parts, the fit line, Best fit and the vision add-on', async () => {
    await expandWith({
      files: [
        { filename: 'Q4/m-Q4_K_M.gguf', title: 'm-Q4_K_M.gguf', sizeBytes: 16e9, repoId: 'r/m', quant: 'q4K', parts: 1, kind: 'model', fit: 'fits', fitText: '6.2 GB free after loading', bestFit: true },
        { filename: 'Q8/m-Q8_0-00001-of-00002.gguf', title: 'm-Q8_0.gguf', sizeBytes: 29e9, repoId: 'r/m', quant: 'q8_0', parts: 2, kind: 'model', fit: 'exceeds', fitText: '5.1 GB over your VRAM', bestFit: false },
        { filename: 'mmproj-F16.gguf', title: 'mmproj-F16.gguf', sizeBytes: 8e8, repoId: 'r/m', quant: 'fp16', parts: 1, kind: 'projector', fit: 'fits', fitText: '22 GB free after loading', bestFit: false },
      ],
      problem: null,
    });
    const text = container.querySelector('.file-list')!.textContent!;
    expect(text).toContain('m-Q8_0.gguf · 2 parts');
    expect(text).toContain('5.1 GB over your VRAM');
    expect(container.querySelectorAll('.hf-best')).toHaveLength(1);
    expect(container.querySelector('.hf-best')!.closest('li')!.textContent).toContain('m-Q4_K_M.gguf');
    expect(text.indexOf('Vision add-on')).toBeLessThan(text.indexOf('mmproj-F16.gguf'));
  });

  it('says a gated repo needs its licence and a token instead of loading forever', async () => {
    await expandWith({ files: [], problem: 'gated' });
    expect(container.querySelector('[data-testid="hf-files-note"]')!.textContent).toContain('Gated repo');
  });
});

describe('ModelDownloads model card', () => {
  it('opens the repo card from an expanded result, with its facts and markdown', async () => {
    get.mockImplementation(async (path: string) => {
      if (path.startsWith('/api/backend/hf/search')) return { models: [MODELS[0]] };
      if (path.startsWith('/api/backend/hf/files')) return { files: [], problem: null };
      if (path.startsWith('/api/backend/hf/card')) {
        return {
          repoId: MODELS[0].id,
          markdown: '# Dark Scarlett\n\nPassion ignited.',
          license: 'apache-2.0',
          baseModels: ['ReadyArt/Dark-Scarlett-27B-v3.0'],
          lastModified: '2026-10-01T00:00:00Z',
          problem: null,
        };
      }
      return { downloads: [], overallProgress: 0, overallSpeed: 0, activeCount: 0 };
    });
    await act(async () => {
      root.render(
        createElement(ModelDownloads, { query: 'Scarlett', setQuery: () => {}, searchNonce: 1, onError: () => {} }),
      );
    });
    await act(async () => {
      container.querySelector<HTMLButtonElement>('.hf-head')!.click();
    });
    await act(async () => {
      container.querySelector<HTMLButtonElement>('.hf-card-row button')!.click();
    });

    expect(get).toHaveBeenCalledWith(`/api/backend/hf/card?repoId=${encodeURIComponent(MODELS[0].id)}`);
    const dialog = document.querySelector('[data-testid="model-card-dialog"]')!;
    expect(dialog.textContent).toContain('Licence: apache-2.0');
    expect(dialog.textContent).toContain('Original: ReadyArt/Dark-Scarlett-27B-v3.0');
    expect(dialog.querySelector('.model-card-md')!.textContent).toContain('Passion ignited.');
  });
});
