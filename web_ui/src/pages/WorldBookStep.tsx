// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import {
  WORLD_BUILD_MODES,
  WORLD_CHARACTER_NO_DEEP_COPY,
  characterDepthOptions,
  contextChoiceOptions,
  depthOptions,
  wikiHostLabel,
  wikiKindGuess,
  type ChatSourceRow,
  type DepthChoice,
  type WorldBuildMode,
  type WorldModeChoice,
  type WorldWizardSource,
} from './worldFromWiki';
import type { CharacterRow } from './story/setup/draft';
import { WorldModeTiles } from './WorldModeTiles';
import { WorldSourceCard } from './WorldSourceCard';

type Props = {
  /** World from Character: the second card and the mode tiles follow it. */
  source?: WorldWizardSource;
  characters?: CharacterRow[] | null;
  chatRows?: ChatSourceRow[];
  characterId?: string;
  setCharacterId?: (id: string) => void;
  sessionId?: string;
  setSessionId?: (id: string) => void;
  mode?: WorldBuildMode;
  setMode?: (m: WorldBuildMode) => void;
  modes?: WorldModeChoice[];
  copyCardLore?: boolean;
  setCopyCardLore?: (v: boolean) => void;
  characterDepthChoices?: unknown;
  name: string;
  setName: (v: string) => void;
  premise: string;
  setPremise: (v: string) => void;
  moment: string;
  setMoment: (v: string) => void;
  savedWikis: string[];
  wikiUrl: string;
  setWikiUrl: (v: string) => void;
  /** The current wiki's page count once a scout has read it. */
  titleCount: number;
  ranked: boolean;
  contextSize: number;
  chatContextSize?: number;
  contextChoices?: number[];
  depth: number;
  depthChoices?: unknown;
  onContext: (pick: { contextSize?: number; depth?: number }) => void;
  lorebooksOn: boolean;
  setLorebooksOn: (v: boolean) => void;
  climateEnabled: boolean;
  setClimateEnabled: (v: boolean) => void;
  busy: boolean;
};

/**
 * The Book step as four cards with a job each: the world, the wiki, how
 * deep, what to make. The desktop twin is WorldFromWikiBookStep.
 */
export function WorldBookStep(p: Props) {
  const character = p.source === 'character';
  const depths = character ? characterDepthOptions(p.characterDepthChoices) : depthOptions(p.depthChoices);
  const contexts = contextChoiceOptions(p.chatContextSize, p.contextSize, p.contextChoices);
  return (
    <div className={`wfw-book${p.busy ? ' dimmed' : ''}`}>
      <p className="muted">
        {character
          ? 'Name the world, pick the character and one of their chats, say how deep to dig. The chat is skimmed into an index first; the scout proposes a shelf of cards from that, not one card per message.'
          : "Name the world, pick its wiki, say how deep to dig. Scout proposes a shelf of cards from the wiki's index, not one card per page."}
      </p>

      <section className="wfw-card">
        <header className="wfw-card-head">
          <span className="wfw-badge" aria-hidden="true">
            <GlobeIcon />
          </span>
          <strong>The world</strong>
          <span className="muted small wfw-grow-right">1 of 4</span>
        </header>
        <div className="wfw-two">
          <label className="cg-field">
            <span className="cg-field-label">World name</span>
            <input value={p.name} disabled={p.busy} onChange={(e) => p.setName(e.target.value)} />
          </label>
          <label className="cg-field">
            <span className="cg-field-label">One-line premise</span>
            <input
              value={p.premise}
              disabled={p.busy}
              placeholder="The Wandenreich invades Soul Society and the Gotei 13 must answer"
              onChange={(e) => p.setPremise(e.target.value)}
            />
          </label>
        </div>
        <div className="wfw-moment">
          <div className="wfw-moment-head">
            <ClockIcon />
            <strong>Where the story stands</strong>
            <span className="wfw-chip">optional</span>
          </div>
          <input
            data-testid="world-wiki-moment"
            value={p.moment}
            disabled={p.busy}
            placeholder="the night after the first invasion"
            onChange={(e) => p.setMoment(e.target.value)}
          />
          <span className="muted small">
            The point in the story the world is frozen at. Cards are written as things are then; what
            happens after stays unwritten, so you can play it.
          </span>
        </div>
      </section>

      {character ? (
        <WorldSourceCard
          characters={p.characters ?? null}
          chatRows={p.chatRows ?? []}
          characterId={p.characterId ?? ''}
          setCharacterId={p.setCharacterId ?? (() => {})}
          sessionId={p.sessionId ?? ''}
          setSessionId={p.setSessionId ?? (() => {})}
          mode={p.mode ?? 'factsOnly'}
          depth={p.depth}
          busy={p.busy}
        />
      ) : (
      <section className="wfw-card">
        <header className="wfw-card-head">
          <span className="wfw-badge" aria-hidden="true">
            <BookIcon />
          </span>
          <strong>The wiki</strong>
          <span className="muted small wfw-grow-right">2 of 4</span>
        </header>
        {p.savedWikis.length === 0 ? (
          <p className="muted small">No wiki saved yet. Save a Fandom or Tiddly address in Porch Life first.</p>
        ) : (
          <div className="wfw-tiles three" role="radiogroup" aria-label="Wiki">
            {p.savedWikis.map((url) => {
              const on = p.wikiUrl === url;
              const scouted = on && p.titleCount > 0;
              return (
                <button
                  type="button"
                  key={url}
                  role="radio"
                  aria-checked={on}
                  className={`wfw-tile${on ? ' on' : ''}`}
                  disabled={p.busy}
                  onClick={() => p.setWikiUrl(url)}
                >
                  <span className="wfw-tile-title">
                    <span className={`wfw-dot${on ? ' on' : ''}`} aria-hidden="true" />
                    <strong>{wikiHostLabel(url)}</strong>
                  </span>
                  <span className="muted small">
                    {wikiKindGuess(url)}
                    {scouted ? ` · ${p.titleCount} pages${p.ranked ? ' linked most' : ''}` : ''}
                  </span>
                </button>
              );
            })}
          </div>
        )}
        <span className="muted small">Saved wikis are the same list as Porch Life&apos;s web search.</span>
      </section>
      )}

      <section className="wfw-card">
        <header className="wfw-card-head">
          <span className="wfw-badge" aria-hidden="true">
            <LayersIcon />
          </span>
          <strong>How deep</strong>
          <span className="muted small wfw-grow-right">3 of 4</span>
        </header>
        <div className="wfw-tiles three" role="radiogroup" aria-label="Depth">
          {depths.map((d: DepthChoice) => {
            const on = d.value === (character && p.depth === 2 ? 1 : p.depth);
            return (
              <button
                type="button"
                key={d.value}
                role="radio"
                aria-checked={on}
                data-testid={`world-wiki-depth-${d.value}`}
                className={`wfw-tile${on ? ' on' : ''}`}
                disabled={p.busy}
                onClick={() => p.onContext({ depth: d.value })}
              >
                <span className="wfw-tile-title">
                  <strong>{d.label}</strong>
                  <span className={`small wfw-grow-right${on ? ' accent' : ' muted'}`}>{d.cards ? `~${d.cards} cards` : ''}</span>
                </span>
                <span className={`small${on ? '' : ' muted'}`}>{d.blurb ?? ''}</span>
                {d.time && <span className="small">{d.time}</span>}
              </button>
            );
          })}
        </div>
        {character && <span className="muted small">{WORLD_CHARACTER_NO_DEEP_COPY}</span>}
        <div className="wfw-pills" role="radiogroup" aria-label="Context for this wizard">
          <span className="muted small">Context for this wizard</span>
          {contexts.map((o) => {
            const on = o.value === p.contextSize;
            return (
              <button
                type="button"
                key={o.value}
                role="radio"
                aria-checked={on}
                data-testid={`world-wiki-context-${o.value}`}
                className={`wfw-pill${on ? ' on' : ''}`}
                disabled={p.busy}
                onClick={() => p.onContext({ contextSize: o.value })}
              >
                {o.label}
              </button>
            );
          })}
        </div>
        <span className="muted small">
          How much the model may read and write in one go. A bigger window lets a thinking model finish
          the card list in one piece; a smaller one has the index asked in parts.
        </span>
      </section>

      <section className="wfw-card">
        <header className="wfw-card-head">
          <span className="wfw-badge" aria-hidden="true">
            <PenIcon />
          </span>
          <strong>What to make</strong>
          <span className="muted small wfw-grow-right">4 of 4</span>
        </header>
        {character && p.mode && p.setMode && (
          <WorldModeTiles
            modes={p.modes ?? WORLD_BUILD_MODES}
            mode={p.mode}
            setMode={p.setMode}
            hasChat={!!p.sessionId}
            busy={p.busy}
          />
        )}
        <div className="wfw-two">
          <label className="wfw-toggle">
            <BookIcon />
            <span className="wfw-toggle-text">
              <strong>Lorebooks</strong>
              <span className="muted small">They scout a shelf of cards; untick any you don&apos;t want written.</span>
            </span>
            <input type="checkbox" checked={p.lorebooksOn} disabled={p.busy} onChange={(e) => p.setLorebooksOn(e.target.checked)} />
          </label>
          <label className="wfw-toggle">
            <CloudIcon />
            <span className="wfw-toggle-text">
              <strong>Climate</strong>
              <span className="muted small">
                {character
                  ? 'Off by default. On, the weather is read from the chat where it shows one; Creative may guess it from the card and says so.'
                  : 'Off by default. On, each place with its own sky gets its own weather.'}
              </span>
            </span>
            <input type="checkbox" checked={p.climateEnabled} disabled={p.busy} onChange={(e) => p.setClimateEnabled(e.target.checked)} />
          </label>
          {character && p.setCopyCardLore && (
            <label className="wfw-toggle">
              <BookIcon />
              <span className="wfw-toggle-text">
                <strong>Copy the card&apos;s lorebook in</strong>
                <span className="muted small">
                  The character&apos;s own entries ride along unchanged, for one portable file. Off, the new cards chain to them instead.
                </span>
              </span>
              <input
                type="checkbox"
                data-testid="world-character-copy-lore"
                checked={!!p.copyCardLore}
                disabled={p.busy}
                onChange={(e) => p.setCopyCardLore?.(e.target.checked)}
              />
            </label>
          )}
        </div>
      </section>
    </div>
  );
}

const icon = { width: 16, height: 16, viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: 2, strokeLinecap: 'round' as const, strokeLinejoin: 'round' as const };

function GlobeIcon() {
  return (
    <svg {...icon}><circle cx="12" cy="12" r="10" /><path d="M2 12h20" /><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z" /></svg>
  );
}
function BookIcon() {
  return (
    <svg {...icon}><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20" /><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z" /></svg>
  );
}
function LayersIcon() {
  return (
    <svg {...icon}><path d="M12 2L2 7l10 5 10-5-10-5z" /><path d="M2 17l10 5 10-5" /><path d="M2 12l10 5 10-5" /></svg>
  );
}
function PenIcon() {
  return (
    <svg {...icon}><path d="M12 20h9" /><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z" /></svg>
  );
}
function CloudIcon() {
  return (
    <svg {...icon}><path d="M17.5 19a4.5 4.5 0 1 0-.9-8.9A7 7 0 1 0 6 19z" /></svg>
  );
}
function ClockIcon() {
  return (
    <svg {...icon}><circle cx="12" cy="12" r="10" /><path d="M12 6v6l4 2" /></svg>
  );
}
