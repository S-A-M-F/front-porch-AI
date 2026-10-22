// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Slice 4 chat-panel twin of the desktop Places panel: the "inside X"
// breadcrumb, the "Weather from <author>" line, and the live-slot write
// discipline — the exact M7 failure from review #592 (two quick scene
// moves dropping a place out of BOTH slots), reproduced here with the
// first POST still in flight.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../api/client', () => ({
  api: { get, post },
  ApiError: class extends Error {},
}));

import { ChatPlacesSection } from './ChatPlacesSection';

let container: HTMLDivElement;
let root: Root;

const LH = {
  id: 'lh-1',
  name: 'The Lighthouse',
  climateEnabled: false,
  parentWorldId: 'bp-1',
  parentName: 'Bletchport',
};
const BP = {
  id: 'bp-1',
  name: 'Bletchport',
  climateEnabled: true,
};

const placesResponse = (primary: unknown, lore: unknown[]) => ({
  primary,
  primaryId: (primary as { id?: string } | null)?.id ?? null,
  lorePlaces: lore,
  climateAuthors: true,
  climateAuthorName: 'Bletchport',
  reachable: [LH, BP],
  climateId: 'temperate',
  dayCount: 1,
  climateOptions: [],
});

beforeEach(async () => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  get.mockReset();
  post.mockReset();
  get.mockImplementation((url: string) => {
    if (url === '/api/chat/places')
      return Promise.resolve(placesResponse(LH, []));
    if (url === '/api/worlds')
      return Promise.resolve({ worlds: [LH, BP] });
    return Promise.resolve({ climates: [] });
  });
  await act(async () => {
    root.render(createElement(ChatPlacesSection));
  });
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

const moveSelect = () =>
  Array.from(container.querySelectorAll('select')).find((s) =>
    Array.from(s.querySelectorAll('option')).some((o) =>
      (o.textContent ?? '').includes('(here)'),
    ),
  ) as HTMLSelectElement;

function choose(sel: HTMLSelectElement, value: string) {
  act(() => {
    const setter = Object.getOwnPropertyDescriptor(
      window.HTMLSelectElement.prototype,
      'value',
    )?.set;
    setter?.call(sel, value);
    sel.dispatchEvent(new Event('change', { bubbles: true }));
  });
}

describe('the Places panel tree twin', () => {
  it('breadcrumbs the setting and names the weather author', () => {
    expect(container.textContent).toContain('inside Bletchport');
    expect(container.textContent).toContain('Weather from Bletchport');
  });

  it('offers one-step places in Move the scene', () => {
    const sel = moveSelect();
    expect(sel).toBeDefined();
    const names = Array.from(sel.querySelectorAll('option')).map((o) => o.textContent);
    expect(names).toContain('The Lighthouse (here)');
    expect(names).toContain('Bletchport');
  });

  it('a move demotes the old setting to lore top', async () => {
    post.mockResolvedValue(placesResponse(BP, [LH]));
    await act(async () => choose(moveSelect(), 'bp-1'));
    expect(post).toHaveBeenCalledWith(
      '/api/chat/places',
      expect.objectContaining({
        primaryId: 'bp-1',
        loreIds: ['lh-1'],
      }),
    );
  });

  it('two quick moves compose on the live slots — no place vanishes (M7)', async () => {
    // The first POST stays in flight: the panel's rendered state (and any
    // render-captured list) is still pre-move. The second write must be
    // built from what the first write JUST committed, not from the stale
    // capture — the desktop bug this web twin must not inherit.
    let resolveFirst: (v: unknown) => void = () => {};
    post.mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          resolveFirst = resolve;
        }),
    );
    post.mockResolvedValueOnce(placesResponse(LH, [BP]));

    await act(async () => {
      choose(moveSelect(), 'bp-1'); // Lighthouse → lore, Bletchport = setting
    });
    // Still no response landed; UI still shows the Lighthouse as setting.
    await act(async () => {
      choose(moveSelect(), 'lh-1'); // straight back to the Lighthouse
      resolveFirst(placesResponse(BP, [LH]));
      await Promise.resolve();
    });

    const second = post.mock.calls[1];
    expect(second[0]).toBe('/api/chat/places');
    const body = second[1] as { primaryId: string; loreIds: string[] };
    expect(body.primaryId).toBe('lh-1');
    // With the stale-capture bug this is [] (or ['lh-1']) — Bletchport
    // would be off both slots. It must be the current setting demoted.
    expect(body.loreIds).toContain('bp-1');
    expect(body.loreIds).not.toContain('lh-1');
  });
});
