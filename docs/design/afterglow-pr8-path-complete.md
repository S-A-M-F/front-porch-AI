# Afterglow PR 8 — post-coital dysphoria (path-complete)

Spec: `docs/design/afterglow-recovery-overhaul.md` §PR 8. Opt-in card
flavor: a grey, hollow mood that can land after a climax — real, transient,
and not about the partner. Off ships; nothing shifts until a card asks.

## 1. Generation matrix (every path that touches pcd state)

| Path | What happens | Pin |
| --- | --- | --- |
| Card has no `pcd` key (every pre-PR-8 card) | `pcdRollHit` short-circuits at rate 0 — no draw, no stamp, no copy changes | `off never rolls and never even draws` (scripted-empty random) |
| Climax first reading, dial `rare` | draw < 0.15 stamps `pcd: true` beside `climax_triggered` in the reply metadata | `a rare dial and a low draw stamp the beat` + boundary pin |
| Climax first reading, dial `sometimes` | 0.35 line, strict | `sometimes takes what rare declines` |
| Continuation onto an already-stamped climax | NO re-roll — the first reading owns the beat (regen re-runs the FIRST-reading branch and rolls fresh) | `a continuation does not re-roll` (script throws if any draw happens) |
| Group member climaxes | roll uses the SPEAKER's card dial (same resolution the lock uses — post-gen already made the speaker the writer) | harness activeCharacter + §PR5 precedent |
| Window open, opening turn | ladder speaks the grey rung (hard: keeps the cannot-answer lock truth; soft: closeness wanted, drift passes through) | `a grey hard/soft opening…` guards |
| Window open, mid-ladder turns | normal rungs — the rung is opening-only; the window's later turns color the emotion eval instead | `a mid-window body never speaks the grey opening` |
| Window open, eval lanes | `emotionSection` note: wistful/tearful is honest, cause unnameable, NOT a reaction to {{user}}, **bond and trust stay exactly as they were** | `the emotion note…` + `both eval lanes…` guards |
| Window closed everywhere | every surface byte-identical with pre-PR-8 copy | `a closed window ships…` + bare-rubric pin |
| Regen / swipe / delete of any reply in the window | window recomputes from history — rewinds for free (no state) | window guards run on fabricated histories |

## 2. The one law of the roll

`RecoveryProfile.pcdRollHit(rand)` is the only roller: rate is a pure
switch over the stored dial (`rare` 0.15, `sometimes` 0.35, else 0), the
draw happens only when rate > 0 (so an off card never consumes randomness —
a later dial change sees the same sequence), and the boundary is strict
(`<`, so exactly-the-rate misses). AfterglowPass takes the source as
`randomSource` (defaults to a process `Random`) so tests script draws.

## 3. The window (duration, from history alone)

`pcdWindowActive` (top-level in `afterglow_pass.dart`) scans backwards:
the newest NON-USER REPLY ATTRIBUTED TO THE SPEAKER that carries
`climax_triggered` decides — it must ALSO carry `pcd` (a fresh solo beat
closes an older grey one; another member's climax is not this body's
business). Then the window is open while that speaker's own later replies
number ≤ 2 (opening + two). Users never advance the clock. Guests are
excluded from attribution at the ChatService closure, mirroring the mutual
scan. No new state: regen/delete rewind by changing the history.

## 4. Composition and precedence

- **PCD outranks mutual on the opening rung** (one rung per beat; the
  opt-in, specific mood beats the general shared-clause). The mutual stamp
  still rides underneath — the eval lanes and a later solo opening see it.
- **Arousal and bond/trust deltas are untouched** — the effect is copy:
  a ladder rung and an emotion note. The note carries its own law:
  "bond and trust stay exactly as they are" — pinned in the fused prompt.
- **The grey rung never breaks the hard lock**: incapacity truth ships in
  the same sentence; the drift is mood, not capacity.
- **Preset/slider switches preserve the dial** (orthogonal, both platforms).

## 4b. Full-suite sweep findings (disclosed test edits)

The PR-8 work ran the WHOLE repo suite for the first time in this stack
(earlier rounds ran `test/services/chat/` scope). Three failures surfaced,
two real, one environmental:

- **`test/models/recovery_profile_test.dart` — stale PR-2 copy pin.**
  The soft-gate resolves line was rewritten by PR 3 (`3699384ec`) to
  describe the shipped tenderness physics, but the model test still
  demanded the PR-2 hedge "until soft-gate mechanics". Pin rewritten to
  the PR-3 copy (and to forbid the stale hedge). Disclosed edit to an
  existing test, same-PR-series collateral, covered by the PR's
  `approved-test-change` label.
- **`test/database/v14_to_current_upgrade_test.dart` — stale ladder ends
  (58 → 60, two sites).** PR 3 added migration v59 and PR 4 added v60
  (both in `database.migrations.late.dart`, correctly), but the v14 pin
  was never moved. The engine is consistent; the pin lagged. Annotations
  for v59/v60 added with the fix. Same disclosure class as above.
- **`test/cli/*` load failures + `storage_service_init.dart` analyzer
  errors — NOT in the PR.** `/lib/cli/`, `/test/cli/` and that one
  storage file are gitignored local "Hermes" dev WIP (`.gitignore`
  188–193); `LLMProvider.remoteOnly` exists only in that local file. A
  fresh CI checkout never sees them. No action.

## 4c. Wiring glue

`ChatService._pcdActive` (chat_service_wiring_injection_leaves.dart) is
the only untested-locally piece: it maps `_messages` + guest/authored
predicates + the group's current speaker into `pcdWindowActive`. Same
coverage posture as PR 5's `_mutualAfterglowOpening` (unit pieces pinned,
glue by construction + poke); the scan semantics live in the pure, fully
pinned function.

## 4d. Hostile-review ledger (commit `6163006fb`)

Reviewer attacked the roll, window, persistence round trip, lanes, copy
law, and gates. **No BLOCKING, no MAJOR** — two MAJOR-shaped candidates
(null-speaker group degradation: `currentSpeakerId()` returns `''`
mid-generate and `''` attributes nothing, so the window is safely off
exactly like the mutual leaf; regen/swipe stamp coherence: stamp writes
and window reads both go through `activeMetadata`, the per-swipe slot)
defused under inspection. All five minors fixed:

- **m1 (fixed + red)** — `pcdWindowActive` counted System status
  banners in 1:1 (they ride the timeline `isUser: false`), spending a
  reply tick of the window on ops furniture. The leaf now filters
  `sender == 'System'` by the same law as `_refractoryBeatMinutes` in
  this very file; new banner guard, red by removing the filter.
- **m2 (fixed)** — §9 said "mutual copy is silent that turn"; true of
  the ladder, but the fused arousal note still speaks its mutual clause
  (complementary lanes). Sentence tightened to what the code does.
- **m3 (fixed in the amended commit)** — guard count was understated
  ("17"); truth is 27 Dart + 2 vitest after the review round.
- **m4 (fixed + red)** — grey-outranks-mutual was pinned on the hard
  rung only; soft rung ordering now has its own guard, red by inverting
  the soft branch's check.
- **m5 (documented)** — pre-existing swipe-shrink fallback semantics,
  shared with every climax stamp since PR 3; added to §9 rather than
  silently ignored.

Verified clean by the reviewer and re-verified in the sweep: the roll's
first-reading-only placement and short-circuit; per-body group windows;
`indexOf` identity safety; guest exclusion matching the M7 mutual
precedent; ALL `emotionSection`/builder call sites (exactly two each)
threading the flag; emotion judge confirmed PRE-generation so the note
lands on exactly opening + 2; `'pcd'` has exactly one writer and one
reader in lib (no scoring code touches it — arousal/bond/trust deltas
cannot move); full pcdMood persistence round trip (codec, bridge, web
mirror, editor, creator, drafts, PNG) with no drop/reset/verbose-off
path found; `kPcdOptions` vs `PCD_OPTIONS` byte-identical to the
character; Rawhide percentages true and name-free; ratchets green
(max touched file 489).

## 5. Web parity

- `realismTypes.ts`: `PcdMood`, `PCD_OPTIONS` (labels byte-identical with
  Dart `kPcdOptions`), `PCD_RATE_RARE/SOMETIMES`, lenient
  `recoveryFromDetail` (trim/lowercase, junk → off),
  `recoveryFromPreset(key, pcdMood)`, `recoveryWithMinutes(current, n)`,
  `recoveryWithPcdMood(current, mood)`.
- `RealismFormSection.tsx` RecoveryBlock: third control ("Grey drift
  after") with the same explanatory copy as desktop, shown wherever the
  Recovery block shows (18+ and Afterglow on — inherited gate).
- Bridge: `toFields` always carries `pcdMood`, `toJson` omits `pcd` when
  off (additive card law), `fromFields`/`fromJson` read it leniently —
  the existing recovery block round-trip (`realism_extensions_json.dart`)
  carries it with no route changes.
- Pins: Dart `recovery_profile_test` (option table + rates + round-trips)
  and vitest `realismTypes.test.ts` (byte-identical table, leniency,
  orthogonal setters). `isDefault` includes the dial so the codec's
  `!isDefault` gate writes a pcd-only card.

## 6. Red proofs (all run before commit; each red on exactly its guard)

1. Off draws anyway (`pcdRollHit` short-circuit removed) → model
   `off never rolls` + pass `off never rolls and never even draws`.
2. Continuation re-rolls (roll moved into the continue branch) →
   `a continuation does not re-roll`.
3. `<` → `<=` at the rate boundary → `the boundary is strict`.
4. Window `since <= 2` → `<= 3` → `two replies carry the window, the
   third closes it`.
5. Window ignores the `pcd` stamp (newest climax wins regardless) →
   `a climax without the stamp opens nothing`.
6. Mutual checked before pcd on the hard rung → `the grey drift outranks
   the mutual clause`.
7. `emotionSection` default `pcdActive: true` → `both eval lanes carry
   the note only when the window is open` (bare side goes red).
8. `isDefault` drops the pcd clause → `a set dial makes the profile
   non-default`.
9. `toJson` always writes `pcd` → `the writers only speak the key when
   it is set`.
10. `fromPreset` drops the carried dial → `the dial survives the
    kind-and-length setters`.
11. Web label drift (one character in `PCD_OPTIONS[1]`) → vitest
    `mirrors the pcd dial table byte-for-byte`.
12. Web auto-branch drops the carried dial → vitest `round-trips preset
    key…`.

Result: 10/11 red on the first sweep; proof 10 came back GREEN and
exposed a real blind spot — the Dart guard never checked the `auto`/
fallback `fromPreset` branch carrying the dial. Guard strengthened
(auto + unknown-key carry pinned, same pin mirrored into vitest), then
RED-OK on the re-run, both platforms. 12/12 red, then all green.

## 7. Poke script (2–5 steps, live)

1. 18+ + Afterglow + Realism on. Editor → Recovery after intimacy →
   **Grey drift after: Rare**. Chat to a climax (Lust high, reply depicts
   release). Open the eval/prompt view: the opening ladder injection
   carries "a sudden grey drift — not sad about anything, and nothing
   {{user}} did". The reply's receipt carries the `pcd` stamp (developer
   view or logs).
2. Continue two more exchanges: the emotion-eval prompt shows the NOTE
   ("wistful or tearful is an honest read… bond and trust stay exactly as
   they were"). After the third reply the note is gone and normal rungs
   speak.
3. Regenerate the climax reply: the roll re-fires — the stamp may flip
   either way on a Rare card (re-roll a few times; window follows the
   regenerated history).
4. Set the dial back to **Off**: a fresh climax never stamps, and every
   prompt copy matches pre-PR-8 byte-for-byte (this is what every
   existing card sees).
5. Group: dial **Rare** on member A, leave B untouched. A climaxes →
   grey rung and note appear on A's turns only, and B's turns never
   advance or borrow A's window.

## 8. Web parity note

Shipped: types, options table, lenient reader, orthogonal setters,
third control in the web RecoveryBlock (same inherited gate as desktop:
Afterglow + 18+). Pins on both sides (vitest 71 green incl. two new;
Dart model guards). No prompt golden or web snapshot breaks.

## 9. Known accepted outcomes

- Continuations do not stamp pcd even if the continued text adds new grey
  prose — the beat belongs to the first reading (same discipline as the
  PR 5 stamp for everything except the monotonic mutual merge).
- Mutual + pcd on the same opening: mutual LADDER copy is silent that
  turn (one rung per beat; the stamp survives). The fused arousal note
  still speaks its mutual clause the same turn — the judge lanes and the
  ladder are different surfaces, and the sentences are complementary
  ("came undone together, shared recovery" beside "a sudden grey drift").
  Review m2: the first draft of this doc said "mutual copy" whole, which
  was wider than the behavior.
- System status banners never spend a window tick (they are ops
  furniture, not the speaker's replies — same law as
  `_refractoryBeatMinutes`). Pinned by the banner guard after review m1.
- Reloaded-message swipe-shrink fallback (pre-existing, shared by every
  climax stamp since PR 3): a message whose persisted `swipeMetadata` is
  shorter than its `swipeIndex` reads the base metadata, so a regen's
  first-reading guard can see a stale `climax_triggered` and take the
  continue branch — pcd rides the old value like the PR 3 body and the
  PR 5 mutual stamp already did (review m5; acknowledged at
  `chat_service_generation_postgen.dart`, not introduced here).
- `pcd` window and the PR 4 warmth tail can overlap; the tail note lives
  in the arousal section, the grey note in the emotion section — different
  fields, no interference.
- The rates are flavor dials, not prevalence claims (SOW copy).
