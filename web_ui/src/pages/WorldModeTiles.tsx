// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The three mode tiles on the Book step's "What to make" card when the
// source is a character: Facts only, Faithful, Creative, each with what it
// does and what it never does. Twin of the desktop BookModeSection.

import {
  WORLD_MODE_EXPLAINER,
  defaultModeFor,
  type WorldBuildMode,
  type WorldModeChoice,
} from './worldFromWiki';

type Props = {
  modes: WorldModeChoice[];
  mode: WorldBuildMode;
  setMode: (m: WorldBuildMode) => void;
  hasChat: boolean;
  busy: boolean;
};

export function WorldModeTiles(p: Props) {
  const fallback = defaultModeFor(p.hasChat);
  return (
    <div className="wfw-modes">
      <div className="wfw-tiles three" role="radiogroup" aria-label="Facts only, Faithful or Creative">
        {p.modes.map((m) => {
          const on = m.value === p.mode;
          return (
            <button
              type="button"
              key={m.value}
              role="radio"
              aria-checked={on}
              data-testid={`world-character-mode-${m.value}`}
              className={`wfw-tile${on ? ' on' : ''}`}
              disabled={p.busy}
              onClick={() => p.setMode(m.value)}
            >
              <span className="wfw-tile-title">
                <strong>{m.label}</strong>
                {m.value === fallback && (
                  <span className={`wfw-chip${on ? ' accent' : ''}`}>
                    {p.hasChat ? 'default with a chat' : 'default for Card only'}
                  </span>
                )}
              </span>
              <span className={`small${on ? '' : ' muted'}`}>
                <strong>What it does:</strong> {m.does}
              </span>
              <span className={`small${on ? '' : ' muted'}`}>
                <strong>Never:</strong> {m.never}
              </span>
            </button>
          );
        })}
      </div>
      <span className="muted small">{WORLD_MODE_EXPLAINER}</span>
    </div>
  );
}
