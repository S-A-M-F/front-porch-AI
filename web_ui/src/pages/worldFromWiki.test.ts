// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import {
  canOpenWorldFromWikiPreview,
  catalogCountCopy,
  contextChoiceOptions,
  depthLabel,
  depthOptions,
  emptyScoutCopy,
  formatContextTokens,
  jumpWorldFromWikiStep,
  parseProposedCards,
  parseProposedPlaces,
  scoutPartsNote,
  shelfReviewNote,
  shelfSections,
  signedCards,
  worldToolsAllowNext,
  worldToolsCanRetest,
  worldToolsCopy,
} from './worldFromWiki';

describe('world-from-wiki review shelf', () => {
  it('is proposed cards, not 211 wiki titles', () => {
    const titles = Array.from({ length: 211 }, (_, i) => `Page ${i + 1}`);
    const proposed = parseProposedCards([
      {
        name: "Baker's Street",
        keys: ["Baker's Street"],
        role: 'hub',
        sourceTitles: ["Baker's Street", "Baker's Street (draft)"],
      },
      {
        name: 'The River Faith',
        keys: ['River Faith'],
        role: 'hub',
        sourceTitles: ['The River Faith'],
        group: 'river-faith',
      },
      {
        name: 'Mira the Scout',
        role: 'leaf',
        sourceTitles: ['Mira the Scout'],
        group: 'river-faith',
      },
    ]);
    expect(proposed).toHaveLength(3);
    expect(proposed.length).toBeLessThan(titles.length);
    expect(proposed.map((c) => c.name)).not.toContain('Page 1');
    expect(signedCards(proposed, new Set())).toHaveLength(0);
    expect(signedCards(proposed, new Set([0, 2])).map((c) => c.name)).toEqual([
      "Baker's Street",
      'Mira the Scout',
    ]);
  });

  it('round-trips a homemade group slug from the scout string', () => {
    const proposed = parseProposedCards([
      {
        name: 'Mira the Scout',
        role: 'leaf',
        sourceTitles: ['Mira the Scout'],
        group: 'river-faith',
      },
    ]);
    expect(proposed[0]?.group).toBe('river-faith');
  });

  it('drops cards with no index sources or a junk role', () => {
    const proposed = parseProposedCards([
      { name: 'No sources', role: 'hub', sourceTitles: [] },
      { name: 'Bad role', role: 'faction', sourceTitles: ["Baker's Street"] },
      { name: 'The Crown Oven', role: 'crown', sourceTitles: ['The Crown Oven'] },
    ]);
    expect(proposed.map((c) => c.name)).toEqual(['The Crown Oven']);
  });

  it('blocks jump-to-Preview without a written shelf', () => {
    expect(
      canOpenWorldFromWikiPreview({
        lorebooksOn: true,
        aborted: false,
        entryCount: 0,
      }),
    ).toBe(false);
    expect(
      jumpWorldFromWikiStep(3, 1, {
        lorebooksOn: true,
        aborted: false,
        entryCount: 0,
        proposedCount: 3,
        signedCount: 1,
      }),
    ).toBe(1);
    expect(
      jumpWorldFromWikiStep(3, 2, {
        lorebooksOn: true,
        aborted: true,
        entryCount: 2,
        proposedCount: 3,
        signedCount: 1,
      }),
    ).toBe(2);
    expect(
      jumpWorldFromWikiStep(3, 2, {
        lorebooksOn: true,
        aborted: false,
        entryCount: 2,
        proposedCount: 3,
        signedCount: 1,
      }),
    ).toBe(3);
    expect(
      canOpenWorldFromWikiPreview({
        lorebooksOn: false,
        aborted: false,
        entryCount: 0,
      }),
    ).toBe(true);
  });

  it('blocks jump-to-Review without a scouted shelf', () => {
    expect(
      jumpWorldFromWikiStep(1, 3, {
        lorebooksOn: true,
        aborted: false,
        entryCount: 2,
        proposedCount: 0,
        signedCount: 0,
      }),
    ).toBe(3);
    expect(
      jumpWorldFromWikiStep(1, 3, {
        lorebooksOn: true,
        aborted: false,
        entryCount: 2,
        proposedCount: 3,
        signedCount: 1,
      }),
    ).toBe(1);
    expect(
      jumpWorldFromWikiStep(1, 3, {
        lorebooksOn: false,
        aborted: false,
        entryCount: 0,
        proposedCount: 0,
        signedCount: 0,
      }),
    ).toBe(3);
  });

  it('blocks jump-to-Write without signed cards', () => {
    expect(
      jumpWorldFromWikiStep(2, 3, {
        lorebooksOn: true,
        aborted: false,
        entryCount: 2,
        proposedCount: 3,
        signedCount: 0,
      }),
    ).toBe(3);
    expect(
      jumpWorldFromWikiStep(2, 1, {
        lorebooksOn: true,
        aborted: false,
        entryCount: 0,
        proposedCount: 3,
        signedCount: 0,
      }),
    ).toBe(1);
    expect(
      jumpWorldFromWikiStep(2, 3, {
        lorebooksOn: true,
        aborted: false,
        entryCount: 2,
        proposedCount: 3,
        signedCount: 2,
      }),
    ).toBe(2);
  });
});

describe('slice 8 places (web twin)', () => {
  it('parses places and keeps place on cards', () => {
    const cards = parseProposedCards([
      { name: 'Mira', role: 'leaf', sourceTitles: ['Ceolwynn'], place: 'Alnhama Republic' },
      { name: 'Baker', role: 'hub', sourceTitles: ['Alnhama'] },
    ]);
    expect(cards[0].place).toBe('Alnhama Republic');
    expect(cards[1].place).toBeUndefined();
    const places = parseProposedPlaces([
      { name: 'Alnhama Republic', climateHint: 'coastal', source_titles: ['Alnhama'] },
      { name: '' },
    ]);
    expect(places).toHaveLength(1);
    expect(places[0].climateHint).toBe('coastal');
    expect(places[0].sourceTitles).toEqual(['Alnhama']);
  });

  it('groups the shelf root-first and unknown places ride the root', () => {
    const cards = parseProposedCards([
      { name: 'Baker', role: 'hub', sourceTitles: ['Alnhama'] },
      { name: 'Mira', role: 'leaf', sourceTitles: ['Ceolwynn'], place: 'Alnhama Republic' },
      { name: 'Ghost', role: 'leaf', sourceTitles: ['Ceolwynn'], place: 'Nowhere' },
    ]);
    const places = parseProposedPlaces([{ name: 'Alnhama Republic' }]);
    const sections = shelfSections(cards, places);
    expect(sections).toHaveLength(2);
    expect(sections[0].place).toBeNull();
    expect(sections[0].indices).toEqual([0, 2]);
    expect(sections[1].place?.name).toBe('Alnhama Republic');
    expect(sections[1].indices).toEqual([1]);
  });

  it('no places keeps one flat section (the pinned unchanged path)', () => {
    const cards = parseProposedCards([
      { name: 'Baker', role: 'hub', sourceTitles: ['Alnhama'] },
    ]);
    const sections = shelfSections(cards, []);
    expect(sections).toHaveLength(1);
    expect(sections[0].place).toBeNull();
    expect(sections[0].indices).toEqual([0]);
  });
});

describe('empty scout copy', () => {
  it('shows the relay\'s reason when the model never answered', () => {
    const cut =
      'The model ran out of room before it finished the card list — its reply hit the 8192-token limit. Press Scout again, or pick a different model.';
    expect(emptyScoutCopy(cut)).toBe(cut);
    expect(emptyScoutCopy('  padded  ')).toBe('padded');
  });

  it('keeps the premise line for a real empty answer', () => {
    const premise = 'The scout returned no cards. Try a clearer premise, or another wiki.';
    expect(emptyScoutCopy(undefined)).toBe(premise);
    expect(emptyScoutCopy('')).toBe(premise);
    expect(emptyScoutCopy(42)).toBe(premise);
  });
});

describe('wizard context pick (web twin)', () => {
  it('names "Same as chat" with the chat size and lists every size in K', () => {
    const opts = contextChoiceOptions(65536, 0, [16384, 32768, 65536]);
    expect(opts.map((o) => o.label)).toEqual([
      'Same as chat (64K)',
      '16K tokens',
      '32K tokens',
      '64K tokens',
    ]);
    expect(opts[0].value).toBe(0);
  });

  it('keeps an odd stored value selectable and falls back to the shipped list', () => {
    const opts = contextChoiceOptions(undefined, 20000, undefined);
    expect(opts[0].label).toBe('Same as chat');
    expect(opts.some((o) => o.value === 20000 && o.label === '20000 tokens')).toBe(true);
    expect(opts.some((o) => o.value === 262144)).toBe(true);
  });

  it('formats whole K and leaves odd numbers alone', () => {
    expect(formatContextTokens(16384)).toBe('16K');
    expect(formatContextTokens(262144)).toBe('256K');
    expect(formatContextTokens(20000)).toBe('20000');
  });

  it('notes a split index and cut parts, and says nothing when it fit', () => {
    expect(scoutPartsNote(1, 0)).toBe('');
    expect(scoutPartsNote(3, 0)).toBe('asked in 3 parts');
    expect(scoutPartsNote(4, 1)).toBe('asked in 4 parts, 1 cut off');
    expect(scoutPartsNote('x', null)).toBe('');
  });
});

describe('world shelf review (web twin)', () => {
  it('keeps a known kind on a card and drops an unknown one', () => {
    const cards = parseProposedCards([
      { name: 'Seireitei', role: 'hub', sourceTitles: ['Seireitei'], kind: 'Place' },
      { name: 'Ichigo', role: 'crown', sourceTitles: ['Ichigo Kurosaki'], kind: 'hero' },
      { name: 'Old card', role: 'leaf', sourceTitles: ['Old'] },
    ]);
    expect(cards.map((c) => c.kind)).toEqual(['place', undefined, undefined]);
  });

  it('words the catalog by links for a big wiki and by pages for a small one', () => {
    expect(catalogCountCopy(478, 3005, true)).toBe(' (top 478 of 3,005 pages by links).');
    expect(catalogCountCopy(211, undefined, false)).toBe(' (211 index pages).');
    expect(catalogCountCopy(0, 3005, true)).toBe('');
  });

  it('notes a revised shelf, a review that did not take, and silence when it passed', () => {
    const notes = ['11 of 30 cards are people; keep at most 10 and spend the rest on places'];
    expect(shelfReviewNote(true, notes)).toBe('shelf revised: 11 of 30 cards are people');
    expect(shelfReviewNote(false, notes)).toBe('review: 11 of 30 cards are people');
    expect(shelfReviewNote(false, [])).toBe('');
    expect(shelfReviewNote(true, 'junk')).toBe('');
  });
});

describe('no model load until Next (web twin)', () => {
  it('lets Next go when the model passed or nothing has asked it yet', () => {
    expect(worldToolsAllowNext('ready')).toBe(true);
    expect(worldToolsAllowNext('notChecked')).toBe(true);
    expect(worldToolsAllowNext('checking')).toBe(false);
    expect(worldToolsAllowNext('failed')).toBe(false);
    expect(worldToolsAllowNext('notRunning')).toBe(false);
  });

  it('tells the user Next does the check', () => {
    expect(worldToolsCopy('notChecked')).toContain('Next checks it first');
  });

  it('a failed verdict can be asked again, and says so', () => {
    expect(worldToolsCanRetest('failed')).toBe(true);
    expect(worldToolsCanRetest('notChecked')).toBe(true);
    expect(worldToolsCanRetest('ready')).toBe(false);
    expect(worldToolsCanRetest('checking')).toBe(false);
    expect(worldToolsCopy('failed')).toContain('Check now');
  });
});

describe('depth pick (web twin)', () => {
  it('reads the relay list and falls back to the shipped one', () => {
    const fromRelay = depthOptions([
      { value: 0, label: 'Quick', cards: 40, blurb: 'fast' },
      { value: 2, label: 'Deep', cards: 200 },
      { value: 'x', label: '' },
    ]);
    expect(fromRelay.map((d) => d.value)).toEqual([0, 2]);
    expect(depthLabel(fromRelay[0])).toBe('Quick — about 40 cards');
    expect(depthOptions(undefined).map((d) => d.label)).toEqual(['Quick', 'Full', 'Deep']);
    expect(depthOptions([]).length).toBe(3);
  });
});
