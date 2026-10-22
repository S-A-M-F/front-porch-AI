// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Slice 6: the PWA confirm twin. The modal speaks the desktop copy,
// answers exactly two ways, and fires accept through onAnswer.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { PlaceMoveModal } from './ChatOverlays';

const move = { id: 'p-tea', name: 'Tea Rooms' };

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  root.unmount();
  container.remove();
});

function renderModal(onAnswer: (accept: boolean) => void) {
  act(() => root.render(createElement(PlaceMoveModal, { move, onAnswer })));
}

const button = (name: string) =>
  Array.from(container.querySelectorAll('button')).find((b) => b.textContent === name);

describe('PlaceMoveModal', () => {
  it('asks about the place and offers Stay / Move there', () => {
    renderModal(() => {});
    expect(container.textContent).toContain('arriving at Tea Rooms');
    expect(button('Stay')).toBeTruthy();
    expect(button('Move there')).toBeTruthy();
  });

  it('Move answers accept; Stay answers decline', () => {
    const onAnswer = vi.fn();
    renderModal(onAnswer);
    act(() => void button('Move there')!.click());
    expect(onAnswer).toHaveBeenLastCalledWith(true);
    act(() => void button('Stay')!.click());
    expect(onAnswer).toHaveBeenLastCalledWith(false);
  });
});
