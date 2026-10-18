# Afterglow PR 6 — chaos respects the hard lock: path-complete fill

Design source: `docs/design/afterglow-recovery-overhaul.md` §PR 6. Rides
PR 1–5 on branch `feat/afterglow-pr2-recovery-profile` (PR #555), stacked
as its own commit.

## The physics

Four adult events out of 82 ASSERT the character's own desire ("visibly
aroused", "hide a visible physical reaction", "suddenly, intensely in the
mood", "a long dry spell… restless"). Under a hard refractory lock the
Lust bar is honestly at zero and the ladder says the body cannot respond —
a wheel landing on those texts makes the player stop trusting the bar. The
"body betrays them" contradiction stays legal as a CARD-authored trait,
never a system coin flip. Soft-gate bodies keep desire up, so the gate is
hard-lock-only by decision.

## 1. Generation matrix

| Path | What happens | Verified by |
| --- | --- | --- |
| Manual spin (desktop overlay) | Goes through `ChatService.spinWheelEvents` → `ChaosModeService.spinWheelEvents` → `buildChaosWheel(hardLockActive: closure)` — tagged events are out of the POOL before slots are dealt; wheel stays 8 with full `kAdultWheelSlots` adult slots | `chaos_hard_lock_test` (real wiring) + `chaos_wheel_test` locked/full guard |
| Web / mobile spin + Accept | Same service method (the single choke), so the pre-picked `_webChanceTimeEvent` can never be a tagged event under lock | same choke — one filter covers all three entry points |
| Auto pressure trigger | The service rolls internally through the same `spinWheelEvents` — filtered identically | same |
| 1:1 attribution | `{{char}}` resolves to the host; the closure reads the live `_nsfwService.refractory` | hard-lock guard (spins 100×), soft guard, release-live guard |
| Group attribution | Speaker is `chanceTimeSpeakerName` (round-robin: the upcoming speaker; random turn order falls back to the last speaker — see §4b m1); the closure maps that NAME back to its card and reads the member's STORED refractory (`_groupStore.members[id].refractory`), never the live scalars (those may hold the previous speaker's) | chaos-layer guards pin the wheel contract for any bool; the name→card→slot branch is code-reviewed (private store, no unit harness — disclosed gap, see §7) |
| No group / no card match | Falls to false → undimmed wheel (fail-open: chaos never dies over a missing mapping) | wheel-contents guards unchanged |

## 2. Prompt/Realism matrix

- Tag: `ChaosEvent.desireAsserting` — exactly the four texts, all adult
  (`chaos_wheel_test` set-equality guard). Pool split keeps all 82 texts
  in `kAllChaosEvents` untouched — only the constructor gains the flag.
- Filter position: pool-side, BEFORE the take. Red-proven: filtering after
  the take hands the wheel dead adult slots (guard "stays full" goes red).
- `hardLockActive` defaults false on `buildChaosWheel`; `isHardLockActive`
  is absent-means-never-gated on the service — every other host and every
  existing caller compiles and behaves unchanged.
- Injection, apply, pressure, cooldown, recent-memory: untouched. The
  event colors the reaction; the gate only chooses legality.

## 3. Persistence

No new state anywhere: no columns, no metadata keys, no member-map keys.
The gate is computed live at spin time from state PR 2–4 already persist.
`recent` memory stores raw texts as before (a tagged text remembered from
before a climax still ages out normally).

## 4. Test law (append-only, each red→green)

1. Exactly four tagged events, set-equality, all adult.
2. Locked wheel (200 seeds): no tagged text, 8 distinct, full adult slots.
3. Baseline wheel still serves every one of the four across seeds.
4. Saturate recency with all other adult texts: still none under lock.
5. Service closure is live per spin; absent closure never gates.
6. Real ChatService wiring: unlocked serves / hard lock pulls / soft keeps
   / releasing serves again (4 guards, new file).
   Red proofs: filter dropped from the wheel call, take-then-filter
   (dead slots), needs-event untagged, closure dropped from wiring — 4/4
   red on exactly their guards, then green.

## 5. Web parity

The wheel is built engine-side for all three surfaces (desktop overlay,
web, manual) through the one `spinWheelEvents`; web needs no separate
change. No labels, no toggles, no new UI. `web_ui` has no wheel-pool
duplicate (verified by grep) — recorded here instead of a diff.

## 6. Hygiene budget

`chaos_event.dart` 55→71, `chaos_pools.dart` 87→~100, `chaos_pool_adult`
roughly flat, service +14, wiring +18; new test file is a leaf. All far
under the bar; format+analyze clean.

## 7. Consequences accepted

- Group closure branch (name→card→member-slot) has no unit guard: the
  members map is private to ChatService and the group-boot harness costs
  more than the branch's four lines. Mitigations: every failure mode is
  fail-open (a missed mapping reads false → today's wheel), the mapping
  copies the proven `_mutualAfterglowOpening` idiom, and chaos-level
  guards pin the behavior the closure feeds. Reviewed (§4b) — not raised
  as blocking.
- SFW desire-adjacent events stay legal by design (only the adult four
  assert outright arousal).

## 4b. Hostile-review ledger (commit `6a4822b69`)

- **M1 (MAJOR, fixed + red-proven)** — a manual SPIN NOW parks
  `_webChanceTimeEvent` WITHOUT halting generation (`requestManualChanceTime`
  sets no completer), and `acceptPendingChanceTime` re-resolves the speaker
  at accept time while the gate ran once at spin time. A group pointer
  rotating onto a body locked the whole window, or an intervening 1:1
  climax, could land a desire-asserting card on a `Lust: 0` body — the exact
  trust break this PR closes. Fix: `applyChanceTimeResult` re-gates against
  `_hardLockForSpeakerNamed(charName)` and swaps the first desire-free
  event from a fresh gated spin (legality over the shown card). Three new
  guards (parked-tagged swapped / unlocked verbatim / locked-untagged
  untouched); red by disabling the accept check.
- **m1 (documented)** — `GroupTurnManager.nextSpeaker` is null for random
  turn order, so attribution falls back to the LAST speaker there; the gate
  and the event text stay consistent (both name that body) but the actual
  random responder can differ. Fail-soft, pre-existing inheritance; the §1
  "upcoming speaker" line reads exactly for round-robin only.
- **m2 (accepted)** — duplicate member names gate the wrong twin; the whole
  Chance Time surface keys on name and names are not uniqueness-enforced.
  Inherited, not amplified; fail-soft.
- **m3 (maintainer judgment)** — the aphrodisiac and flirting-back events
  assert a desire CAUSE, not the outright state the four tagged ones assert;
  left untagged at the design's "assert outright arousal" bar.
- **m4 (noted)** — `ChaosModeService.chanceTimeEventPool`/`chanceTimeNsfwPool`
  are ungated static pools, tests-only consumers today; any future direct
  sampler would bypass the gate.
- **m5** — `chat_service_wiring_realism.dart` sat at 488; the fix MOVES the
  lookup into `chat_service_controls.dart`, restoring slack.
- **Checked clean:** spin path has no ungated pool sampler (auto pressure
  rolls a bool and always routes `spinWheelEvents`; all three callers
  audited); pool math exact (82 adult, no dupes, tagged set == four);
  `running => minutes > 0` means clock-off locks gate correctly (the
  suspected blocker is dead); recent-memory stores raw texts so the new flag
  needs no serialization; no `ChaosEvent` field consumed by any exhaustive UI
  switch; slot freshness held by per-beat elapse + turn-end scalar flush;
  test law append-only and the `nsfw_cooldown_default` pref genuinely seeds
  the adult pool (the baseline guard proves liveness).
