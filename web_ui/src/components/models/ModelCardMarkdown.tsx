// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Renders a HuggingFace model card's markdown as React elements. The host has
// already removed its HTML (HfReadme.clean); this never sets innerHTML, so a
// card cannot inject markup, and only http(s) links become links. Covers what
// model cards use: headings, paragraphs, lists, quotes, rules, fenced code,
// pipe tables, and inline code, bold, italic, links and bare URLs.

import { Fragment, type ReactNode } from 'react';

// Groups: 1 code · 2,3 link · 4 **bold** · 5 __bold__ · 6 *em* · 7 _em_ · 8 bare URL.
// Underscores only emphasise at word edges (CommonMark), so Q4_K_M stays a name.
const INLINE =
  /(`[^`]+`)|\[([^\]]+)\]\(([^)\s]+)[^)]*\)|\*\*(.+?)\*\*|(?<!\w)__(.+?)__(?!\w)|\*([^*\s][^*]*?)\*|(?<!\w)_([^_\s][^_]*?)_(?!\w)|(https?:\/\/[^\s<>()]+[^\s<>().,;:!?'"])/g;

function link(href: string, children: ReactNode, key: number): ReactNode {
  if (!/^https?:\/\//i.test(href)) return <Fragment key={key}>{children}</Fragment>;
  return (
    <a key={key} href={href} target="_blank" rel="noopener noreferrer">
      {children}
    </a>
  );
}

function inline(text: string): ReactNode[] {
  const out: ReactNode[] = [];
  let last = 0;
  let k = 0;
  for (const m of text.matchAll(INLINE)) {
    const at = m.index ?? 0;
    if (at > last) out.push(text.slice(last, at));
    const bold = m[4] ?? m[5];
    const em = m[6] ?? m[7];
    if (m[1]) out.push(<code key={k++}>{m[1].slice(1, -1)}</code>);
    else if (m[2]) out.push(link(m[3], inline(m[2]), k++));
    else if (bold) out.push(<strong key={k++}>{inline(bold)}</strong>);
    else if (em) out.push(<em key={k++}>{inline(em)}</em>);
    else if (m[8]) out.push(link(m[8], m[8], k++));
    last = at + m[0].length;
  }
  if (last < text.length) out.push(text.slice(last));
  return out;
}

const cells = (row: string) =>
  row.trim().replace(/^\||\|$/g, '').split('|').map((c) => c.trim());

export function ModelCardMarkdown({ source }: { source: string }) {
  const lines = source.replace(/\r\n/g, '\n').split('\n');
  const blocks: ReactNode[] = [];
  let i = 0;
  let k = 0;
  while (i < lines.length) {
    const line = lines[i];
    const t = line.trim();
    if (!t) {
      i++;
      continue;
    }
    if (t.startsWith('```')) {
      const body: string[] = [];
      i++;
      while (i < lines.length && !lines[i].trim().startsWith('```')) body.push(lines[i++]);
      i++;
      blocks.push(<pre key={k++}><code>{body.join('\n')}</code></pre>);
      continue;
    }
    const h = /^(#{1,6})\s+(.*)$/.exec(t);
    if (h) {
      const level = Math.min(h[1].length + 2, 6);
      const Tag = `h${level}` as 'h3' | 'h4' | 'h5' | 'h6';
      blocks.push(<Tag key={k++}>{inline(h[2].replace(/\s*#+$/, ''))}</Tag>);
      i++;
      continue;
    }
    if (/^([-*_])(\s*\1){2,}$/.test(t)) {
      blocks.push(<hr key={k++} />);
      i++;
      continue;
    }
    if (t.includes('|') && i + 1 < lines.length && /^\s*\|?\s*:?-{2,}/.test(lines[i + 1])) {
      const head = cells(t);
      i += 2;
      const rows: string[][] = [];
      while (i < lines.length && lines[i].includes('|') && lines[i].trim()) rows.push(cells(lines[i++]));
      blocks.push(
        <div key={k++} className="mc-table">
          <table>
            <thead><tr>{head.map((c, j) => <th key={j}>{inline(c)}</th>)}</tr></thead>
            <tbody>{rows.map((r, ri) => <tr key={ri}>{r.map((c, j) => <td key={j}>{inline(c)}</td>)}</tr>)}</tbody>
          </table>
        </div>,
      );
      continue;
    }
    if (t.startsWith('>')) {
      const body: string[] = [];
      while (i < lines.length && lines[i].trim().startsWith('>')) body.push(lines[i++].trim().replace(/^>\s?/, ''));
      blocks.push(<blockquote key={k++}>{inline(body.join(' '))}</blockquote>);
      continue;
    }
    const item = /^\s*([-*+]|\d+[.)])\s+/;
    if (item.test(line)) {
      const ordered = /^\s*\d/.test(line);
      const items: string[] = [];
      while (i < lines.length && item.test(lines[i])) items.push(lines[i++].replace(item, ''));
      const List = ordered ? 'ol' : 'ul';
      blocks.push(<List key={k++}>{items.map((it, j) => <li key={j}>{inline(it)}</li>)}</List>);
      continue;
    }
    const para: string[] = [];
    while (i < lines.length && lines[i].trim() && !/^(```|#{1,6}\s|>|\s*([-*+]|\d+[.)])\s)/.test(lines[i].trim())) {
      para.push(lines[i++].trim());
    }
    if (para.length === 0) para.push(lines[i++].trim());
    blocks.push(<p key={k++}>{inline(para.join(' '))}</p>);
  }
  return <div className="model-card-md">{blocks}</div>;
}
