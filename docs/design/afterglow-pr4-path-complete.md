# Afterglow PR 4 — warmth tail: path-complete fill

Design source: `docs/design/afterglow-recovery-overhaul.md` §PR 4 (maintainer-
approved 2026-10-17). Rides PR 1–3 on branch `feat/afterglow-pr2-recovery-profile`
(PR #555), stacked as its own commit.

## The physics

Climax seeds a **warmth tail**: `half the would-be lock, floor 15 min, cap
120 min`. A hard lock of 0 seeds nothing ("no refractory, no tail"); a soft
card's would-be lock is the judge's number (`fixed` never resolves soft, so
soft is always `turns × 15`; judge 0 on a soft card still floors to 15 — the
floor is the research baseline, not the lock). The tail is a `tail` field
inside `Refractory` (decision: reuse the value object — one slot, so
elapse/receipts/snapshot/member-map/hydrate carry it through ONE read path,
not two). It is frozen while the body runs (lock, or soft window plus the
warm-again hour) and starts aging on the first beat after the body is fully
clear — lock end for hard, last peak aging out for soft. Clock off it ages
15 minutes per speaker reply like everything else, so it lasts
`ceil(tail / 15)` replies (decision 1). No chip, no new switch — the prose
carries it.

## 1. Generation matrix (does the behavior differ by path?)

| Path | What happens | Verified by |
| --- | --- | --- |
| Normal send (1:1) | Climax seeds tail via `applyClimaxEffects(tailMinutes:)`; every tick ages body-then-tail through `Refractory.elapse` (frozen until body clears); `_moveRefractory` gate widened to "no lock AND no peaks AND no tail" so a tail-only body still ticks and receipts | refractory_clock tail group |
| Continue | Not a beat: no aging, tail unchanged (existing rule covers it — tail rides the body) | same (Continue asserts unchanged) |
| Regen / swipe / delete | Body receipts carry the nested tail map through `toSnapshot`/`read` — rewind restores tail minutes exactly; pre-climax stamp includes it | clock regen-tail guard + legacy round-trip |
| Group | Speaker-only ticks per reply; all bodies age on the clock; member map round-trips `refractoryTail` (key registered in `GroupRealismKeys.runtime` — the :309 assert guards) | member-map round-trip |
| Climax during a live tail | New climax re-seeds: the fresh body takes the new tail (fresh restart, documented) | nsfw_service tail seed test |

## 2. Prompt/Realism matrix

| Site | Change |
| --- | --- |
| Injection ladder | One new rung, both modes, pronoun-free: "still riding a warm afterglow — ordinary warmth runs deeper than usual today; small kindnesses land harder, and any desire that has come back cools slowly." Rung order: window rungs → soft warm-again → **tail** → arousal bands (tail outranks the "chasing release" snap the design calls the bar-vs-prose break) |
| Eval note | Tail branch: non-romantic turns above +10 hold (return 0), never −5…−10, never raise. Wired through `realism_prompt_builder` + `realism_eval_calls` + `realism_eval_one_shot` like `refractorySoft` was in PR 3 |
| Chip | None (by design — tail is not a lock) |

## 3. Persistence (v60)

- `sessions.refractory_tail_minutes` + `refractory_tail_total` INTEGER,
  NULL = no tail (v59 rows byte-identical). Schema 59 → 60, drift regen.
- Hydrate rebuilds the nested map under `RefractoryKeys.tail`; save writes
  NULL unless the tail is running… plus RUNNING-OR-PENDING: a tail frozen
  under a live lock must survive restart, so save writes whenever a tail
  EXISTS (running), freeze state follows from the body's own minutes.
- `.fpchat`: session head writes/reads `refractory_tail_minutes` /
  `refractory_tail_total` (snake, beside the PR 3 pair); message realism
  snapshot core keys gain `refractoryTail` (the nested camel map).
- Group member map: `refractoryTail` key, registered; nested JSON rides the
  existing dynamic-value encode.
- Receipts/snapshots: automatic through `toSnapshot`/`read` — pinned by a
  round-trip test anyway.

## 4. Test law (append-only, each red→green)

Existing-test edits, disclosed (label on PR #555 covers them): the
`afterglow_independence` exact-equality pin now carries the seeded tail;
the `avatar_repository` schemaVersion pin 59→60 + chain line; the
`refractory_clock_test` import gained `Refractory` to its existing `show`
clause (CI test-integrity carve-out permits imports).

## 4b. Hostile review round (2026-10-18) — findings and fixes

1. BLOCKING (fixed): group member slots merged the snapshot with
   `_data.addAll` — a finished tail (or expired peaks, or a soft flag under
   a later hard body) stayed in the slot forever and revived on every
   read: the member spoke "still riding a warm afterglow" indefinitely,
   breaking 1:1↔group parity. Fix: the typed setter removes soft/peaks/tail
   when the new snapshot omits them; `setValue` clears on null (the
   `withUser` convention) and `saveNsfwScalarsToGroup` sends null for the
   omitted keys. Guard: "a completed body REPLACES" + the clear-on-null
   test, red-proven by reverting the setter (ghost revive reproduced).
2. MINOR (fixed): a junk/empty nested tail map manufactured a resident
   empty body; `read` now collapses a not-running tail to null.
3. MINOR (fixed): the eval note dropped the design's "above +10" band;
   restored.
4. MINOR (fixed): a soft card carrying a stale `fixed` number seeded the
   tail off `fixed`; soft now always seeds off the judge's number.
5. Fixed: miscounted clock-off test title ("three replies" → two).
6. INFO (accepted): a completed tail leaves `Refractory(soft: true)` as
   the resting body — behavior-neutral, all consumers gate on
   running/peaks/tail; same pattern as PR 3's soft expiry.

1. Seed math exact: judge 6 → (6×15)/2 = 45; fixed 240 → 120 (cap); judge 2
   → 15 (floor); soft judge 0 → 15 (floor); hard judge 0 → none.
2. Timing: hard tail starts the first beat after lock end (frozen at exactly
   the seed during the lock); soft tail waits for the last peak to age out;
   clock-off ages 15/reply, lasts ceil(tail/15) replies; Continue ages
   nothing.
3. Rewind: regen of a ticked-tail reply restores its pre-beat tail minutes
   (receipt carries nested tail); pre-climax stamp carries the tail.
4. Rung: copy pinned; beats the arousal band; hard body gets it too; the
   pronoun-guard sweep lists the tail state among the ladders.
5. Eval note: hold-not-raise sentence present when tail active and absent
   otherwise; band copy intact.
6. Persistence: v60 session row round-trip (frozen AND active tail), `.fpchat`
   head round-trip, member-map round-trip, junk/negative tail minutes read
   as none.
7. Avatar pin 59 → 60 + chain comment (`approved-test-change` label already
   on PR #555 — second edit covered).

## 5. Web parity

No chip, no switch, no new web surface: `refractoryLabel` stays empty
during a tail and `ChatToolsRealism.tsx` shows nothing new (correct — the
tail is prose-only). `realismTypes.ts` recovery copy unchanged (the tail is
behavior of every mode, not a new mode). Recorded here instead of a diff.

## 6. Hygiene budget

`chat_service_regen_revert.dart` is 484/500 going in — tail rewind must ride
existing lines there (it does: the body snapshot carries it, zero added
lines; verified with wc after). `refractory.dart` ~382 after (+40). Touched
lib files re-checked against the 500 gate; format+analyze clean; full
`test/services/chat/` green.

## 7. Consequences accepted

- A tail does NOT survive a NEW climax as a second window — the new body's
  seed replaces it (one tail at a time, oldest warmth wins nothing).
- Clock-off tail granularity is 15 min/reply; a 45-min tail is exactly 3
  replies; rounding is inherited from the decision-1 rule, not new.
- Mid-window soft→hard flips keep ticking their seeded tail; the rung does
  not check `soft` (warmth is not gendered by mode; copy is mode-neutral).
