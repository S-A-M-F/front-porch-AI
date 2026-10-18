// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The web System prompt row and new-chat picker send what the desktop's
// Chat Settings row and PromptSourcePickerDialog write. Desktop twin:
// test/services/chat/prompt_source_picker_test.dart. The real round trip
// is the "prompted card" journey in e2e/journeys.spec.ts.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const posts: { url: string; body: unknown }[] = [];
vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: {
    get: () => new Promise(() => {}),
    post: (url: string, body: unknown) => {
      posts.push({ url, body });
      return Promise.resolve({ status: 'ok' });
    },
  },
}));

const { PromptSourcePickerModal, PromptSourceSettings, presetOf } = await import('./PromptSource');

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  posts.length = 0;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

const radio = (name: string) =>
  [...container.querySelectorAll('[role="radio"]')].find((b) => b.textContent?.includes(name)) as HTMLButtonElement;
const button = (name: string) =>
  [...container.querySelectorAll('button')].find((b) => b.textContent === name) as HTMLButtonElement;

describe('prompt source', () => {
  it('reads the stored pair the way the desktop row does', () => {
    expect(presetOf({})).toBe('card+amend');
    expect(presetOf({ source: 'card', amendments: true })).toBe('card+amend');
    expect(presetOf({ source: 'card', amendments: false })).toBe('card');
    expect(presetOf({ source: 'user', amendments: false })).toBe('user');
  });

  it('the row saves each preset as its source and additions pair', async () => {
    const onDone = vi.fn();
    act(() => {
      root.render(createElement(PromptSourceSettings, { state: {}, onDone, onFailed: vi.fn() }));
    });
    expect(radio('Card + my amendments').getAttribute('aria-checked')).toBe('true');
    await act(async () => radio('Card only').click());
    await act(async () => radio('My prompt').click());
    expect(posts).toEqual([
      { url: '/api/chat/prompt-source', body: { source: 'card', amendments: false } },
      { url: '/api/chat/prompt-source', body: { source: 'user', amendments: true } },
    ]);
    expect(onDone).toHaveBeenCalledTimes(2);
  });

  it('the picker previews the chosen base and answers with it', async () => {
    act(() => {
      root.render(
        createElement(PromptSourcePickerModal, {
          picker: { characterName: 'Wren', cardPrompt: 'CARD', userPrompt: 'MINE', amendment: 'ADD' },
          onDone: vi.fn(),
          onFailed: vi.fn(),
        }),
      );
    });
    const preview = () => container.querySelector('.prompt-picker-preview-text')?.textContent ?? '';
    expect(preview()).toContain('CARD');
    expect(preview()).toContain('ADD');
    act(() => radio('My prompt').click());
    expect(preview()).toContain('MINE');
    act(() => radio('Card only').click());
    expect(preview()).not.toContain('ADD');
    act(() => (container.querySelector('.prompt-picker-remember input') as HTMLInputElement).click());
    await act(async () => button('Start chat').click());
    await act(async () => button('Ask me every chat').click());
    expect(posts).toEqual([
      { url: '/api/chat/prompt-picker', body: { preset: 'card', remember: true } },
      { url: '/api/chat/prompt-picker', body: { preset: 'card', askEveryChat: true } },
    ]);
  });
});
