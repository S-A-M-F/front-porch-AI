// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The per-chat system prompt source, the web counterpart of the desktop
// Chat Settings "System prompt" row and the new-chat prompt picker. State
// comes from /api/chat/state `promptSource` (1:1 chats only); the row saves
// through POST /api/chat/prompt-source and the picker answers through
// POST /api/chat/prompt-picker.

import { useState } from 'react';
import { api } from '../api/client';
import { Toggle } from './ChatToolsShared';

export type PromptPresetWire = 'card+amend' | 'card' | 'user';

export interface PromptPicker {
  characterName: string;
  cardPrompt: string;
  userPrompt: string;
  amendment: string;
}

export interface PromptSourceState {
  source?: 'card' | 'user' | null;
  amendments?: boolean | null;
  picker?: PromptPicker;
}

export const PROMPT_PRESETS: { wire: PromptPresetWire; label: string; sub: string }[] = [
  { wire: 'card+amend', label: 'Card + my amendments', sub: 'Recommended · what happens today' },
  { wire: 'card', label: 'Card only', sub: "Author's prompt, nothing added" },
  { wire: 'user', label: 'My prompt', sub: "Replaces the card's prompt" },
];

/** The preset a stored pair reads as, the same mapping as the desktop row. */
export function presetOf(state: PromptSourceState): PromptPresetWire {
  if (state.source === 'user') return 'user';
  if (state.amendments === false) return 'card';
  return 'card+amend';
}

type Failed = (what: string, e: unknown) => void;

/** Chat Settings' System prompt row: three presets plus the additions switch. */
export function PromptSourceSettings({ state, onDone, onFailed }: {
  state: PromptSourceState;
  onDone: () => void | Promise<void>;
  onFailed: Failed;
}) {
  const preset = presetOf(state);
  const save = (source: 'card' | 'user', amendments: boolean) => {
    api
      .post('/api/chat/prompt-source', { source, amendments })
      .then(() => onDone())
      .catch((e) => onFailed('change this chat’s system prompt', e));
  };
  return (
    <section className="card prompt-source-settings">
      <h3>System prompt</h3>
      <p className="reading-blurb">
        Which base this chat sends. Global additions append unless turned off; blank state
        follows the defaults.
      </p>
      <div className="prompt-source-chips" role="radiogroup" aria-label="System prompt for this chat">
        {PROMPT_PRESETS.map((p) => (
          <button
            key={p.wire}
            role="radio"
            aria-checked={preset === p.wire}
            title={p.sub}
            className={`chip-toggle${preset === p.wire ? ' on' : ''}`}
            onClick={() => save(p.wire === 'user' ? 'user' : 'card', p.wire !== 'card')}
          >
            {p.label}
          </button>
        ))}
      </div>
      <Toggle
        label="Append global prompt additions"
        value={state.amendments !== false}
        onChange={(v) => save(state.source === 'user' ? 'user' : 'card', v)}
      />
    </section>
  );
}

const approxTokens = (base: string, amendment: string, withAmendment: boolean) =>
  Math.round((base.length + (withAmendment && amendment.trim() ? amendment.trim().length : 0)) / 4);

/**
 * The new-chat picker: shown when a 1:1 chat starts with a card that ships
 * its own system prompt. Both prompts show in full in their own scrolling
 * panes; the footer stays on screen.
 */
export function PromptSourcePickerModal({ picker, onDone, onFailed }: {
  picker: PromptPicker;
  onDone: () => void | Promise<void>;
  onFailed: Failed;
}) {
  const [preset, setPreset] = useState<PromptPresetWire>('card+amend');
  const [remember, setRemember] = useState(false);
  const usesCard = preset !== 'user';
  const usesAmendments = preset !== 'card';
  const base = usesCard ? picker.cardPrompt : picker.userPrompt;
  const amendment = picker.amendment.trim();

  const answer = (body: { preset: PromptPresetWire | null; remember?: boolean; askEveryChat?: boolean }) => {
    api
      .post('/api/chat/prompt-picker', body)
      .then(() => onDone())
      .catch((e) => onFailed('choose this chat’s system prompt', e));
  };

  return (
    <div className="drawer-backdrop center" onClick={() => answer({ preset: null })}>
      <div
        className="modal prompt-picker"
        role="dialog"
        aria-label="Choose the system prompt for this chat"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="prompt-picker-head">
          <strong>Choose the system prompt for this chat</strong>
          <p className="muted small">
            New chat with <b>{picker.characterName}</b> · their card ships its own system prompt.
            Your global amendments apply unless you turn them off.
          </p>
        </div>
        <div className="prompt-picker-body">
          <div className="prompt-picker-presets" role="radiogroup" aria-label="Prompt preset">
            {PROMPT_PRESETS.map((p) => (
              <button
                key={p.wire}
                role="radio"
                aria-checked={preset === p.wire}
                className={`prompt-picker-preset${preset === p.wire ? ' on' : ''}`}
                onClick={() => setPreset(p.wire)}
              >
                <span className="prompt-picker-preset-label">{p.label}</span>
                <span className="prompt-picker-preset-sub">{p.sub}</span>
              </button>
            ))}
          </div>
          <div className="prompt-picker-panes">
            <PromptPane title="Character card prompt" text={picker.cardPrompt} isBase={usesCard} />
            <PromptPane title="Your prompt (Settings → General)" text={picker.userPrompt} isBase={!usesCard} />
          </div>
          <div className="prompt-picker-preview">
            <div className="prompt-picker-preview-head">
              <span>What gets sent</span>
              <span className="muted small">
                base: {usesCard ? 'card prompt' : 'your prompt'}
                {usesAmendments ? ' + amendment' : ' · no amendment'}
              </span>
            </div>
            <div className="prompt-picker-preview-text">
              <div>{base}</div>
              {usesAmendments && amendment && (
                <div className="prompt-picker-amendment">{amendment} ← global amendment</div>
              )}
            </div>
            <div className="muted small prompt-picker-tokens">
              ≈ <b>{approxTokens(base, amendment, usesAmendments)} tokens</b> counted against the
              context budget before history trimming · macros resolved per speaker
            </div>
          </div>
        </div>
        <div className="prompt-picker-foot">
          <label className="prompt-picker-remember">
            <input type="checkbox" checked={remember} onChange={(e) => setRemember(e.target.checked)} />
            <span>Remember my choice for {picker.characterName}</span>
          </label>
          <div className="modal-actions">
            <button onClick={() => answer({ preset, askEveryChat: true })}>Ask me every chat</button>
            <button className="primary" onClick={() => answer({ preset, remember })}>Start chat</button>
          </div>
        </div>
      </div>
    </div>
  );
}

function PromptPane({ title, text, isBase }: { title: string; text: string; isBase: boolean }) {
  return (
    <div className={`prompt-pane${isBase ? ' base' : ' dim'}`}>
      <div className="prompt-pane-head">
        <span>{title}</span>
        {isBase && <span className="prompt-pane-tag">BASE</span>}
      </div>
      <div className="prompt-pane-text" tabIndex={0}>{text || '(empty)'}</div>
    </div>
  );
}
