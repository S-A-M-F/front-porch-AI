// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// World-from-wiki review shelf: proposed cards, not a wiki table of contents.

import type { LoreEntry } from '../components/LoreEntriesEditor';

export const WORLD_FROM_WIKI_STEPS = ['Book', 'Shelf', 'Write', 'Review'];

/** Chat's own tool check for the chat model, as the host reports it. */
export type WorldToolsGate =
  | 'ready'
  | 'checking'
  | 'notRunning'
  | 'notChecked'
  | 'failed';

const TOOLS_GATES: readonly WorldToolsGate[] = [
  'ready',
  'checking',
  'notRunning',
  'notChecked',
  'failed',
];

/** Older hosts sent only `toolsAdvertised`; an unknown name is not ready. */
export function parseWorldToolsGate(raw: unknown, toolsAdvertised?: unknown): WorldToolsGate {
  if (typeof raw === 'string' && (TOOLS_GATES as readonly string[]).includes(raw)) {
    return raw as WorldToolsGate;
  }
  return toolsAdvertised === true ? 'ready' : 'notChecked';
}

/** Same words as the desktop wizard (its phone wording). Null = may run. */
export function worldToolsCopy(gate: WorldToolsGate): string | null {
  switch (gate) {
    case 'ready':
      return null;
    case 'checking':
      return 'Checking whether this model can use tools…';
    case 'notRunning':
      return 'This wizard needs a model that can use tools, and the app checks that by asking the model itself, so it has to be running first. Start it on the Models page (or connect your online provider), and the check runs by itself.';
    case 'notChecked':
      return "This model hasn't been checked for tools yet. Next checks it first (on a local server that loads the model), or press Check now.";
    case 'failed':
      return "This model was tested and didn't answer the tool-calling check correctly, so it can't be used for World from Wiki. Next (or Check now) asks it again; if it still answers in words, pick a different model (for example Qwen 3 or Gemma 4).";
  }
}

/**
 * Next may go: the model passed, nothing has asked it yet, or it failed once
 * (Next asks it again rather than trusting a "no").
 */
export function worldToolsAllowNext(gate: WorldToolsGate): boolean {
  return gate === 'ready' || gate === 'notChecked' || gate === 'failed';
}

/**
 * The pill's "ask again": nothing has asked the model yet, or it failed once
 * (a prose answer mid-load, say) and should not lock the wizard until the
 * user changes models.
 */
export function worldToolsCanRetest(gate: WorldToolsGate): boolean {
  return gate === 'notChecked' || gate === 'failed';
}

/** One line of what the host was doing, stamped with the time since the run started. */
export type WorldProgressLine = { at: string; text: string };

/** How many progress lines are kept; older ones fall off the top. */
export const WORLD_PROGRESS_KEEP = 12;

/** Clock-face elapsed time for the panel: 0:42, 12:05, 1:03:09. */
export function worldElapsedLabel(ms: number): string {
  const total = Math.max(0, Math.floor(ms / 1000));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const ss = String(s).padStart(2, '0');
  return h > 0 ? `${h}:${String(m).padStart(2, '0')}:${ss}` : `${m}:${ss}`;
}

/**
 * One more line from the host (the same line twice in a row is kept once),
 * stamped with the elapsed time, the log held to the last WORLD_PROGRESS_KEEP.
 */
export function pushWorldProgress(
  log: WorldProgressLine[],
  text: string,
  elapsedMs: number,
): WorldProgressLine[] {
  const line = text.trim();
  if (!line || (log.length > 0 && log[log.length - 1].text === line)) return log;
  const next = [...log, { at: worldElapsedLabel(elapsedMs), text: line }];
  return next.length > WORLD_PROGRESS_KEEP ? next.slice(next.length - WORLD_PROGRESS_KEEP) : next;
}

export type WorldCraftRole = 'era' | 'hub' | 'leaf' | 'crown';

export type ProposedWorldCard = {
  name: string;
  keys: string[];
  role: WorldCraftRole;
  sourceTitles: string[];
  group?: string;
  /** Slice 8: the scout-named place this card belongs to; undefined
   * for the root book (and for every card on an untagged wiki). */
  place?: string;
  /** What the card is about (place, faction, event, concept, race, item,
   * person); undefined from an older server. */
  kind?: string;
};

export const WORLD_CARD_KINDS = ['place', 'faction', 'event', 'concept', 'race', 'item', 'person'];

/** A place the scout named from tags/categories — the web twin of
 * WorldProposedPlace. The server sends them in build order. */
export type ProposedWorldPlace = {
  name: string;
  keys: string[];
  sourceTitles: string[];
  parentName: string;
  climateHint: string;
};

export function parseProposedPlaces(raw: unknown): ProposedWorldPlace[] {
  if (!Array.isArray(raw)) return [];
  const out: ProposedWorldPlace[] = [];
  for (const item of raw) {
    if (!item || typeof item !== 'object') continue;
    const row = item as Record<string, unknown>;
    const name = String(row.name ?? '').trim();
    if (!name) continue;
    out.push({
      name,
      keys: stringList(row.keys),
      sourceTitles: stringList(row.sourceTitles ?? row.source_titles).slice(0, 4),
      parentName:
        String(row.parentName ?? row.parent_place ?? row.parent ?? '').trim(),
      climateHint: String(row.climateHint ?? row.climate_hint ?? '').trim(),
    });
    if (out.length >= 8) break;
  }
  return out;
}

/** Shelf order for the grouped review: root cards first, then each
 * place's block. Cards naming an unknown place ride the root —
 * grouping is total, a card never vanishes (desktop twin). */
export function shelfSections(
  proposed: ProposedWorldCard[],
  places: readonly ProposedWorldPlace[],
): { place: ProposedWorldPlace | null; indices: number[] }[] {
  if (!places.length) {
    return [{ place: null, indices: proposed.map((_, i) => i) }];
  }
  const known = new Set(places.map((p) => p.name.toLowerCase()));
  const buckets = new Map<string, number[]>();
  const root: number[] = [];
  for (const p of places) buckets.set(p.name.toLowerCase(), []);
  proposed.forEach((card, i) => {
    const pk = (card.place ?? '').trim().toLowerCase();
    if (pk && known.has(pk)) buckets.get(pk)!.push(i);
    else root.push(i);
  });
  return [
    { place: null, indices: root },
    ...places
      .map((p) => ({ place: p, indices: buckets.get(p.name.toLowerCase())! }))
      .filter((section) => section.indices.length > 0),
  ];
}

export function parseProposedCards(raw: unknown): ProposedWorldCard[] {
  if (!Array.isArray(raw)) return [];
  const out: ProposedWorldCard[] = [];
  for (const item of raw) {
    if (!item || typeof item !== 'object') continue;
    const row = item as Record<string, unknown>;
    const name = String(row.name ?? '').trim();
    const role = String(row.role ?? '').trim() as WorldCraftRole;
    if (!name || !['era', 'hub', 'leaf', 'crown'].includes(role)) continue;
    const sourceTitles = stringList(row.sourceTitles ?? row.source_titles).slice(0, 3);
    if (!sourceTitles.length) continue;
    out.push({
      name,
      keys: stringList(row.keys),
      role,
      sourceTitles,
      group: String(row.group ?? '').trim() || undefined,
      place: String(row.place ?? '').trim() || undefined,
      kind: (() => {
        const k = String(row.kind ?? '').trim().toLowerCase();
        return WORLD_CARD_KINDS.includes(k) ? k : undefined;
      })(),
    });
  }
  return out;
}

/** Review is a signed shelf. Never select-all on the wiki title list. */
export function signedCards(
  proposed: ProposedWorldCard[],
  signed: ReadonlySet<number>,
): ProposedWorldCard[] {
  return proposed.filter((_, i) => signed.has(i));
}

const REVIEW_STEP = 1;
const WRITE_STEP = 2;
const PREVIEW_STEP = 3;

export function canOpenWorldFromWikiReview(opts: {
  lorebooksOn: boolean;
  proposedCount: number;
}): boolean {
  return opts.lorebooksOn && opts.proposedCount > 0;
}

export function canOpenWorldFromWikiWrite(opts: {
  lorebooksOn: boolean;
  signedCount: number;
}): boolean {
  return opts.lorebooksOn && opts.signedCount > 0;
}

export function canOpenWorldFromWikiPreview(opts: {
  lorebooksOn: boolean;
  aborted: boolean;
  entryCount: number;
}): boolean {
  if (opts.aborted) return false;
  if (!opts.lorebooksOn) return true;
  return opts.entryCount > 0;
}

/** Linear safety: Review needs a scout, Write needs a signed shelf, Preview needs a write. */
export function jumpWorldFromWikiStep(
  next: number,
  current: number,
  opts: {
    lorebooksOn: boolean;
    aborted: boolean;
    entryCount: number;
    proposedCount?: number;
    signedCount?: number;
    previewStep?: number;
  },
): number {
  const proposedCount = opts.proposedCount ?? 0;
  const signedCount = opts.signedCount ?? 0;
  const preview = opts.previewStep ?? PREVIEW_STEP;
  if (
    next === REVIEW_STEP &&
    !canOpenWorldFromWikiReview({
      lorebooksOn: opts.lorebooksOn,
      proposedCount,
    })
  ) {
    return current;
  }
  if (
    next === WRITE_STEP &&
    !canOpenWorldFromWikiWrite({
      lorebooksOn: opts.lorebooksOn,
      signedCount,
    })
  ) {
    return current;
  }
  if (next === preview && !canOpenWorldFromWikiPreview(opts)) return current;
  return next;
}

function stringList(raw: unknown): string[] {
  if (Array.isArray(raw)) {
    return raw.map((e) => String(e).trim()).filter(Boolean);
  }
  if (typeof raw === 'string' && raw.trim()) {
    return raw.split(',').map((s) => s.trim()).filter(Boolean);
  }
  return [];
}

/** The relay's own words for an empty shelf when the model never answered
 * (token limit, busy server, unreadable call); the premise line is for a
 * real empty answer only. Twin of the desktop wizard's `result.failure`. */
export function emptyScoutCopy(failure: unknown): string {
  if (typeof failure === 'string' && failure.trim()) return failure.trim();
  return 'The scout returned no cards. Try a clearer premise, or another wiki.';
}

/** The Book step's context sizes besides "Same as chat" (twin of the desktop list). */
export const WORLD_WIKI_CONTEXT_CHOICES = [16384, 32768, 65536, 131072, 262144];

/** "64K" for 65536; a number that is not whole K stays as digits. */
export function formatContextTokens(n: number): string {
  return n > 0 && n % 1024 === 0 ? `${n / 1024}K` : String(n);
}

export type ContextChoice = { value: number; label: string };

/** The context select's options: 0 = same as chat (named with the chat's size
 * when the relay sent it), then every size, plus an odd stored value so the
 * select never shows a value it has no option for. */
export function contextChoiceOptions(
  chatContextSize: number | undefined,
  current: number | undefined,
  choices: number[] | undefined = WORLD_WIKI_CONTEXT_CHOICES,
): ContextChoice[] {
  const sizes = [...(choices && choices.length ? choices : WORLD_WIKI_CONTEXT_CHOICES)];
  if (current && current > 0 && !sizes.includes(current)) sizes.push(current);
  sizes.sort((a, b) => a - b);
  return [
    {
      value: 0,
      label: chatContextSize ? `Same as chat (${formatContextTokens(chatContextSize)})` : 'Same as chat',
    },
    ...sizes.map((v) => ({ value: v, label: `${formatContextTokens(v)} tokens` })),
  ];
}

/** "asked in 3 parts, 1 cut off" for the review header; '' when the index
 * fit the wizard's context whole. Twin of the desktop status note. */
export function scoutPartsNote(parts: unknown, partsCut: unknown): string {
  const p = typeof parts === 'number' ? parts : 0;
  const c = typeof partsCut === 'number' ? partsCut : 0;
  const bits: string[] = [];
  if (p > 1) bits.push(`asked in ${p} parts`);
  if (c > 0) bits.push(`${c} cut off`);
  return bits.join(', ');
}

/** "(478 index pages)" or, for a big wiki, "(top 478 of 3,005 pages by
 * links)" — twin of the desktop review header. '' when nothing was listed. */
export function catalogCountCopy(titles: unknown, articles: unknown, ranked: unknown): string {
  const t = typeof titles === 'number' ? titles : 0;
  if (t <= 0) return '';
  const a = typeof articles === 'number' ? articles : 0;
  if (ranked === true && a > t) return ` (top ${t} of ${a.toLocaleString('en-US')} pages by links).`;
  return ` (${t} index pages).`;
}

/** "shelf revised: 11 of 30 cards were people" or "review: …" when the
 * revise did not take; '' when the shelf read as a world. */
export function shelfReviewNote(revised: unknown, auditNotes: unknown): string {
  if (!Array.isArray(auditNotes) || auditNotes.length === 0) return '';
  const first = String(auditNotes[0]);
  const short = first.includes(';') ? first.split(';')[0] : first;
  return revised === true ? `shelf revised: ${short}` : `review: ${short}`;
}

export type DepthChoice = { value: number; label: string; cards?: number; blurb?: string; time?: string };

/** The shipped depth list, for an older server that sends none. */
export const WORLD_WIKI_DEPTHS: DepthChoice[] = [
  { value: 0, label: 'Quick', cards: 40, blurb: 'About 40 cards, no review passes. Fast; the shelf may be thin.', time: 'About 10 min on a remote model' },
  { value: 1, label: 'Full', cards: 60, blurb: 'About 60 cards. Factions and places name their people in their own card; the main cast gets cards. Reviewers check the shelf and every entry.', time: 'About 40 min on a remote model' },
  { value: 2, label: 'Deep', cards: 200, blurb: 'About 200 cards. Every place gets its people; slow on a local model.', time: 'Hours; run it overnight' },
];

/** The time hint for a depth value, from the shipped list. */
export function depthTimeHint(value: number): string {
  return WORLD_WIKI_DEPTHS.find((d) => d.value === value)?.time ?? '';
}

/** The relay's depth choices as select options, or the shipped list. */
export function depthOptions(raw: unknown): DepthChoice[] {
  if (!Array.isArray(raw) || raw.length === 0) return WORLD_WIKI_DEPTHS;
  const out: DepthChoice[] = [];
  for (const item of raw) {
    if (!item || typeof item !== 'object') continue;
    const row = item as Record<string, unknown>;
    const value = typeof row.value === 'number' ? row.value : Number(row.value);
    const label = String(row.label ?? '').trim();
    if (!Number.isFinite(value) || !label) continue;
    out.push({
      value,
      label,
      cards: typeof row.cards === 'number' ? row.cards : undefined,
      blurb: typeof row.blurb === 'string' ? row.blurb : undefined,
    });
  }
  return out.length ? out : WORLD_WIKI_DEPTHS;
}

/** "Full — about 60 cards" for the select, and the blurb under it. */
export function depthLabel(d: DepthChoice): string {
  return d.cards ? `${d.label} — about ${d.cards} cards` : d.label;
}

/** What the entry loop did to one entry (the relay's `notes`, by lowercase name). */
export type WorldEntryNote = { tries: number; passed: boolean; problem?: string };

/** The relay's notes map, parsed defensively. */
export function parseWorldEntryNotes(raw: unknown): Record<string, WorldEntryNote> {
  const out: Record<string, WorldEntryNote> = {};
  if (!raw || typeof raw !== 'object') return out;
  for (const [name, v] of Object.entries(raw as Record<string, unknown>)) {
    if (!v || typeof v !== 'object') continue;
    const row = v as Record<string, unknown>;
    const tries = typeof row.tries === 'number' ? row.tries : Number(row.tries) || 1;
    out[name.trim().toLowerCase()] = {
      tries,
      passed: row.passed !== false,
      problem: typeof row.problem === 'string' ? row.problem : '',
    };
  }
  return out;
}

/** Same words as the desktop: "Passed first try", "Rewritten once · …". */
export function worldEntryNoteCopy(note: WorldEntryNote | undefined): string {
  if (!note) return 'Written without a reviewer';
  const why = note.problem ? ` · ${note.problem}` : '';
  if (note.passed) {
    if (note.tries <= 1) return 'Passed first try';
    if (note.tries === 2) return `Rewritten once${why}`;
    return `Passed on try ${note.tries}${why}`;
  }
  return `Still failing after ${note.tries} ${note.tries === 1 ? 'try' : 'tries'}${why}`;
}

/** What the reviewers did, in plain lines, from the shelf note and the entry notes. */
export function worldReviewFindings(
  shelfNote: string,
  notes: Record<string, WorldEntryNote>,
): string[] {
  const lines: string[] = [];
  if (shelfNote) lines.push(shelfNote.replace(/^,\s*/, '').replace(/^\w/, (c) => c.toUpperCase()) + '.');
  const all = Object.values(notes);
  const rewritten = all.filter((n) => n.passed && n.tries > 1).length;
  const failing = all.filter((n) => !n.passed).length;
  if (rewritten > 0) {
    lines.push(`${rewritten} of ${all.length} entries ${rewritten === 1 ? 'was' : 'were'} rewritten by the entry reviewer.`);
  }
  if (failing > 0) {
    lines.push(`${failing} ${failing === 1 ? 'entry is' : 'entries are'} still marked by the reviewer; the last try stands.`);
  }
  return lines;
}

/** One entry as the page holds it (the LoreEntriesEditor shape: `key` is comma-joined). */
export type WorldReviewEntry = LoreEntry;

/** The root book of a written tree; the page keeps it without a name. */
export type WorldReviewRoot = {
  name?: string;
  parentName?: string;
  description: string;
  entries: WorldReviewEntry[];
  biome?: Record<string, unknown>;
};

export type WorldReviewPlace = {
  name: string;
  parentName: string;
  description: string;
  entries: WorldReviewEntry[];
  biome?: Record<string, unknown>;
};

/** The relay's `world_wiki_review_done` event: only what changed. */
export type WorldReviewResult = {
  updated?: { name: string; place: string; entry: WorldReviewEntry; note?: unknown }[];
  added?: { name: string; place: string; entry: WorldReviewEntry; note?: unknown }[];
  dropped?: string[];
};

const lower = (s: string) => s.trim().toLowerCase();

/**
 * The page's tree after a review action: updated entries swapped in by name
 * where they live, added ones appended under their place (the root when the
 * place is unknown), dropped ones removed. Root may be null on a flat write.
 */
export function applyWorldReview(
  root: WorldReviewRoot | null,
  places: WorldReviewPlace[],
  result: WorldReviewResult,
): { root: WorldReviewRoot | null; places: WorldReviewPlace[] } {
  const updates = new Map<string, WorldReviewEntry>();
  for (const u of result.updated ?? []) updates.set(lower(u.name), u.entry);
  const dropped = new Set((result.dropped ?? []).map(lower));
  const swap = (es: WorldReviewEntry[]) =>
    es.filter((e) => !dropped.has(lower(e.name))).map((e) => updates.get(lower(e.name)) ?? e);
  let nextRoot = root ? { ...root, entries: swap(root.entries) } : null;
  const nextPlaces = places.map((p) => ({ ...p, entries: swap(p.entries) }));
  for (const a of result.added ?? []) {
    const idx = nextPlaces.findIndex((p) => lower(p.name) === lower(a.place));
    if (idx >= 0) {
      nextPlaces[idx] = { ...nextPlaces[idx], entries: [...nextPlaces[idx].entries, a.entry] };
    } else if (nextRoot) {
      nextRoot = { ...nextRoot, entries: [...nextRoot.entries, a.entry] };
    } else {
      nextRoot = { description: '', entries: [a.entry] };
    }
  }
  return { root: nextRoot, places: nextPlaces };
}

/** Every entry of the tree, root first, for the flat save and the count. */
export function worldReviewEntries(root: WorldReviewRoot | null, places: WorldReviewPlace[]): WorldReviewEntry[] {
  return [...(root?.entries ?? []), ...places.flatMap((p) => p.entries)];
}

/** Notes merged in from a review result (updated and added carry theirs). */
export function mergeWorldEntryNotes(
  notes: Record<string, WorldEntryNote>,
  result: WorldReviewResult,
): Record<string, WorldEntryNote> {
  const next = { ...notes };
  for (const row of [...(result.updated ?? []), ...(result.added ?? [])]) {
    const parsed = parseWorldEntryNotes({ [row.name]: row.note });
    const key = lower(row.name);
    if (parsed[key]) next[key] = parsed[key];
  }
  for (const d of result.dropped ?? []) delete next[lower(d)];
  return next;
}

/** The three stages a scout goes through, for the progress card's chips. */
export const WORLD_SCOUT_STAGES = ['Scout the index', 'Reviewer reads the shelf', 'Fill what it forgot'];

/** The three stages a write goes through. */
export const WORLD_WRITE_STAGES = ['Write the cards', 'Reviewer reads them', 'Places and weather'];

/** Which scout stage a progress line belongs to (0-based), from its words. */
export function worldScoutStageOf(line: string): number {
  const l = line.toLowerCase();
  if (l.startsWith('hunting') || l.startsWith('nothing new') || l.includes(': +') || l.startsWith('shelf ready')) return 2;
  if (l.startsWith('reading the shelf') || l.startsWith('sent back') || l.includes('reviewer is reading') || l.includes('— passed')) return 1;
  return 0;
}

/** Which write stage a progress line belongs to (0-based), from its words. */
export function worldWriteStageOf(line: string): number {
  const l = line.toLowerCase();
  if (l.startsWith('walking around') || l.startsWith('checking the weather') || l.startsWith('weather written') || l.includes('book is done')) return 2;
  if (l.startsWith('reading ') || l.startsWith('re-reading') || l.startsWith('rewriting') || l.includes('sent back') || l.includes('passed')) return 1;
  return 0;
}

/** "MediaWiki", "Tiddly" or "Wiki" from the address alone. */
export function wikiKindGuess(url: string): string {
  const u = url.toLowerCase();
  if (u.includes('fandom.com') || u.includes('wikipedia.org') || u.includes('/wiki/') || u.includes('wiki.')) return 'MediaWiki';
  if (u.includes('tiddly') || u.includes('github.io')) return 'Tiddly';
  return 'Wiki';
}

/** The host part of a saved wiki address, for a tile. */
export function wikiHostLabel(url: string): string {
  try {
    const u = new URL(url);
    const path = u.pathname.replace(/\/+$/, '');
    return path && path !== '/' ? `${u.host}${path}` : u.host;
  } catch {
    return url;
  }
}

/** The Shelf step's filter chips: label and the kinds each gathers. */
export const WORLD_SHELF_FILTERS: { label: string; kinds: string[] }[] = [
  { label: 'Places', kinds: ['place'] },
  { label: 'Factions', kinds: ['faction'] },
  { label: 'Events', kinds: ['event'] },
  { label: 'Powers & terms', kinds: ['concept', 'race', 'item'] },
  { label: 'People', kinds: ['person'] },
];

/** The kinds that make a world's backbone. */
export const WORLD_BACKBONE_KINDS = new Set(['place', 'faction', 'event']);

/** A card's kind, with the role standing in when the scout gave none. */
export function shelfKindOf(c: ProposedWorldCard): string {
  return c.kind && c.kind.length ? c.kind : c.role;
}

/** How many cards each filter chip gathers. */
export function shelfKindCounts(proposed: ProposedWorldCard[]): Record<string, number> {
  const out: Record<string, number> = {};
  for (const f of WORLD_SHELF_FILTERS) {
    out[f.label] = proposed.filter((c) => f.kinds.includes(shelfKindOf(c))).length;
  }
  return out;
}

/** The indices of [proposed] that pass the filter ('' = all). */
export function shelfFilterIndices(proposed: ProposedWorldCard[], indices: number[], filter: string): number[] {
  if (!filter) return indices;
  const f = WORLD_SHELF_FILTERS.find((x) => x.label === filter);
  if (!f) return indices;
  return indices.filter((i) => f.kinds.includes(shelfKindOf(proposed[i])));
}

/** The indices "Sign the backbone" signs: the era card and every place, faction and event. */
export function shelfBackboneIndices(proposed: ProposedWorldCard[]): number[] {
  return proposed
    .map((c, i) => (c.role === 'era' || WORLD_BACKBONE_KINDS.has(shelfKindOf(c)) ? i : -1))
    .filter((i) => i >= 0);
}

// ── World from Character (docs/design/world-from-character.md) ──────────

/** What the wizard builds from; the steps are the same either way. */
export type WorldWizardSource = 'wiki' | 'character';

export function wizardSourceTitle(source: WorldWizardSource): string {
  return source === 'character' ? 'World from Character' : 'World from Wiki';
}

/** How far the writer may go beyond the record (design §3.3). */
export type WorldBuildMode = 'factsOnly' | 'faithful' | 'creative';

export type WorldModeChoice = { value: WorldBuildMode; label: string; does: string; never: string };

/** The shipped tiles, for an older server that sends none; same words as the desktop. */
export const WORLD_BUILD_MODES: WorldModeChoice[] = [
  {
    value: 'factsOnly',
    label: 'Facts only',
    does: "Restates what the chat, its Journal, Growth rings and Objectives, and the card say, in the world's voice. The model writes the sentences; it adds no fact.",
    never: 'A new name, place, event or detail. A sentence the lines do not state is sent back; a card nothing supports is dropped; weather only if the chat shows some.',
  },
  {
    value: 'faithful',
    label: 'Faithful',
    does: 'Keeps every fact as the spine and rounds it out: a place gets the look its lines imply, a person their manner, a gap between known events a line of connective tissue.',
    never: 'A new named place, person, faction, item or event, and nothing that changes what happened. Rounded-out sentences are marked at Review.',
  },
  {
    value: 'creative',
    label: 'Creative',
    does: 'The same facts, and the model may invent around them: new places, people and events the chat only hints at, and a climate guessed from the card.',
    never: 'A contradiction of the chat. Invented cards start unsigned on the Shelf and are marked at Review.',
  },
];

export const WORLD_MODE_EXPLAINER =
  'All three read the same record. They differ in what the model may add: nothing, texture, or new things. Whatever is added is marked, so you can drop it before Mint.';

const MODE_VALUES: readonly WorldBuildMode[] = ['factsOnly', 'faithful', 'creative'];

/** The relay's mode list as tiles, or the shipped list. */
export function modeOptions(raw: unknown): WorldModeChoice[] {
  if (!Array.isArray(raw) || raw.length === 0) return WORLD_BUILD_MODES;
  const out: WorldModeChoice[] = [];
  for (const item of raw) {
    if (!item || typeof item !== 'object') continue;
    const row = item as Record<string, unknown>;
    const value = String(row.value ?? '') as WorldBuildMode;
    if (!MODE_VALUES.includes(value)) continue;
    out.push({
      value,
      label: String(row.label ?? value),
      does: String(row.does ?? ''),
      never: String(row.never ?? ''),
    });
  }
  return out.length ? out : WORLD_BUILD_MODES;
}

/** Facts only with a chat, Creative for Card only (design §7). */
export function defaultModeFor(hasChat: boolean): WorldBuildMode {
  return hasChat ? 'factsOnly' : 'creative';
}

/** Under this there is almost nothing to skim (design §3.5). */
export const WORLD_CHAT_MESSAGES_FLOOR = 40;
/** Under this (about fifty turns) Facts only gives a thin shelf. */
export const WORLD_CHAT_MESSAGES_SHORT = 100;
/** Below this Full is mostly review passes over the same cards. */
export const WORLD_CHAT_MESSAGES_FOR_FULL = 200;

/** The chip a chat row wears: 'too short to skim', 'short chat', or ''. */
export function worldChatLengthChip(messages: number): string {
  if (messages <= 0) return '';
  if (messages < WORLD_CHAT_MESSAGES_FLOOR) return 'too short to skim';
  if (messages < WORLD_CHAT_MESSAGES_SHORT) return 'short chat';
  return '';
}

const MODE_LABEL: Record<WorldBuildMode, string> = { factsOnly: 'Facts only', faithful: 'Faithful', creative: 'Creative' };

/** The one warning line under the chat rows, or null; the desktop says exactly this. It warns, never blocks. */
export function worldChatLengthWarning(messages: number, mode: WorldBuildMode, depth: number): string | null {
  if (messages <= 0) return null;
  const turns = Math.round(messages / 2);
  const count = `${messages} message${messages === 1 ? '' : 's'} (about ${turns} turn${turns === 1 ? '' : 's'})`;
  if (messages < WORLD_CHAT_MESSAGES_FLOOR) {
    return `This chat has ${count}. Under ${WORLD_CHAT_MESSAGES_FLOOR} messages there is almost nothing to skim: Card only, or Creative, does better.`;
  }
  if (messages < WORLD_CHAT_MESSAGES_SHORT) {
    return mode === 'creative'
      ? `This chat has ${count}. The shelf will lean on what the model invents around it.`
      : `This chat has ${count}. ${MODE_LABEL[mode]} will give a thin shelf, likely under ten cards.`;
  }
  if (messages < WORLD_CHAT_MESSAGES_FOR_FULL && depth !== 0) {
    return `This chat has ${count}. Below ${WORLD_CHAT_MESSAGES_FOR_FULL} messages Full is mostly review passes over the same cards; Quick is the better fit.`;
  }
  return null;
}

/** The depth tiles a chat offers: no Deep, smaller counts (design §3.3). */
export const WORLD_CHARACTER_DEPTHS: DepthChoice[] = [
  { value: 0, label: 'Quick', cards: 15, blurb: 'The places, the people around them, the events the chat turned on. No review passes; the shelf may be thin.', time: 'About 5 min on a remote model' },
  { value: 1, label: 'Full', cards: 30, blurb: 'Places and factions name their people in their own card. Reviewers check the shelf and every entry against the chat.', time: 'About 15 min on a remote model' },
];

export const WORLD_CHARACTER_NO_DEEP_COPY =
  "Deep is not offered here: a chat has no roster to walk the way a wiki's categories do.";

/** The relay's character depth list, or the shipped one; a stored Deep shows as Full. */
export function characterDepthOptions(raw: unknown): DepthChoice[] {
  const parsed = depthOptions(raw);
  const own = parsed === WORLD_WIKI_DEPTHS ? WORLD_CHARACTER_DEPTHS : parsed;
  return own.filter((d) => d.value !== 2);
}

export function characterDepthValue(depth: number): number {
  return depth === 2 ? 1 : depth;
}

/** The scout's stages when the source is a chat: the Skim comes first. */
export const WORLD_CHARACTER_SCOUT_STAGES = ['Skim the chat', ...WORLD_SCOUT_STAGES];

/** Which character-scout stage a progress line belongs to (0-based). */
export function worldCharacterScoutStageOf(line: string): number {
  const l = line.toLowerCase();
  if (
    l.startsWith('skimming') ||
    l.startsWith('part ') ||
    l.startsWith('weather in this stretch') ||
    l.startsWith('reading the character') ||
    l.includes('messages in ') ||
    l.startsWith('index ready')
  ) {
    return 0;
  }
  return worldScoutStageOf(line) + 1;
}

/** One 1:1 chat as /api/stories/chat-sources lists it. */
export type ChatSourceRow = {
  character_id: string;
  character_name: string;
  session_id: string;
  session_name: string;
  summary: string;
  date: string;
  message_count: number;
};

export function parseChatSourceRows(raw: unknown): ChatSourceRow[] {
  const list = Array.isArray(raw)
    ? raw
    : raw && typeof raw === 'object' && Array.isArray((raw as { chats?: unknown }).chats)
      ? ((raw as { chats: unknown[] }).chats)
      : [];
  const out: ChatSourceRow[] = [];
  for (const item of list) {
    if (!item || typeof item !== 'object') continue;
    const r = item as Record<string, unknown>;
    const sessionId = String(r.session_id ?? '').trim();
    if (!sessionId) continue;
    out.push({
      character_id: String(r.character_id ?? ''),
      character_name: String(r.character_name ?? ''),
      session_id: sessionId,
      session_name: String(r.session_name ?? ''),
      summary: String(r.summary ?? ''),
      date: String(r.date ?? ''),
      message_count: typeof r.message_count === 'number' ? r.message_count : Number(r.message_count) || 0,
    });
  }
  return out;
}

/** The 1:1 chats of one character, as the relay orders them (newest first). */
export function worldChatRowsFor(rows: ChatSourceRow[], characterId: string): ChatSourceRow[] {
  return rows.filter((r) => r.character_id === characterId);
}

/** The relay's `source` field for a scout or write body; absent means the wiki. */
export function worldSourceBody(pick: {
  source: WorldWizardSource;
  characterId: string;
  sessionId: string;
  mode: WorldBuildMode;
  copyCardLore: boolean;
}): Record<string, unknown> {
  if (pick.source !== 'character') return {};
  return {
    source: {
      kind: 'character',
      characterId: pick.characterId,
      ...(pick.sessionId ? { sessionId: pick.sessionId } : {}),
      mode: pick.mode,
      copyCardLore: pick.copyCardLore,
    },
  };
}
