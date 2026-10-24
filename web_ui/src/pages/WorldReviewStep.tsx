// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useState } from 'react';

import { WorldProgressPanel } from './WorldProgressPanel';
import {
  worldEntryNoteCopy,
  type WorldEntryNote,
  type WorldProgressLine,
  type WorldReviewEntry,
  type WorldReviewPlace,
  type WorldReviewRoot,
} from './worldFromWiki';

/** How many of a place's cards show before "Show the other N". */
export const WORLD_REVIEW_CARDS_SHOWN = 6;

type EntryPatch = { content?: string; key?: string };

type Props = {
  worldName: string;
  root: WorldReviewRoot | null;
  places: WorldReviewPlace[];
  climateEnabled: boolean;
  notes: Record<string, WorldEntryNote>;
  pinned: Set<string>;
  busy: boolean;
  findings: string[];
  direction: string;
  setDirection: (v: string) => void;
  wholeWorld: boolean;
  setWholeWorld: (v: boolean) => void;
  reviewStatus: string;
  onSendBack: () => void;
  onEdit: (name: string, patch: EntryPatch) => void;
  onDrop: (name: string) => void;
  onPin: (name: string) => void;
  onRewrite: (name: string, note: string) => void;
  onAdd: (place: string, name: string, page: string) => void;
  progress: { status: string; log: WorldProgressLine[]; elapsed: string };
};

const lower = (s: string) => s.trim().toLowerCase();

/**
 * The last step before Mint, the desktop's twin: the reviewers' findings,
 * the author's direction box, and every entry grouped by place with its
 * verdict, editable in place, with Rewrite with a note, Drop and Keep.
 */
export function WorldReviewStep(p: Props) {
  const [findingsOpen, setFindingsOpen] = useState(true);
  return (
    <div className="world-review">
      <p className="muted">
        Read what was written, fix what you like by hand, or tell the wizard what to change and send it
        back around the reviewers. Nothing is saved until Mint World.
      </p>

      <section className="world-review-findings">
        <div className="world-review-findings-head">
          <strong>What the reviewers did this run</strong>
          <button type="button" className="world-review-link" onClick={() => setFindingsOpen((o) => !o)}>
            {findingsOpen ? 'Hide' : 'Show'}
          </button>
        </div>
        {findingsOpen &&
          (p.findings.length === 0 ? (
            <p className="muted small" data-testid="world-review-findings">
              Every entry passed the reviewer first time, and the shelf was never sent back.
            </p>
          ) : (
            <ul className="muted small" data-testid="world-review-findings">
              {p.findings.map((f, i) => (
                <li key={i}>{f}</li>
              ))}
            </ul>
          ))}
      </section>

      <section className="world-review-direction">
        <strong>Your direction</strong>
        <p className="muted small">
          In your own words. Your note goes into the same loop the reviewers use: the cards it names are
          rewritten and reviewed again, a card it asks for is written from its page, the rest stay as they
          are.
        </p>
        <textarea
          data-testid="world-from-wiki-direction"
          rows={3}
          value={p.direction}
          disabled={p.busy}
          placeholder="e.g. The Royal Guard card should name all four, not just Ichibe. Karakura needs the Kurosaki Clinic."
          onChange={(e) => p.setDirection(e.target.value)}
        />
        <div className="world-review-scope">
          <span className="muted small">Apply to</span>
          <label>
            <input
              type="radio"
              name="world-review-scope"
              checked={!p.wholeWorld}
              disabled={p.busy}
              onChange={() => p.setWholeWorld(false)}
            />{' '}
            The cards my note names
          </label>
          <label>
            <input
              type="radio"
              name="world-review-scope"
              checked={p.wholeWorld}
              disabled={p.busy}
              onChange={() => p.setWholeWorld(true)}
            />{' '}
            The whole world
          </label>
          <button
            type="button"
            className="world-review-outline"
            data-testid="world-from-wiki-send-back"
            disabled={p.busy || !p.direction.trim()}
            onClick={p.onSendBack}
          >
            Send it back around
          </button>
        </div>
        {p.reviewStatus && !p.busy && (
          <p className="small" data-testid="world-review-status">
            {p.reviewStatus}
          </p>
        )}
      </section>

      {p.busy && (
        <WorldProgressPanel
          status={p.progress.status}
          fallback="Working…"
          log={p.progress.log}
          elapsed={p.progress.elapsed}
        />
      )}

      <PlaceSection
        key="root"
        placeKey=""
        name={p.worldName.trim() || 'The world'}
        kind="world"
        description={p.root?.description ?? ''}
        climate={p.climateEnabled}
        entries={p.root?.entries ?? []}
        {...p}
      />
      {p.places.map((pl) => (
        <PlaceSection
          key={pl.name}
          placeKey={pl.name}
          name={pl.name}
          kind={pl.parentName ? `place · inside ${pl.parentName}` : 'place'}
          description={pl.description}
          climate={!!pl.biome}
          entries={pl.entries}
          {...p}
        />
      ))}
    </div>
  );
}

function PlaceSection(
  p: Props & {
    placeKey: string;
    name: string;
    kind: string;
    description: string;
    climate: boolean;
    entries: WorldReviewEntry[];
  },
) {
  const [open, setOpen] = useState(false);
  const [addOpen, setAddOpen] = useState(false);
  const [addName, setAddName] = useState('');
  const [addPage, setAddPage] = useState('');
  const shown = open ? p.entries : p.entries.slice(0, WORLD_REVIEW_CARDS_SHOWN);
  const hidden = p.entries.length - shown.length;
  return (
    <section className="world-review-place" data-testid={`world-review-place-${p.placeKey || 'root'}`}>
      <div className="world-review-place-head">
        <div>
          <div className="world-review-place-title">
            <strong>{p.name}</strong>
            <span className="world-review-chip">{p.kind}</span>
            <span className="world-review-chip">
              {p.entries.length} card{p.entries.length === 1 ? '' : 's'}
            </span>
            <span className="world-review-chip">{p.climate ? 'own weather' : 'weather from above'}</span>
          </div>
          {p.description && <p className="muted small">{p.description}</p>}
        </div>
        <button
          type="button"
          className="world-review-link"
          data-testid={`world-review-add-${p.placeKey || 'root'}`}
          disabled={p.busy}
          onClick={() => setAddOpen((o) => !o)}
        >
          + Add a card here
        </button>
      </div>
      {addOpen && (
        <div className="world-review-add">
          <span className="muted small">
            Add a card here: a name, and which wiki page to read (the name itself when blank)
          </span>
          <div className="world-review-add-row">
            <input
              data-testid={`world-review-add-name-${p.placeKey || 'root'}`}
              placeholder="Kurosaki Clinic"
              value={addName}
              onChange={(e) => setAddName(e.target.value)}
            />
            <input placeholder="wiki page title (optional)" value={addPage} onChange={(e) => setAddPage(e.target.value)} />
            <button
              type="button"
              className="primary"
              data-testid={`world-review-add-send-${p.placeKey || 'root'}`}
              disabled={p.busy || !addName.trim()}
              onClick={() => {
                p.onAdd(p.placeKey, addName.trim(), addPage.trim());
                setAddName('');
                setAddPage('');
                setAddOpen(false);
              }}
            >
              Write it
            </button>
          </div>
        </div>
      )}
      {p.entries.length === 0 ? (
        <p className="muted small">No cards here yet.</p>
      ) : (
        <div className="world-review-grid">
          {shown.map((e) => (
            <EntryCard key={e.name} entry={e} {...p} />
          ))}
        </div>
      )}
      {(hidden > 0 || open) && p.entries.length > WORLD_REVIEW_CARDS_SHOWN && (
        <button type="button" className="world-review-link world-review-more" onClick={() => setOpen((o) => !o)}>
          {open ? 'Show fewer' : `Show the other ${hidden} card${hidden === 1 ? '' : 's'} in ${p.name}`}
        </button>
      )}
    </section>
  );
}

function EntryCard(p: Props & { entry: WorldReviewEntry }) {
  const [noteOpen, setNoteOpen] = useState(false);
  const [note, setNote] = useState('');
  const [keyOpen, setKeyOpen] = useState(false);
  const [newKey, setNewKey] = useState('');
  const name = p.entry.name;
  const pinned = p.pinned.has(lower(name));
  const n = p.notes[lower(name)];
  const keys = (p.entry.key || '')
    .split(',')
    .map((k) => k.trim())
    .filter(Boolean);
  let verdict: string;
  let tone: string;
  if (pinned) {
    verdict = 'Kept as it is · a send-back never touches it';
    tone = 'kept';
  } else if (!n) {
    verdict = worldEntryNoteCopy(undefined);
    tone = 'kept';
  } else if (!n.passed) {
    verdict = worldEntryNoteCopy(n);
    tone = 'failing';
  } else if (n.tries > 1) {
    verdict = worldEntryNoteCopy(n);
    tone = 'rewritten';
  } else {
    verdict = worldEntryNoteCopy(n);
    tone = 'passed';
  }
  return (
    <article
      className={`world-review-card${pinned ? ' pinned' : ''}${noteOpen ? ' noting' : ''}`}
      data-testid={`world-entry-${name}`}
    >
      <div className="world-review-card-head">
        <strong>{name}</strong>
        <span className="world-review-grow" />
        <button
          type="button"
          className={`world-review-pin${pinned ? ' on' : ''}`}
          aria-label={pinned ? 'Kept as it is; press to unpin' : 'Keep this card as it is'}
          data-testid={`world-entry-pin-${name}`}
          disabled={p.busy}
          onClick={() => p.onPin(name)}
        >
          <svg aria-hidden="true" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M12 17v5" />
            <path d="M9 11V4h6v7l2 2v2H7v-2z" />
          </svg>
        </button>
      </div>
      <div className="world-review-keys">
        {keys.map((k) => (
          <span key={k} className="world-review-key">
            {k}
            <button
              type="button"
              aria-label={`Remove key ${k}`}
              disabled={p.busy}
              onClick={() => p.onEdit(name, { key: keys.filter((x) => x !== k).join(', ') })}
            >
              ×
            </button>
          </span>
        ))}
        {keyOpen ? (
          <input
            className="world-review-key-input"
            autoFocus
            placeholder="a name a chat would say"
            value={newKey}
            onChange={(e) => setNewKey(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                const k = newKey.trim();
                if (k) p.onEdit(name, { key: [...keys, k].join(', ') });
                setNewKey('');
                setKeyOpen(false);
              } else if (e.key === 'Escape') {
                setNewKey('');
                setKeyOpen(false);
              }
            }}
          />
        ) : (
          <button type="button" className="world-review-key add" disabled={p.busy} onClick={() => setKeyOpen(true)}>
            + key
          </button>
        )}
      </div>
      <textarea
        data-testid={`world-entry-content-${name}`}
        rows={3}
        value={p.entry.content}
        disabled={p.busy}
        onChange={(e) => p.onEdit(name, { content: e.target.value })}
      />
      <p className={`world-review-verdict ${tone}`} data-testid={`world-entry-verdict-${name}`}>
        {verdict}
      </p>
      {noteOpen && (
        <div className="world-review-note">
          <span className="muted small">Rewrite this card with a note</span>
          <textarea
            data-testid={`world-entry-note-${name}`}
            rows={2}
            autoFocus
            placeholder="e.g. Say they were sealed in the palace by Yhwach's order."
            value={note}
            onChange={(e) => setNote(e.target.value)}
          />
          <div className="world-review-row">
            <button
              type="button"
              className="primary"
              data-testid={`world-entry-rewrite-send-${name}`}
              disabled={p.busy || !note.trim()}
              onClick={() => {
                p.onRewrite(name, note.trim());
                setNote('');
                setNoteOpen(false);
              }}
            >
              Rewrite this card
            </button>
            <button type="button" onClick={() => { setNote(''); setNoteOpen(false); }}>
              Cancel
            </button>
          </div>
        </div>
      )}
      <div className="world-review-row">
        {!noteOpen && (
          <button
            type="button"
            className="world-review-link"
            data-testid={`world-entry-rewrite-${name}`}
            disabled={p.busy}
            onClick={() => setNoteOpen(true)}
          >
            Rewrite…
          </button>
        )}
        <button
          type="button"
          className="world-review-link muted"
          data-testid={`world-entry-drop-${name}`}
          disabled={p.busy}
          onClick={() => p.onDrop(name)}
        >
          Drop
        </button>
      </div>
    </article>
  );
}
