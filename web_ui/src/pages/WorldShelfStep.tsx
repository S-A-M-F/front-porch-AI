// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useState } from 'react';

import {
  shelfBackboneIndices,
  shelfFilterIndices,
  shelfKindCounts,
  shelfKindOf,
  shelfSections,
  WORLD_SHELF_FILTERS,
  type ProposedWorldCard,
  type ProposedWorldPlace,
} from './worldFromWiki';

/** How many of a group's cards show before "Show the other N". */
export const WORLD_SHELF_CARDS_SHOWN = 8;

type Props = {
  proposed: ProposedWorldCard[];
  places: readonly ProposedWorldPlace[];
  signed: Set<number>;
  setSigned: (next: Set<number>) => void;
  climateEnabled: boolean;
  placeClimate: Set<string>;
  setPlaceClimate: (next: Set<string>) => void;
  reviewLine: string;
  revised: boolean;
};

/**
 * The Shelf step: counts and the reviewer's word up top, kind filters,
 * "Only the backbone" for a shorter write, and the places as groups with
 * "Sign all here" / "Unsign all here". Every card starts signed (the page
 * seeds that when the scout lands); the step is a trim, since the Review
 * step at the end is where a written card gets fixed. The desktop twin is
 * WorldFromWikiReviewStep.
 */
export function WorldShelfStep(p: Props) {
  const [filter, setFilter] = useState('');
  const [expanded, setExpanded] = useState<Set<string>>(new Set());
  const counts = shelfKindCounts(p.proposed);
  const sign = (indices: number[], on: boolean) => {
    const next = new Set(p.signed);
    for (const i of indices) {
      if (on) next.add(i);
      else next.delete(i);
    }
    p.setSigned(next);
  };
  return (
    <div className="wfw-shelf" data-testid="world-from-wiki-review">
      <div className="wfw-shelf-head">
        <div>
          <p className="muted">
            Every card they proposed is signed. Untick what you don&apos;t want written; the Review
            step at the end is where the rest gets fixed.
          </p>
        </div>
        <div className="wfw-counts">
          <span className="wfw-count"><strong>{p.proposed.length}</strong><span className="muted small">cards</span></span>
          <span className="wfw-count"><strong>{p.places.length}</strong><span className="muted small">places</span></span>
          <span className="wfw-count accent"><strong>{p.signed.size}</strong><span className="muted small">signed</span></span>
        </div>
      </div>

      {p.reviewLine && (
        <div className="wfw-banner" data-testid="world-shelf-review-line">
          <span aria-hidden="true">{p.revised ? '↻' : '✓'}</span>
          <span>{p.reviewLine}</span>
        </div>
      )}

      <div className="wfw-pills">
        <button type="button" className={`wfw-pill${filter === '' ? ' on' : ''}`} onClick={() => setFilter('')}>
          All {p.proposed.length}
        </button>
        {WORLD_SHELF_FILTERS.map((f) => (
          <button
            type="button"
            key={f.label}
            className={`wfw-pill${filter === f.label ? ' on' : ''}`}
            data-testid={`world-shelf-filter-${f.label}`}
            onClick={() => setFilter(filter === f.label ? '' : f.label)}
          >
            {f.label} {counts[f.label]}
          </button>
        ))}
        <span className="wfw-grow" />
        <button
          type="button"
          className="world-review-link"
          data-testid="world-shelf-only-backbone"
          onClick={() => p.setSigned(new Set(shelfBackboneIndices(p.proposed)))}
        >
          Only the backbone
        </button>
        <span className="muted small">era, places, factions, events: a shorter write</span>
      </div>

      {shelfSections(p.proposed, p.places).map((section, si) => {
        const key = section.place ? section.place.name.toLowerCase() : '';
        const title = section.place ? section.place.name : p.places.length ? 'The world' : 'The shelf';
        const shown = shelfFilterIndices(p.proposed, section.indices, filter);
        const open = expanded.has(key);
        const visible = open ? shown : shown.slice(0, WORLD_SHELF_CARDS_SHOWN);
        const hidden = shown.length - visible.length;
        const signedHere = section.indices.filter((i) => p.signed.has(i)).length;
        const allSigned = signedHere === section.indices.length;
        return (
          <section key={section.place ? `place-${section.place.name}` : `root-${si}`} className="wfw-group">
            <div className="wfw-group-head" data-testid={section.place ? 'world-place-header' : undefined}>
              <strong>{title}</strong>
              {section.place?.parentName && <span className="wfw-chip">inside {section.place.parentName}</span>}
              <span className="wfw-chip">
                {section.indices.length} cards · {signedHere} signed
              </span>
              {section.place?.climateHint && <span className="wfw-chip">Weather hint: {section.place.climateHint}</span>}
              {section.place && p.climateEnabled && (
                <label className="cg-toggle small">
                  <input
                    type="checkbox"
                    checked={p.placeClimate.has(key)}
                    onChange={(e) => {
                      const next = new Set(p.placeClimate);
                      if (e.target.checked) next.add(key);
                      else next.delete(key);
                      p.setPlaceClimate(next);
                    }}
                  />
                  <span>Own weather</span>
                </label>
              )}
              <span className="wfw-grow" />
              <button
                type="button"
                className={`world-review-link${allSigned ? ' muted' : ''}`}
                data-testid={`world-shelf-sign-all-${key || 'root'}`}
                onClick={() => sign(section.indices, !allSigned)}
              >
                {allSigned ? 'Unsign all here' : 'Sign all here'}
              </button>
            </div>
            {visible.length === 0 ? (
              <p className="muted small">Nothing of that kind here.</p>
            ) : (
              <div className="wfw-grid">
                {visible.map((i) => {
                  const c = p.proposed[i];
                  const on = p.signed.has(i);
                  const role = c.role === 'era' || c.role === 'hub' || c.role === 'crown' ? ` · ${c.role}` : '';
                  return (
                    <label key={`${c.name}-${i}`} className={`wfw-shelf-card${on ? ' on' : ''}`}>
                      <input type="checkbox" checked={on} onChange={(e) => sign([i], e.target.checked)} />
                      <span className="wfw-shelf-card-text">
                        <span className="wfw-tile-title">
                          <strong>{c.name}</strong>
                          <span className={`wfw-chip${c.role === 'era' || c.role === 'crown' ? ' accent' : ''}`}>
                            {shelfKindOf(c)}
                            {role}
                          </span>
                        </span>
                        <span className="muted small">
                          {c.group ? `${c.group} · ` : ''}
                          {c.sourceTitles.join(', ')}
                        </span>
                      </span>
                    </label>
                  );
                })}
              </div>
            )}
            {(hidden > 0 || (open && shown.length > WORLD_SHELF_CARDS_SHOWN)) && (
              <button
                type="button"
                className="world-review-link muted world-review-more"
                onClick={() => {
                  const next = new Set(expanded);
                  if (next.has(key)) next.delete(key);
                  else next.add(key);
                  setExpanded(next);
                }}
              >
                {open ? 'Show fewer' : `Show the other ${hidden} card${hidden === 1 ? '' : 's'} in ${title}`}
              </button>
            )}
          </section>
        );
      })}
    </div>
  );
}
