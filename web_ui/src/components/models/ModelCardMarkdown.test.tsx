// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's model-card renderer: the markdown model cards use becomes
// elements, and nothing in a card can become markup or a non-web link.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { ModelCardMarkdown } from './ModelCardMarkdown';

let container: HTMLDivElement;
let root: Root;

function show(source: string) {
  act(() => root.render(createElement(ModelCardMarkdown, { source })));
  return container.querySelector('.model-card-md')!;
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('ModelCardMarkdown', () => {
  it('renders the blocks model cards use', () => {
    const md = show(
      [
        '## Prompt format',
        '```',
        '<start_of_turn>user',
        '```',
        '- **Context:** 128K',
        '- see [the original](https://huggingface.co/x/y)',
        '| Quant | Size |',
        '| --- | --- |',
        '| Q4_K_M | 16 GB |',
        '> Mature themes',
        'Made with https://github.com/ggerganov/llama.cpp.',
      ].join('\n'),
    );
    expect(md.querySelector('h4')!.textContent).toBe('Prompt format');
    expect(md.querySelector('pre code')!.textContent).toBe('<start_of_turn>user');
    expect(md.querySelectorAll('ul li')).toHaveLength(2);
    expect(md.querySelector('li strong')!.textContent).toBe('Context:');
    expect(md.querySelector('td')!.textContent).toBe('Q4_K_M');
    expect(md.querySelector('blockquote')!.textContent).toBe('Mature themes');
    const links = [...md.querySelectorAll('a')].map((a) => a.getAttribute('href'));
    expect(links).toEqual(['https://huggingface.co/x/y', 'https://github.com/ggerganov/llama.cpp']);
    expect(md.querySelector('a')!.getAttribute('rel')).toBe('noopener noreferrer');
  });

  it('never turns card text into markup or a script link', () => {
    const md = show('<img src=x onerror=alert(1)> [click](javascript:alert(1)) <script>bad()</script>');
    expect(md.querySelector('img, script')).toBeNull();
    expect(md.querySelector('a')).toBeNull();
    expect(md.textContent).toContain('<script>bad()</script>');
    expect(md.textContent).toContain('click');
  });
});
