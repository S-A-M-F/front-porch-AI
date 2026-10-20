// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// SETTINGS PARITY — WEB SIDE. docs/design/settings-parity-manifest.json maps
// every Settings control to its home on each surface. This guard proves the
// web half: SettingsPage renders the six desktop-tab sections in order, and
// each control sits in its pinned section (the chat-appearance controls also
// inside their group). The desktop half is guarded by
// test/hygiene/settings_parity_manifest_test.dart. Move a card in the page
// without the manifest, and this fails.

import { readFileSync } from 'node:fs';
import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../api/client', () => ({ api: { get, post }, ApiError: class extends Error {} }));

// Each sub-panel is a stub carrying the marker text its real component
// renders (and its testid). The panels have their own tests; here only the
// page's wiring is under test. PromptSettingsCard stays real — its markers
// are the point of the Phase 2 move.
vi.mock('../components/PersonaManager', async () => {
  const { createElement: h } = await import('react');
  return { PersonaManager: () => h('div', { 'data-testid': 'persona-manager' }, 'User personas') };
});
vi.mock('../components/MessageSideSettings', async () => {
  const { createElement: h } = await import('react');
  return { MessageSideSettings: () => h('div', { 'data-testid': 'message-side-card' }, 'My messages on the right') };
});
vi.mock('../components/FollowStreamingSettings', async () => {
  const { createElement: h } = await import('react');
  return { FollowStreamingSettings: () => h('div', { 'data-testid': 'follow-streaming-card' }, 'Follow streaming replies') };
});
vi.mock('../components/ReadingSizeSettings', async () => {
  const { createElement: h } = await import('react');
  return { ReadingSizeSettings: () => h('div', { 'data-testid': 'reading-size-card' }, 'Reading size') };
});
vi.mock('../components/ChatColorsSettings', async () => {
  const { createElement: h } = await import('react');
  return { ChatColorsSettings: () => h('div', { 'data-testid': 'chat-colors-card' }, 'Chat colors') };
});
vi.mock('../components/PorchLifeSettings', async () => {
  const { createElement: h } = await import('react');
  return { PorchLifeSettings: () => h('div', { 'data-testid': 'porch-life-card' }, 'Porch Life') };
});
vi.mock('../components/GenerationSettingsFields', async () => {
  const { createElement: h } = await import('react');
  return { GenerationSettingsFields: () => h('div', { 'data-testid': 'generation-fields' }, 'Temperature · Spell check language') };
});
vi.mock('../components/ModelTransportCard', async () => {
  const { createElement: h } = await import('react');
  return { ModelTransportCard: () => h('div', { 'data-testid': 'model-transport-card' }, 'Model transport') };
});
vi.mock('../components/VoiceMediaSettings', async () => {
  const { createElement: h } = await import('react');
  return { VoiceMediaSettings: () => h('div', { 'data-testid': 'voice-media-card' }, 'Voice & Media') };
});
vi.mock('../components/IdleUnloadSettings', async () => {
  const { createElement: h } = await import('react');
  return { IdleUnloadSettings: () => h('div', { 'data-testid': 'idle-unload-card' }, 'Free graphics memory when idle') };
});
vi.mock('../components/KeepRecentChatsSettings', async () => {
  const { createElement: h } = await import('react');
  return { KeepRecentChatsSettings: () => h('div', { 'data-testid': 'keep-recent-card' }, 'Keep recent chats ready') };
});
vi.mock('../components/ModelPicker', () => ({ ModelPicker: () => null }));
vi.mock('../components/WorkerBackendCard', () => ({ WorkerBackendCard: () => null }));
vi.mock('../components/SuperGrokCard', () => ({ SuperGrokCard: () => null }));

import { SettingsPage } from './SettingsPage';

interface ManifestControl {
  section: string;
  group?: string;
  webMarker: string;
}
const manifest = JSON.parse(
  // Vitest runs with web_ui/ as cwd; the manifest lives at the repo root.
  readFileSync('../docs/design/settings-parity-manifest.json', 'utf8'),
) as { sections: string[]; controls: Record<string, ManifestControl> };

const settings = () => ({
  backend: 'kobold',
  backends: ['kobold', 'openRouter'],
  isLocal: true,
  loadedModel: 'No model loaded',
  remoteApiUrl: '',
  remoteModelName: '',
  hasApiKey: false,
  contextSize: 16384,
  reasoningEnabled: false,
  reasoningEffort: 'medium',
  generation: {},
  systemPrompt: 'You are a friend.',
  additionalSystemPrompt: 'Stay in character.',
  additionalPostHistoryInstructions: 'End with a question.',
});

let container: HTMLDivElement;
let root: Root;

async function open() {
  get.mockImplementation((path: string) => {
    if (path === '/api/settings') return Promise.resolve(settings());
    if (path === '/api/legacy-models') {
      return Promise.resolve({ groups: [{ label: 'Piper voices', bytes: 2 ** 20 }], totalBytes: 2 ** 20 });
    }
    return Promise.resolve({});
  });
  await act(async () => {
    root.render(createElement(SettingsPage));
  });
}

const section = (id: string): HTMLElement | null =>
  container.querySelector(`[data-section="${id}"]`);
const textOf = (el: Element | null) => el?.textContent ?? '';

beforeEach(() => {
  vi.useFakeTimers();
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
  vi.useRealTimers();
});

describe('Settings sections mirror the desktop tabs', () => {
  it('renders the six sections in the manifest order', async () => {
    await open();
    const rendered = [...container.querySelectorAll('[data-section]')].map((el) =>
      el.getAttribute('data-section'),
    );
    expect(rendered).toEqual(manifest.sections);
  });

  it('mounts every control in its pinned section', async () => {
    await open();
    for (const [key, control] of Object.entries(manifest.controls)) {
      const host = control.group
        ? container.querySelector(
            `[data-section="${control.section}"] [data-testid="${control.group}-group"]`,
          )
        : section(control.section);
      expect(host, `section "${control.section}" for ${key}`).not.toBeNull();
      expect(
        textOf(host).includes(control.webMarker),
        `${key}: "${control.webMarker}" missing from "${control.group ?? control.section}"`,
      ).toBe(true);
    }
  });

  it('keeps the chat-appearance controls inside their group in General', async () => {
    await open();
    const group = container.querySelector(
      '[data-section="general"] [data-testid="chat-appearance-group"]',
    );
    expect(group).not.toBeNull();
    for (const key of ['userMessagesOnRight', 'followStreamingReplies', 'readingSize', 'chatColors']) {
      expect(
        textOf(group).includes(manifest.controls[key].webMarker),
        `${key} left the chat-appearance group`,
      ).toBe(true);
    }
  });

  it('moves the prompt family out of Generation into General, flat', async () => {
    await open();
    const general = textOf(section('general'));
    expect(general).toContain('Fallback system prompt');
    expect(general).toContain('Additional system instructions');
    expect(general).toContain('Additional post-history instructions');
    expect(textOf(section('generation'))).not.toContain('Fallback system prompt');
  });
});
