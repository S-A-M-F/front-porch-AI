// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
import { act, createElement } from 'react';
import { createRoot } from 'react-dom/client';
import { expect, it, vi } from 'vitest';
import { ProcessingOverlay, NO_PROCESSING } from './ProcessingOverlay';

it('minimizes live details without cancelling, preserves phase actions, and retains the chosen view after idle', () => {
  vi.useFakeTimers();
  const host = document.createElement('div');
  document.body.append(host);
  const root = createRoot(host);
  const cancel = vi.fn();
  const skip = vi.fn();
  const button = (label: string) => {
    const match = [...host.querySelectorAll('button')].find(b => b.textContent === label);
    expect(match, label).toBeDefined();
    act(() => match!.click());
  };
  let minimized = false;
  let current: Partial<typeof NO_PROCESSING> = {};
  const render = (flags: Partial<typeof NO_PROCESSING>) => act(() => root.render(createElement(
    ProcessingOverlay, { p: { ...NO_PROCESSING, ...(current = flags) }, onCancel: cancel, onSkipObjective: skip,
      minimized, onMinimizedChange: (value: boolean) => { minimized = value; render(current); } },
  )));
  try {
    render({ active: true, realism: true, text: 'synthetic evaluation' });
    expect(host.querySelector('pre')?.textContent).toBe('synthetic evaluation');
    button('Minimize evaluation');
    expect(host.querySelector('pre')).toBeNull();
    expect(cancel).not.toHaveBeenCalled();
    act(() => vi.advanceTimersByTime(31_000));
    expect(host.textContent).toContain('31s elapsed');
    expect(host.querySelector('[aria-hidden="true"][aria-live="off"]')?.textContent).toBe('31s elapsed');
    button('Stop this reply');
    expect(cancel).toHaveBeenCalledTimes(1);
    render({ active: true, objective: true });
    button('Skip goal check');
    expect(skip).toHaveBeenCalledTimes(1);
    button('Show evaluation details');
    expect(host.querySelector('.proc-stages')).not.toBeNull();
    button('Minimize evaluation');
    render({ active: false });
    expect(host.textContent).toBe('');
    render({ active: true, greeting: true });
    expect(host.querySelector('.proc-stages')).toBeNull();
    expect(host.textContent).toContain('Show evaluation details');
    expect(host.textContent).toContain('Reading the room');
    button('Stop this reply');
    expect(cancel).toHaveBeenCalledTimes(2);
  } finally {
    act(() => root.unmount());
    host.remove();
    vi.useRealTimers();
  }
});
