# Afterglow PR 7 — bonding surge: path-complete fill

Design source: `docs/design/afterglow-recovery-overhaul.md` §PR 7. Rides
PR 1–6 on branch `feat/afterglow-pr2-recovery-profile` (PR #555), stacked
as its own commit.

## The physics

Oxytocin and prolactin rise after orgasm in humans; the pair-bonding
mechanism itself is mostly animal-model evidence, so the SOW settles this
as a gentle CONDITIONAL tilt in the prompt, never a stat. The condition is
WANTED intimacy + existing warmth — not orgasm itself (maintainer
stress-test: the sex-worker / dissociation archetype must have a legal
"the body recovered, the heart did not follow" reading).

## 1. Generation matrix

| Path | What happens | Verified by |
| --- | --- | --- |
| Fused one-shot eval | `bondSection` carries the conditional — the model scores `relationship_delta` with the surge lever named ("counts more toward short-term bond") and the duty escape together | `every window speaks the conditional` + drift pin |
| Multi-call lane (every local backend) | `bondSection` rides the RELATIONSHIP judge's prompt (realism_prompt_builder :292) where `relationship_delta` is the output; the emotional judge's arousal notes carry NO surge (it has no bond field — §4b M1) | `the emotional judge gets no dangling surge` guard |
| Cooldown window (hard) | The refractory note on the arousal section appends the clause — mid-lock the surge prose still reads (affection scored while capacity is out is exactly when the lever matters) | hard-note guard |
| Cooldown window (soft) | Soft refractory note appends the same clause | soft-note guard |
| Warmth tail window | Tail note appends the same clause (PR 4 left the bond side to PR 7; now it lands) | tail-note guard |
| No afterglow | Arousal section without note carries no clause (no clause about someone else's afterglow on a plain turn); the bond section keeps the always-conditional line — inert prose outside a scene | bare-arousal guard |
| Continue / regen / swipe | Prompt-only: nothing stamped, nothing to roll | by construction |
| Group | The clause names `$charName`/`$userName` from the same per-eval substitution every other fragment line uses — per-speaker by existing wiring | by construction |

## 2. Prompt/Realism matrix

- ONE source: `RealismPromptFragments.bondSurgeClause(charName, userName)`
  in `realism_prompt_fragments.dart`; four call sites (hard note, soft
  note, tail note, bond section). PR 7 owns the copy; nothing paraphrases
  it. The three NOTES append it only when `bondScoredHere` is set (the
  fused lane); the multi-call emotional judge — which has no bond field
  to spend the advice on — gets the conditional solely through
  `bondSection` on the relationship judge (§4b M1).
- Drift law, double-pinned: (a) each surface's output must contain the
  SOW sentence and the duty clause verbatim; (b) the drift pin EXTRACTS
  the emitted sentence from all four surfaces and requires byte equality.
  Changing the shared clause changes all four in lockstep by construction
  (a shared-string paraphrase is invisible to (b) — proven, and fine);
  (b) goes red the moment any single CALL SITE copies or paraphrases the
  clause locally (red-proven with a one-word local "practiced skill"
  swap).
- Judge lanes resolve no macros: the clause interpolates `$userName`, and
  a guard asserts no `{{user}}` token leaks into any of the four surfaces
  (PR 5 M3 law kept).
- No scoring code, no bounds moved: the clause rides the existing wanted/
  unwanted bands and authored tastes — a nudge on the model's judgment,
  not a multiplier.

## 3. Persistence

None. No fields, no columns, no metadata, no member-map keys. Nothing for
`.fpchat`, snapshots, receipts, or hydra to carry.

## 4. Test law (append-only, each red→green)

1. Conditional + duty clause + no-macro-leak in all four surfaces.
2. Drift pin: byte-identical extracted sentence across surfaces; red on a
   local paraphrase at one call site.
3. Bare arousal path stays clause-free.
Red proofs: tail note dropped, bond section dropped, call-site paraphrase
— 3/3 red on exactly their guards, then green. Existing pins (fusion
parity, prompt-shape tests) pass UNCHANGED.

## 4b. Hostile-review ledger (commit `1d9a8d840`)

Reviewer attacked across eight fronts. No BLOCKING; two MAJOR, all fixed:

- **M1 (MAJOR, fixed + red-proven) — the dangling surge.** The multi-call
  lane (which `resolveOneShotMode` resolves for EVERY local backend)
  builds `emotionalEvalPrompt` with `arousalSection` but no
  `relationship_delta` field — the surge rode that note as advice with no
  field to spend it on, and small models pour unmatched advice into the
  number that IS there (exactly what the note caps). Fix: notes carry the
  clause only when the same prompt scores bond — `arousalSection` gains
  `bondScoredHere` (default false), only `oneShotEvalPrompt` passes true.
  The trio lane still gets the conditional through `bondSection` on the
  relationship judge, where the field lives (pinned). Guards: emotional
  prompt clause-free while its note stays; bond section keeps it; fused
  emits exactly two copies. Red by opting the emotional call in.
- **M2 (MAJOR, fixed + red-proven) — the duty escape was rhetoric, not
  instruction.** Under two unconditional-sounding warmth sentences, "the
  heart may not follow" reads as permission to climb anyway. Duty branch
  now names the score: "…and the heart may not follow — a flat or dipped
  bond is the honest score there." The neither-wanted-nor-duty middle
  case lands on the existing default bands by design (no lever fires).
  Drift pin's `duty` constant moved with the copy.
- **m1 (fixed)** — `bondSurgeClause` carried a leading space the call
  sites also added, leaving three-space indents mid-paragraph. Clause is
  space-free now; notes join with one space, the bond rubric indents two
  like its siblings, and a surface-aware whitespace guard pins both.
- **m2 (accepted)** — the fused prompt speaks the surge twice (bond line +
  refractory note). Double-emphasis of ONE copy is the accepted cost of
  the SOW's "extend all three places + the bond section"; the fused
  guard pins the count at exactly 2 so a third copy fails loudly.
- **"Contented satedness" softening declined** — PR 3's copy is its own
  pinned law; the surge steers BOND while that sentence bounds AROUSAL.
  Complementary, not contradictory; a model reads "not horny, but this
  closeness matters."
- **Checked CLEAN:** single source (no second copy in lib/ or web_ui/ —
  rubric fragments have no web duplicate); bond is always an output
  wherever bondSection rides (`:292` relationship, `:371` fused); no
  prompt golden pins the changed sections byte-exact (chat golden and
  stopped-reply pins pass unchanged); output parsers untouched (the
  clause names no output field); `_warmthTailNote`'s new `userName` is
  passed at its single call site; pure function of two names — no state,
  no stamp, nothing to persist.

## 5. Web parity

Prompt-only change inside the shared eval builders; `web_ui` has no copy
of these prompt fragments (grep: no "relationship_delta" rubric duplicate)
and no chip/switch added. Recorded here instead of a diff.

## 6. Hygiene budget

`realism_prompt_fragments.dart` gains ~12 lines (one clause + one line at
each of three call sites + comment). Format + analyze clean; suite green.

## 7. Consequences accepted

- "Counts more toward short-term bond" has no number by design — the
  magnitude table already owns the scale; the clause only raises
  afterglow-contact moments within it. Expect ±3-5 moments where a plain
  comfort turn would sit at ±2, at the model's discretion.
- The bond section carries the clause on every eval turn (it already
  carries wanted-ness bands every turn). Outside a scene the sentence is
  inert; the design chose always-present over gated so the copy and its
  single source cannot fork on a condition no test can pin.
- No UI surface promises anything; Rawhide describes the felt change only.
