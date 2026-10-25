// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The model downloader's "Model card" on the phone: the repo's README and its
// facts (licence, last update, the model it was made from), with a way
// through to the original's card. Same content as the desktop dialog; the
// host fetches and cleans it (GET /api/backend/hf/card).

import { useEffect, useState } from 'react';
import { api } from '../../api/client';
import { Dialog } from '../../pages/story/setup/primitives';
import { ModelCardMarkdown } from './ModelCardMarkdown';
import '../../styles/studio.css';

interface Card {
  repoId: string;
  markdown: string;
  license: string | null;
  baseModels: string[];
  lastModified: string | null;
  problem: 'gated' | 'notFound' | 'network' | null;
}

const PROBLEM: Record<NonNullable<Card['problem']>, string> = {
  gated: 'Gated repo — accept its licence on huggingface.co, then add a HuggingFace token in Settings → Backend to read its card here.',
  notFound: 'This repo is gone or was renamed.',
  network: 'Could not load the model card — check your connection.',
};

export function ModelCardDialog({ repoId, onClose }: { repoId: string; onClose: () => void }) {
  const [trail, setTrail] = useState([repoId]);
  const current = trail[trail.length - 1];
  const [card, setCard] = useState<Card | null>(null);

  useEffect(() => {
    let live = true;
    setCard(null);
    api
      .get<Card>(`/api/backend/hf/card?repoId=${encodeURIComponent(current)}`)
      .then((c) => live && setCard(c))
      .catch(() => live && setCard({ repoId: current, markdown: '', license: null, baseModels: [], lastModified: null, problem: 'network' }));
    return () => {
      live = false;
    };
  }, [current]);

  const note = card?.problem ? PROBLEM[card.problem] : card && !card.markdown ? 'This repo has no model card.' : null;
  return (
    <Dialog
      title="Model card"
      onClose={onClose}
      testid="model-card-dialog"
      actions={<button type="button" className="s-btn-ghost" onClick={onClose}>Close</button>}
    >
      <div className="s-w720 model-card">
        <div className="model-card-head">
          {trail.length > 1 && (
            <button type="button" className="ghost small-btn" onClick={() => setTrail(trail.slice(0, -1))}>
              ← Back
            </button>
          )}
          <strong className="model-card-repo">{current}</strong>
          <a href={`https://huggingface.co/${current}`} target="_blank" rel="noopener noreferrer" className="small">
            Open on HuggingFace
          </a>
        </div>
        {!card ? (
          <p className="muted small">Loading the model card…</p>
        ) : (
          <>
            <div className="model-card-facts muted small">
              {card.license && <span>Licence: {card.license}</span>}
              {card.lastModified && <span>Updated {card.lastModified.slice(0, 10)}</span>}
              {card.baseModels
                .filter((b) => b !== card.repoId)
                .map((b) => (
                  <button key={b} type="button" className="ghost small-btn" onClick={() => setTrail([...trail, b])}>
                    Original: {b}
                  </button>
                ))}
            </div>
            {note ? <p className="muted small" data-testid="model-card-note">{note}</p> : <ModelCardMarkdown source={card.markdown} />}
          </>
        )}
      </div>
    </Dialog>
  );
}
