// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Book step's second card when the source is a character: the library
// as tiles, then that character's 1:1 chats as rows with Card only first,
// and the one warning line for the picked chat. Twin of the desktop
// BookSourceSection.

import { useState } from 'react';
import type { CharacterRow } from './story/setup/draft';
import { characterAvatar } from './story/setup/useSetupData';
import {
  WORLD_CHAT_MESSAGES_FLOOR,
  WORLD_CHAT_MESSAGES_SHORT,
  worldChatLengthChip,
  worldChatLengthWarning,
  worldChatRowsFor,
  type ChatSourceRow,
  type WorldBuildMode,
} from './worldFromWiki';

type Props = {
  characters: CharacterRow[] | null;
  chatRows: ChatSourceRow[];
  characterId: string;
  setCharacterId: (id: string) => void;
  sessionId: string;
  setSessionId: (id: string) => void;
  mode: WorldBuildMode;
  depth: number;
  busy: boolean;
};

const SHOWN = 24;
const CHATS_SHOWN = 8;

export function WorldSourceCard(p: Props) {
  const [query, setQuery] = useState('');
  const words = query.toLowerCase().split(/\s+/).filter(Boolean);
  const all = p.characters ?? [];
  const shown = words.length
    ? all.filter((c) => words.every((w) => c.name.toLowerCase().includes(w)))
    : all;
  const picked = all.find((c) => c.id === p.characterId) ?? null;
  const chats = picked ? worldChatRowsFor(p.chatRows, picked.id) : [];
  const pickedRow = chats.find((r) => r.session_id === p.sessionId);
  const warning = worldChatLengthWarning(pickedRow?.message_count ?? 0, p.mode, p.depth);
  return (
    <section className={`wfw-card${picked ? '' : ' wfw-card-wanted'}`} data-testid="world-source-card">
      <header className="wfw-card-head">
        <span className="wfw-badge" aria-hidden="true">
          <PersonIcon />
        </span>
        <strong>The source</strong>
        <span className="muted small wfw-grow-right">2 of 4</span>
      </header>
      <label className="cg-field">
        <span className="cg-field-label">Character</span>
        <input
          type="search"
          data-testid="world-character-search"
          placeholder="Search your characters"
          value={query}
          disabled={p.busy}
          onChange={(e) => setQuery(e.target.value)}
        />
      </label>
      {p.characters === null ? (
        <p className="muted small">Loading your characters…</p>
      ) : all.length === 0 ? (
        <p className="muted small">No characters yet. Make or import one first, then come back.</p>
      ) : shown.length === 0 ? (
        <p className="muted small">No character matches that search.</p>
      ) : (
        <div className="wfw-tiles four" role="radiogroup" aria-label="Character">
          {shown.slice(0, SHOWN).map((c) => {
            const on = c.id === p.characterId;
            const n = worldChatRowsFor(p.chatRows, c.id).length;
            const avatar = characterAvatar(c);
            return (
              <button
                type="button"
                key={c.id}
                role="radio"
                aria-checked={on}
                data-testid={`world-character-pick-${c.id}`}
                className={`wfw-tile wfw-tile-row${on ? ' on' : ''}`}
                disabled={p.busy}
                onClick={() => {
                  if (c.id !== p.characterId) {
                    p.setCharacterId(c.id);
                    p.setSessionId('');
                  }
                }}
              >
                {avatar ? (
                  <img className="wfw-avatar" src={avatar} alt="" />
                ) : (
                  <span className="wfw-avatar wfw-avatar-initials" aria-hidden="true">
                    {initials(c.name)}
                  </span>
                )}
                <span className="wfw-tile-text">
                  <strong>{c.name}</strong>
                  <span className="muted small">{n === 0 ? 'no chats yet' : `${n} chat${n === 1 ? '' : 's'}`}</span>
                </span>
              </button>
            );
          })}
        </div>
      )}
      {shown.length > SHOWN && (
        <span className="muted small">
          Showing {SHOWN} of {shown.length} characters. Search to narrow them down.
        </span>
      )}
      {picked && (
        <>
          <div className="wfw-moment-head" style={{ marginTop: 8 }}>
            <strong>Chats with {picked.name}</strong>
            <span className="wfw-chip">optional</span>
            <span className="muted small wfw-grow-right">1:1 chats only for now; group chats come later.</span>
          </div>
          <div className="wfw-grid" role="radiogroup" aria-label="Chat">
            <button
              type="button"
              role="radio"
              aria-checked={!p.sessionId}
              data-testid="world-character-chat-card-only"
              className={`wfw-tile wfw-tile-row${p.sessionId ? '' : ' on'}`}
              disabled={p.busy}
              onClick={() => p.setSessionId('')}
            >
              <span className="wfw-tile-text">
                <strong>Card only</strong>
                <span className="muted small">
                  {chats.length === 0
                    ? `No chats with ${picked.name} yet. The card alone makes a short world, mostly the places and people it names.`
                    : 'A short world from the card alone: mostly the places and people it names.'}
                </span>
              </span>
            </button>
            {chats.slice(0, CHATS_SHOWN).map((r) => {
              const on = r.session_id === p.sessionId;
              const chip = worldChatLengthChip(r.message_count);
              return (
                <button
                  type="button"
                  key={r.session_id}
                  role="radio"
                  aria-checked={on}
                  data-testid={`world-character-chat-${r.session_id}`}
                  className={`wfw-tile wfw-tile-row${on ? ' on' : ''}`}
                  disabled={p.busy}
                  onClick={() => p.setSessionId(r.session_id)}
                >
                  <span className="wfw-tile-text">
                    <strong>{r.session_name || 'Untitled chat'}</strong>
                    <span className="muted small">
                      {shortDate(r.date)} · {r.message_count} message{r.message_count === 1 ? '' : 's'}
                    </span>
                  </span>
                  {chip && (
                    <span
                      className={`wfw-chip${chip === 'short chat' ? ' accent' : ' warn'}`}
                      title={
                        chip === 'short chat'
                          ? `Fewer than ${WORLD_CHAT_MESSAGES_SHORT} messages. Facts only will give a thin shelf.`
                          : `Fewer than ${WORLD_CHAT_MESSAGES_FLOOR} messages. There is almost nothing to skim.`
                      }
                    >
                      {chip}
                    </span>
                  )}
                </button>
              );
            })}
          </div>
          {chats.length > CHATS_SHOWN && (
            <span className="muted small">Showing the newest {CHATS_SHOWN} of {chats.length} chats.</span>
          )}
          {warning && (
            <p className="wfw-warning small" data-testid="world-character-length-warning">
              {warning}
            </p>
          )}
        </>
      )}
    </section>
  );
}

function initials(name: string): string {
  return name
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((w) => w[0]?.toUpperCase() ?? '')
    .join('') || '?';
}

function shortDate(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  return d.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' });
}

function PersonIcon() {
  return (
    <svg width={16} height={16} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="8" r="4" />
      <path d="M4 21a8 8 0 0 1 16 0" />
    </svg>
  );
}
