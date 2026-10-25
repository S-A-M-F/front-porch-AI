// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// HuggingFace model browser + the live download queue. Matches the desktop
// manager: per-task pause / resume / cancel, bulk pause-all / resume-all /
// clear-completed, an overall progress bar, and per-task size / ETA / errors.
// Progress is polled (1.2s) only while something is active.

import { useCallback, useEffect, useRef, useState } from 'react';
import { api, ApiError } from '../../api/client';
import { type HFModel, type HFFile, type HFFilesProblem, type Download, type DownloadsState, fmtSize, fmtEta } from './types';
import { ModelCardDialog } from './ModelCardDialog';

const EMPTY: DownloadsState = { downloads: [], overallProgress: 0, overallSpeed: 0, activeCount: 0 };
const ACTIVE = new Set(['downloading', 'pending', 'verifying']);

// The host's HfSort / HfSizeBucket names; the labels match the desktop filter row.
const SORTS = [
  ['downloads', 'Most downloaded'],
  ['likes', 'Most liked'],
  ['newest', 'Recently updated'],
  ['trending', 'Trending'],
] as const;
const SIZES = [
  ['any', 'Any size'],
  ['small', 'Up to 13B'],
  ['medium', '14B to 34B'],
  ['large', '35B and up'],
] as const;
type Filters = { sort: string; rp: boolean; size: string };

// The desktop card's wording for an empty file list.
const PROBLEM_TEXT: Record<HFFilesProblem | 'none', string> = {
  gated: 'Gated repo — accept its licence on huggingface.co, then add a HuggingFace token in Settings → Backend',
  notFound: 'This repo is gone or was renamed',
  network: 'Could not load the file list — check your connection',
  none: 'No GGUF files available',
};
const DEFAULT_FILTERS: Filters = { sort: 'downloads', rp: false, size: 'any' };

/** The search URL; filters at their defaults are left off so it reads like an old PWA's. */
function hfSearchPath(q: string, f: Filters): string {
  const params = new URLSearchParams({ q });
  if (f.sort !== DEFAULT_FILTERS.sort) params.set('sort', f.sort);
  if (f.rp) params.set('rp', '1');
  if (f.size !== DEFAULT_FILTERS.size) params.set('size', f.size);
  return `/api/backend/hf/search?${params.toString().replace(/\+/g, '%20')}`;
}

export function ModelDownloads({
  query,
  setQuery,
  searchNonce,
  onError,
}: {
  query: string;
  setQuery: (q: string) => void;
  searchNonce: number;
  onError: (s: string) => void;
}) {
  const [results, setResults] = useState<HFModel[]>([]);
  const [searching, setSearching] = useState(false);
  const [expanded, setExpanded] = useState<string | null>(null);
  // The repo whose model card is open, if any.
  const [cardRepo, setCardRepo] = useState<string | null>(null);
  const [files, setFiles] = useState<HFFile[]>([]);
  // Shown instead of "Loading files…" once an expand comes back empty.
  const [filesNote, setFilesNote] = useState<string | null>(null);
  const [dl, setDl] = useState<DownloadsState>(EMPTY);

  const loadDownloads = useCallback(
    () => api.get<DownloadsState>('/api/backend/downloads').then(setDl).catch(() => {}),
    [],
  );
  useEffect(() => {
    void loadDownloads();
  }, [loadDownloads]);

  const hasActive = dl.downloads.some((d) => ACTIVE.has(d.state));
  useEffect(() => {
    if (!hasActive) return;
    const t = setInterval(() => void loadDownloads(), 1200);
    return () => clearInterval(t);
  }, [hasActive, loadDownloads]);

  const [filters, setFilters] = useState<Filters>(DEFAULT_FILTERS);
  // Bumped per search / expand: an answer that arrives after a newer request is dropped.
  const searchSeq = useRef(0);
  const filesSeq = useRef(0);

  const search = useCallback(
    (q: string, f: Filters = filters) => {
      const t = q.trim();
      if (!t) return;
      const seq = ++searchSeq.current;
      setSearching(true);
      setExpanded(null);
      api.get<{ models: HFModel[] }>(hfSearchPath(t, f))
        .then((r) => {
          if (seq === searchSeq.current) setResults(r.models);
        })
        .catch((e) => {
          if (seq === searchSeq.current) onError(e instanceof ApiError ? e.message : 'Search failed');
        })
        .finally(() => {
          if (seq === searchSeq.current) setSearching(false);
        });
    },
    [onError, filters],
  );

  const changeFilters = (f: Filters) => {
    setFilters(f);
    if (query.trim()) search(query, f);
  };

  // A recommended-chip click (HardwarePanel) bumps searchNonce → run that search.
  useEffect(() => {
    if (searchNonce > 0) search(query);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [searchNonce]);

  const expand = (id: string) => {
    if (expanded === id) {
      setExpanded(null);
      return;
    }
    setExpanded(id);
    setFiles([]);
    setFilesNote(null);
    const seq = ++filesSeq.current;
    api.get<{ files: HFFile[]; problem?: HFFilesProblem | null }>(`/api/backend/hf/files?repoId=${encodeURIComponent(id)}`)
      .then((r) => {
        if (seq !== filesSeq.current) return;
        setFiles(r.files);
        if (r.files.length === 0) setFilesNote(PROBLEM_TEXT[r.problem ?? 'none']);
      })
      .catch(() => {
        if (seq === filesSeq.current) setFilesNote(PROBLEM_TEXT.network);
      });
  };

  // Every queue mutation returns the fresh DownloadsState — just swap it in.
  const mutate = (p: Promise<DownloadsState>) =>
    p.then(setDl).catch((e) => onError(e instanceof ApiError ? e.message : 'Action failed'));
  const download = (f: HFFile) =>
    mutate(api.post<DownloadsState>('/api/backend/downloads', { repoId: f.repoId, filename: f.filename }));
  const taskAct = (id: string, verb: string) => mutate(api.post<DownloadsState>(`/api/backend/downloads/${id}/${verb}`));
  const bulk = (verb: string) => mutate(api.post<DownloadsState>(`/api/backend/downloads/${verb}`));

  const hasCompleted = dl.downloads.some((d) => ['completed', 'failed', 'cancelled'].includes(d.state));

  return (
    <section className="card">
      <h3>Download models (HuggingFace)</h3>

      {dl.downloads.length > 0 && (
        <div className="dl-queue">
          {dl.activeCount > 0 && (
            <div className="dl-overall">
              <div className="dl-overall-head">
                <span className="muted small">{dl.activeCount} active · {fmtSize(dl.overallSpeed)}/s</span>
                <span className="muted small">{Math.round(dl.overallProgress * 100)}%</span>
              </div>
              <div className="stat-track"><div className="stat-fill" style={{ width: `${Math.round(dl.overallProgress * 100)}%` }} /></div>
            </div>
          )}
          <div className="dl-bulk">
            <button className="ghost small-btn" onClick={() => bulk('pause-all')}>Pause all</button>
            <button className="ghost small-btn" onClick={() => bulk('resume-all')}>Resume all</button>
            {hasCompleted && <button className="ghost small-btn" onClick={() => bulk('clear-completed')}>Clear finished</button>}
          </div>
          <ul className="download-list">
            {dl.downloads.map((d) => (
              <DownloadRow key={d.id} d={d} onAct={taskAct} />
            ))}
          </ul>
        </div>
      )}

      <div className="tool-row">
        <input
          placeholder="Search GGUF models…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && search(query)}
        />
        <button className="primary" disabled={searching} onClick={() => search(query)}>{searching ? '…' : 'Search'}</button>
      </div>
      <div className="hf-filters" data-testid="hf-filters">
        <select
          aria-label="Sort results"
          value={filters.sort}
          onChange={(e) => changeFilters({ ...filters, sort: e.target.value })}
        >
          {SORTS.map(([v, label]) => <option key={v} value={v}>{label}</option>)}
        </select>
        <label className="hf-rp-only">
          <input type="checkbox" checked={filters.rp} onChange={(e) => changeFilters({ ...filters, rp: e.target.checked })} />
          Roleplay only
        </label>
        <select
          aria-label="Model size"
          value={filters.size}
          onChange={(e) => changeFilters({ ...filters, size: e.target.value })}
        >
          {SIZES.map(([v, label]) => <option key={v} value={v}>{label}</option>)}
        </select>
      </div>

      <ul className="hf-list">
        {results.map((m) => (
          <li key={m.id} className="card hf-row">
            <button className="hf-head" onClick={() => expand(m.id)}>
              <strong>{m.name}</strong>
              <span className="muted small">
                {m.author} · ♥ {m.likes} · ↓ {m.downloads}
                {m.roleplay && <span className="badge hf-rp">Roleplay</span>}
              </span>
            </button>
            {expanded === m.id && (
              <div className="hf-card-row">
                <button type="button" className="ghost small-btn" onClick={() => setCardRepo(m.id)}>
                  📄 Model card
                </button>
              </div>
            )}
            {expanded === m.id && (
              <ul className="file-list">
                {files.length === 0 ? (
                  <li className="muted small" data-testid="hf-files-note">{filesNote ?? 'Loading files…'}</li>
                ) : (
                  <>
                    {files.filter((f) => f.kind !== 'projector').map((f) => (
                      <FileRow key={f.filename} f={f} onDownload={download} />
                    ))}
                    {files.some((f) => f.kind === 'projector') && (
                      <li className="muted small hf-addon-head">
                        Vision add-on — lets the model see images; paired with what you download from this repo
                      </li>
                    )}
                    {files.filter((f) => f.kind === 'projector').map((f) => (
                      <FileRow key={f.filename} f={f} onDownload={download} />
                    ))}
                  </>
                )}
              </ul>
            )}
          </li>
        ))}
      </ul>
      {cardRepo && <ModelCardDialog repoId={cardRepo} onClose={() => setCardRepo(null)} />}
    </section>
  );
}

/** One quant: name (with its part count), size and the desktop's VRAM fit line. */
function FileRow({ f, onDownload }: { f: HFFile; onDownload: (f: HFFile) => void }) {
  const name = f.parts && f.parts > 1 ? `${f.title ?? f.filename} · ${f.parts} parts` : (f.title ?? f.filename);
  const incomplete = f.complete === false;
  return (
    <li className={`hf-file fit-${f.fit ?? 'unknown'}`}>
      <span className="small">
        {name}
        {f.bestFit && <span className="badge hf-best">Best fit</span>}
        <span className="muted"> ({fmtSize(f.sizeBytes)} · {f.quant})</span>
        {f.fitText && <span className="hf-fit muted">{f.fitText}</span>}
      </span>
      {incomplete ? (
        <span className="muted small" title="Incomplete upload: not every part is on HuggingFace yet">⊘</span>
      ) : (
        <button className="icon-btn" title="Download" onClick={() => onDownload(f)}>⬇</button>
      )}
    </li>
  );
}

function DownloadRow({ d, onAct }: { d: Download; onAct: (id: string, verb: string) => void }) {
  const pct = Math.round(d.progress * 100);
  const sizeLabel =
    d.totalBytes > 0 ? `${fmtSize(d.bytesDownloaded)} / ${fmtSize(d.totalBytes)}` : '';
  const detail =
    d.state === 'downloading'
      ? `${pct}% · ${fmtSize(d.speedBytesPerSec)}/s · ETA ${fmtEta(d.etaSeconds)}`
      : d.state === 'paused'
        ? `Paused · ${pct}%`
        : d.state === 'failed'
          ? `Failed${d.errorMessage ? `: ${d.errorMessage}` : ''}`
          : d.status;

  return (
    <li className={`dl-item state-${d.state}`}>
      <div className="dl-head">
        <span className="dl-name" title={d.repoId ?? undefined}>{d.filename}</span>
        <div className="dl-controls">
          {d.state === 'downloading' && <button className="icon-btn" title="Pause" onClick={() => onAct(d.id, 'pause')}>⏸</button>}
          {(d.state === 'paused' || d.state === 'failed') && <button className="icon-btn" title="Resume" onClick={() => onAct(d.id, 'resume')}>▶</button>}
          {!['completed', 'cancelled'].includes(d.state) && <button className="icon-btn" title="Cancel" onClick={() => onAct(d.id, 'cancel')}>✕</button>}
        </div>
      </div>
      <div className="dl-sub">
        <span className={`muted small${d.state === 'failed' ? ' dl-err' : ''}`}>{detail}</span>
        {sizeLabel && <span className="muted small">{sizeLabel}</span>}
      </div>
      <div className="stat-track"><div className={`stat-fill${d.state === 'failed' ? ' danger' : ''}`} style={{ width: `${pct}%` }} /></div>
    </li>
  );
}
