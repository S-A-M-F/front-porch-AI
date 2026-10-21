// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The "Part of" picker (slice 4 web twin of slice 3). Guards, in order of
// the failure they prevent:
//   - candidates come from the relay's ONE law endpoint, never a client
//     guess (review #592: a UI that re-decides legality drifts);
//   - the save posts parentWorldId, and clearing Part of detaches;
//   - naming a parent flips the place to Inherit (design §7 default);
//   - a dangling/cycled parent still renders a value (the select must be
//     honest about state the relay reports), the web twin of desktop's
//     pinned-item fix;
//   - the library groups children under their root instead of one flat
//     grid, and a library with no tree is the old flat grid untouched.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../api/client', () => ({
  api: { get, post },
  ApiError: class extends Error {},
}));
vi.mock('../components/ClimateSeasonEditor', () => ({ ClimateSeasonEditor: () => null }));
vi.mock('../components/LoreEntriesEditor', () => ({ LoreEntriesEditor: () => null }));
vi.mock('../components/ImportCharacterLoreButton', () => ({
  ImportCharacterLoreButton: () => null,
}));

import { WorldsPage } from './WorldsPage';

let container: HTMLDivElement;
let root: Root;

const button = (label: string) =>
  Array.from(container.querySelectorAll('button')).find(
    (b) => b.textContent?.trim() === label,
  )!;

const partOfSelect = () =>
  container.querySelector('select[aria-label="Part of"]') as HTMLSelectElement;

function setValue(el: HTMLSelectElement, value: string) {
  act(() => {
    const setter = Object.getOwnPropertyDescriptor(
      window.HTMLSelectElement.prototype,
      'value',
    )?.set;
    setter?.call(el, value);
    el.dispatchEvent(new Event('change', { bubbles: true }));
  });
}

const WORLD_ROWS = [
  {
    id: 'earth-1',
    name: 'Earth',
    description: 'A world',
    entryCount: 2,
    climateEnabled: true,
    biomeId: 'temperate',
  },
  {
    id: 'town-1',
    name: 'Bletchfield',
    description: 'A town',
    entryCount: 1,
    climateEnabled: false,
    parentWorldId: 'earth-1',
  },
];

beforeEach(async () => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  get.mockReset();
  post.mockReset();
  get.mockImplementation((url: string) => {
    if (url === '/api/worlds/climates') return Promise.resolve({ climates: [] });
    if (url.startsWith('/api/worlds/parent-candidates'))
      return Promise.resolve({
        candidates: [{ id: 'earth-1', name: 'Earth', parentWorldId: null }],
      });
    if (url.includes('/detail'))
      return Promise.resolve({
        id: 'earth-1',
        name: 'Earth',
        description: 'A world',
        entries: [],
        climateEnabled: true,
        atmosphere: 'breathable',
        gravity: 'earth',
      });
    return Promise.resolve({ worlds: WORLD_ROWS });
  });
  await act(async () => {
    root.render(createElement(MemoryRouter, null, createElement(WorldsPage)));
  });
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('the Part of picker', () => {
  it('asks the relay for the candidate law and lists what it answers', async () => {
    await act(async () => button('＋ New place').click());
    expect(
      get.mock.calls.some(([u]) => String(u).startsWith('/api/worlds/parent-candidates')),
    ).toBe(true);
    const sel = partOfSelect();
    expect(sel).not.toBeNull();
    const options = Array.from(sel.querySelectorAll('option')).map((o) => o.textContent);
    expect(options).toContain('Not inside anything (its own world)');
    expect(options).toContain('Earth');
  });

  it('a new place inside a parent defaults to INHERIT, and saves the parent', async () => {
    await act(async () => button('＋ New place').click());
    setValue(partOfSelect(), 'earth-1');
    // Name it so Save is live (blank-name law), then save.
    const nameInput = container.querySelector(
      '.world-edit label input',
    ) as HTMLInputElement;
    act(() => {
      const setter = Object.getOwnPropertyDescriptor(
        window.HTMLInputElement.prototype,
        'value',
      )?.set;
      setter?.call(nameInput, 'The Lighthouse');
      nameInput.dispatchEvent(new Event('input', { bubbles: true }));
    });
    post.mockResolvedValue({ worlds: WORLD_ROWS });
    await act(async () => button('Save place').click());
    expect(post).toHaveBeenCalledWith(
      '/api/worlds',
      expect.objectContaining({
        name: 'The Lighthouse',
        parentWorldId: 'earth-1',
        // §7: inheritance is the default the moment a parent is named.
        climateEnabled: false,
      }),
    );
  });

  it('clearing Part of detaches on save — never keeps a ghost parent', async () => {
    await act(async () => button('＋ New place').click());
    setValue(partOfSelect(), 'earth-1');
    setValue(partOfSelect(), '');
    const nameInput = container.querySelector(
      '.world-edit label input',
    ) as HTMLInputElement;
    act(() => {
      const setter = Object.getOwnPropertyDescriptor(
        window.HTMLInputElement.prototype,
        'value',
      )?.set;
      setter?.call(nameInput, 'Detached');
      nameInput.dispatchEvent(new Event('input', { bubbles: true }));
    });
    post.mockResolvedValue({ worlds: WORLD_ROWS });
    await act(async () => button('Save place').click());
    expect(post).toHaveBeenCalledWith(
      '/api/worlds',
      expect.objectContaining({ parentWorldId: null }),
    );
  });

  it('shows a dangling parent honestly instead of blanking', async () => {
    // Editing the town whose parent Earth vanished from candidates.
    get.mockImplementation((url: string) => {
      if (url === '/api/worlds/climates') return Promise.resolve({ climates: [] });
      if (url.startsWith('/api/worlds/parent-candidates'))
        return Promise.resolve({ candidates: [] });
      if (url.includes('/detail'))
        return Promise.resolve({
          id: 'town-1',
          name: 'Bletchfield',
          description: 'A town',
          entries: [],
          climateEnabled: false,
          parentWorldId: 'ghost-9',
        });
      return Promise.resolve({ worlds: WORLD_ROWS });
    });
    await act(async () => {
      const childCard = Array.from(container.querySelectorAll('.wsg-world-card')).find(
        (c) => c.querySelector('.wsg-world-name')?.textContent === 'Bletchfield',
      )!;
      (childCard.querySelector('[title="Edit"]') as HTMLButtonElement).click();
    });
    const sel = partOfSelect();
    expect(sel.value).toBe('ghost-9');
    expect(Array.from(sel.querySelectorAll('option')).some((o) =>
      (o.textContent ?? '').includes('invalid here'),
    )).toBe(true);
  });
});

describe('the grouped library', () => {
  it('indents the child under its root, not beside it in a flat grid', () => {
    const grid = container.querySelector('.wsg-child-grid');
    expect(grid).not.toBeNull();
    const childNames = Array.from(
      grid!.querySelectorAll('.wsg-world-name'),
    ).map((n) => n.textContent);
    expect(childNames).toContain('Bletchfield');
    // Earth renders through its section header only — never also flat.
    const sectionHeads = container.querySelectorAll('.wsg-section-head');
    expect(sectionHeads).toHaveLength(1);
  });

  it('a section child keeps its weather tag but drops the redundant inside-tag', () => {
    // The CI journey caught these two being conflated: the weather tag
    // rides the parent (every location gets one); the inside-tag only
    // renders where the tree is not visually obvious. A child under its
    // root is obvious — but still must say what its weather does.
    const grid = container.querySelector('.wsg-child-grid')!;
    const childCard = Array.from(grid.querySelectorAll('.wsg-world-card')).find(
      (c) => c.querySelector('.wsg-world-name')?.textContent === 'Bletchfield',
    )!;
    expect(
      childCard.querySelector('.wsg-weather-tag--inherit')?.textContent,
    ).toBe('Inherits weather');
    expect(childCard.querySelector('.wsg-inside-tag')).toBeNull();
    // The flat 'Solo'-style card would carry the inside-tag; here the
    // root's own card carries the places chip instead.
    expect(
      container
        .querySelector('.wsg-section-head .wsg-place-chip')
        ?.textContent ?? '',
    ).toContain('1 place');
  });

  it('a library with no tree stays the pre-locations flat grid', async () => {
    act(() => root.unmount());
    root = createRoot(container);
    get.mockImplementation((url: string) =>
      Promise.resolve(
        url === '/api/worlds/climates'
          ? { climates: [] }
          : {
              worlds: [
                {
                  id: 'a',
                  name: 'Solo',
                  description: '',
                  entryCount: 0,
                  climateEnabled: true,
                },
              ],
            },
      ),
    );
    await act(async () => {
      root.render(createElement(MemoryRouter, null, createElement(WorldsPage)));
    });
    expect(container.querySelector('.wsg-child-grid')).toBeNull();
    expect(container.querySelectorAll('.wsg-world-card')).toHaveLength(1);
  });
});
