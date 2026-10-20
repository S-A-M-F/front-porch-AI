# Afterglow recovery overhaul — personality judge, recovery profiles, soft-gate mode

Status: **APPROVED — all PRs (1–8), maintainer sign-off 2026-10-17 (PRs 5–8
promoted from follow-ups the same day). Revised the same day after a
line-by-line check against the code** (file paths, test pins, persistence and
file-size budgets corrected; four open points ruled by the maintainer:
decisions 3, 4, 6 and 8 — the mode field, the peak math, the warm-again beat,
a required `user_climaxed`). A second pass the same day verified every
remaining "verify" claim and the research citations against their sources,
and the maintainer ruled four more points: groups follow each member's own
card (no per-member override), one peak per reply on Continue, one neutral
warmth-tail line, and the mockup updated to match. **Ready for
implementation.** Written 2026-10-17
from a verified code + git audit of the "every character refracts ~6 turns"
report and the follow-up design conversation (futanari handling, soft-gate
mechanics, cuddle-time preservation). **UI reference:
`~/Desktop/afterglow-ui-mockup.html`** — pixel-faithful renderings of the
actual screens (sidebar, character editor, Porch Life) measured from
`realism_progress_row.dart`, `bond_bars.dart`, and web `forms.css`; the
implementing agent matches these frames, dark and light. The mockup's text was
updated 2026-10-17 to match this plan (the "Lock, length by personality"
dropdown entry, the warm-again beat, the required field, one tail line); where
the two ever disagree on behaviour, this document wins and the mockup is
fixed.

**PR 1 SHIPPED 2026-10-18** — merged to Rawhide as `521bf6055` (PR #553).
Live acceptance ran on the Linux media server against llama-server
Qwen3-14B-Instruct, driven through the real app (wizard-created cards, real
climax turns): the insatiable card judged `refractory 0 min` — no refractory
started, no sidebar line — and the reserved card `refractory 180 min` with
the user-visible chip "Refractory: about 180 min". Same model, same message,
personality alone moved the number. Full method and numbers recorded in the PR.
**Maintainer ruling 2026-10-18 — stacking:** PRs 2–8 land as one **stacked
chain**: each PR branch is cut from the previous PR's branch (PR 3 bases on
PR 2's branch, PR 4 on PR 3's, …), so the tip of the stack is the single
end-to-end testable branch where the whole poke script runs. PR 2 bases on
`Rawhide` as of `521bf6055`. Merges go bottom-up into `Rawhide`, one per
maintainer green light; a PR's CI runs against its stack base.

This is chat/realism work: the executor fills
[path-complete-chat-work.md](path-complete-chat-work.md) before code, and the
Needs-on-the-clock dual-mode precedent
([needs-on-the-clock.md](needs-on-the-clock.md), `needs_wear.dart`) governs all
time-vs-turns mechanics.

## The problem (verified)

Every character gets ~6 refractory turns (~90 min) after climax, regardless of
who they are. Root causes, each confirmed against code and git:

| # | Cause | Evidence |
|---|---|---|
| 1 | The climax judge has **zero character input**. `d688efe07` (Apr, "Make intimacy refractory period dynamic based on character personality") added the card's personality (capped at 600 chars) and the guidance "a normal character 5-7 turns, a highly sexual one 1-2 — use their traits". `b50702be5` (Jun consolidation) kept the personality but dropped the cap and the guidance sentence; `e943ba20c` (Aug) dropped the personality itself when the question moved to the standalone `ClimaxEval`. Two commits, two losses, one symptom. | `climax_eval.dart:80-120` takes only `charName/reply/recentExchange` |
| 2 | Rubric anchored high: "int from 3 to 7 (~6-7 intense / ~3 quick)" (from `ba40b23c4`). | `climax_eval.dart:88-91` |
| 3 | Fusion (`a2b4831b8`) made collapse near-certain: one low-temp forced-tool multi-question call per turn; small local models mode-collapse on a single small int. | `reply_facts_eval.dart` |
| 4 | **Parser floor bug:** `parseRefractory` clamps to **1–10**, so a judge answer of 0 ("no cooldown needed") silently becomes 1 turn = 15 min. "No refractory" is inexpressible today. | `climax_eval.dart:133` |
| 5 | `CharacterCard` has **no structured sex field** — sex exists only at chargen (`creator_template_schema.dart:60` `sex`, `narrative_voice.dart:278-314`) and evaporates into prose. Nothing downstream can know a character is female. | grep: no `sex`/`gender` on `character_card.dart` or `front_porch_extensions.dart` |
| 6 | One mechanic for everyone: climax always zeroes arousal + hard lock (`nsfw_service.dart:189-192`), which mis-models female-typical recovery (often no capacity lock; multiple orgasms are common — Masters & Johnson 1966 report a short or absent refractory period in women; Darling, Davidson & Jennings 1991, *Arch Sex Behav* 20:527-40, found 42.7% of 805 women surveyed had experienced multiple orgasms). | `applyClimaxEffects` |

Arousal runs **−100…+100** (`nsfw_service.dart:205-210`); every number below is
on that scale.

## Design decisions (settled with the maintainer — do not re-litigate)

1. **Minutes are the canonical ledger; turns stay the clock-off lens.** This is
   already how `Refractory` stores state (`refractory.dart:11`,
   `kRefractoryMinutesPerTurn = 15`) and how Needs dual-ticks
   (`needs_wear.dart` `needsWearPerHour` / `needsTickPerReply` — two
   independently tuned constants, never converted). Do not invent a third
   mechanism. Clock off: 15 min drain per speaker reply (existing
   `AfterglowPass.tickPerReply`, `afterglow_pass.dart:181`). **Everything new
   in this plan that ages — the tenderness window, the peak stamps, the warmth
   tail — ages in story minutes the same way; no reply counters.** The
   quantization floor (sub-15-min values read as "1 reply") is an accepted,
   documented consequence — cite the Needs precedent.
2. **Mode (hard lock vs soft gate) is the profile's job. Sex is only the `auto`
   prior.** `auto` resolves: structured sex male → hard lock; female → soft
   gate; anything else (futanari, shapeshifter, unspecified, imported card with
   no sex) → **hard lock** (today's behavior — no card gets surprised). The
   author's explicit mode always beats the prior. This is the fix for "the
   system fights character descriptions."
3. **Two stored values, each with one job (ruled 2026-10-17).**
   `recoveryMode` (`auto` / `hard` / `soft`, default `auto`) picks the kind;
   `recoveryMinutes` (0–180, or null = the judge decides) sets the length of a
   hard lock. Soft gate ignores the minutes — its tenderness window is a fixed
   ~15 story minutes (decision 4). The editor's one dropdown is a set of
   presets over both fields, so there is still no "which wins" branch:

   | Preset | `recoveryMode` | `recoveryMinutes` |
   |---|---|---|
   | Auto (default) | auto | null |
   | None / multiorgasmic | soft | null |
   | Lock, length by personality | hard | null |
   | Short (30 min) | hard | 30 |
   | Typical (90 min) | hard | 90 |
   | Long (180 min) | hard | 180 |
   | Custom (slider moved) | hard | slider value |

   A hard lock of 0 (judge or slider) starts no refractory; arousal still
   resets as today.
4. **Soft-gate mechanics (peak math ruled 2026-10-17):** on climax — no
   arousal zero. Peak cost
   `arousal -= round(0.2 × max(arousal − 50, 0) × peaks)`, where `peaks`
   counts this story hour's peaks including this one, **capped at 3**. Each
   peak takes a bigger bite, so the body winds down on its own: from 100 the
   first peak leaves 90; a second from 95 leaves 77; a third from 90 leaves 66.
   **The cap is what keeps the floor:** with `peaks ≤ 3` a climax that starts
   at ≥ 50 never ends below 50 (it keeps at least 40% of the distance above
   50); without the cap a sixth peak would push below 50. A climax that starts
   below 50 costs nothing. A ~15-story-minute tenderness window halves arousal
   **gains** only (positive deltas; reuse the halving in
   `applyEvalArousalDelta`, `nsfw_service.dart:206-208`, but not its −10
   floor or its halving of negative deltas — those are hard-lock semantics).
   Climax detection already runs every turn, lock or not
   (`afterglow_pass.dart:83` has no refractory gate), so a second climax
   during the window needs nothing re-enabled: it counts a peak and restarts
   the window. **One peak per reply (ruled 2026-10-17):** on Continue the pass
   reads only the new text (`chat_service_generation_postgen_engine.dart:145-149`);
   if the reply already carries `climax_triggered`, a climax found in the
   continuation restarts the tenderness window but adds no peak, so a misread
   of the aftermath cannot stack peaks. The hard path stays absolute as today.
5. **Peaks age on the minutes ledger.** Store up to three peak stamps as
   "story minutes since that peak" beside the refractory; `peaksLastHour` is
   the list's length. Each beat adds its elapsed minutes (clock on) or 15 per
   speaker reply (clock off, through `tickPerReply`), and a stamp that reaches
   60 drops — so with the clock off a peak clears after four of the speaker's
   replies without a separate counter. The stamps ride the existing pre/post
   beat receipts (`noteRefractoryBeat`, `refractory.dart:158`) so
   regen/swipe/delete rewind them.
6. **Cuddle time is kept, not ripped out.** The hard-lock injection ladder
   (`nsfw_injection.dart:98-116`) ships unchanged. Soft-gate bodies get a
   parallel ladder whose beats replace incapacity ("the body simply cannot
   respond yet") with tenderness ("a flinch that turns into leaning in"):
   **glow** (opening turn) → **tender** (while the window runs) →
   **warm-again** (after the window, for as long as any peak is still counted,
   i.e. up to one story hour; ruled 2026-10-17; no chip — the rose chip
   shows only during the window) → the normal arousal ladder.
   Without warm-again, a soft body at ≥ 50 would drop straight into the
   "heavily aroused — chasing release" rung (`nsfw_injection.dart:145-150`)
   15 minutes after climax and cuddle time would be gone. **Pronoun-free
   contract (load-bearing):** the shipped ladder interpolates `$name` and
   speaks of "the body" — never gendered pronouns. Every new rung keeps this
   contract; the guard matches **whole words, case-insensitive**:
   `\b(she|her|hers|herself|he|him|his|himself)\b`. (A bare `she|he|her|his`
   matches inside "the", "other" and "there" and fails on the shipped ladder.)
7. **PR 1 ships alone first.** It is the root-cause fix; PR 2+3 are one
   path-complete feature piece behind it.
8. **`user_climaxed` is required whenever the climax question is asked
   (ruled 2026-10-17).** The schema carries the recorded lesson
   (`realism_tool_schemas.dart:399-402`): a model fills in what the schema
   demands and skips what it does not, which once switched climax detection
   off on every tools-capable backend. An optional field would rarely be
   answered and the mutual beat would rarely show.

## Persistence (applies to PR 3 and PR 4)

The refractory is saved in more places than `refractory.dart`. Every one of
them must carry the new state, or it is lost on reload, export or group
restore:

- Session DB columns — `database.tables.core.dart:139-152` (v55 minutes
  columns). **DB change: plan before code.** Additive nullable columns only
  (soft flag; peak stamps as JSON text; tail minutes), schema version bump,
  regenerate `database.g.dart`; a NULL reads as hard / no peaks / no tail, so
  every existing row means exactly what it means today.
- Snapshot, member-map and receipt keys — add to `RefractoryKeys`
  (`refractory.dart:15-22`) so `group_member_realism.dart:77-83`,
  `nsfw_service.dart:292` and the receipts pick them up.
- Session hydrate / save / import — `chat_service_session_hydrate.dart:224-228`,
  `chat_service_session_state_save.dart`, `chat_service_import_seed.dart:279-288`.
- `.fpchat` export — `fpchat_format.dart:53-59`.
- Web snapshot — `lib/services/web/facade/chat_tools/chat_tools_snapshot.dart`.

Message-metadata stamps (`user_climaxed`, the PR 8 roll) need no schema change.

**Regen undoes a climax separately from the receipts.**
`chat_service_regen_revert.dart:150-160` reads `climax_triggered` /
`pre_climax_arousal` off the rejected reply, restores the arousal and sets
`Refractory.none`. That is right only when no afterglow state existed before
the climax. With soft gate (peak 2 inside the window) or a climax during the
warmth tail it would wipe the earlier state. PR 3 stamps the full pre-climax
body (`pre_climax_refractory`: minutes, total, opened, soft flag, peak stamps,
tail) beside `pre_climax_arousal`, under the same first-reading guard
(`afterglow_pass.dart:115`), and the revert restores that snapshot instead of
`none` (falling back to `none` for replies stamped before PR 3). Manual
Reprocess keeps "a climax's reset stands"
(`chat_service_reprocess_choice.dart:365`), which holds for the soft peak cost
too.

## PR 1 — restore the personality judge (root cause, zero extra LLM calls) — ✅ SHIPPED 2026-10-18 (`521bf6055`)

Keep the tool field name `refractory_turns` (renaming ripples through the
converter registry, fused schema, and five test files for no user gain).
Widen its range to **0–12** (×15 → 0–180 min).

Touchpoints:

- `lib/services/chat/climax_eval.dart`
  - `rubric(String charName)` → `rubric(String charName, [String physiology = ''])`:
    de-anchor (drop the "~6-7"/"~3" numeric tilt, qualitative anchors only),
    range 0–12, restore "use their traits to decide" guidance, and state that
    0 is a valid common answer. Keep the phrases "CLIMAX DETECTION" and "are
    NOT a climax" (pinned at `afterglow_independence_test.dart:64-67`). An
    empty physiology omits the traits line.
  - `buildPrompt` / `detect` take `physiology` as an **optional** named
    parameter (default `''`). Optional on purpose: existing tests call
    `rubric`/`buildPrompt` without it (`reply_facts_fusion_test.dart:133,148,154`,
    `climax_scene_context_test.dart:49,114`, `afterglow_independence_test.dart:57`),
    and a required parameter would break their compile.
  - **Physiology source**, capped at **600 chars** total (the `d688efe07`
    cap; the post-gen budget is tight): the authored intimate preferences
    first (`intimateInto` / `intimateNotInto`,
    `front_porch_extensions.dart:121-122`), then `personality`; when
    `personality` is blank (common on imported cards), the opening of
    `description`.
  - `parseRefractory`: fallback `?? 5` stays (75 min — the "climax reported,
    length missing" floor; no later PR changes it), clamp becomes
    `.clamp(0, 12)`. **0 must survive.**
- `lib/services/chat/reply_facts_eval.dart` — thread `physiology` through
  `buildPrompt`/`fetch` (the rubric fragment is embedded verbatim at
  `reply_facts_eval.dart:115`, so one rubric edit fixes both transports).
- Call sites pass the physiology: the standalone call in
  `AfterglowPass.runClimaxPass` (`afterglow_pass.dart:95-105`) and the fused
  call built by `ReplyFacts.prefetch` (`reply_facts.dart`, wired in
  `chat_service_wiring_evals.dart:111-145`). Group: the card of the
  **reply's speaker** — never the previous speaker (see the group-safety
  contract in `nsfw_injection.dart:41-47`). Verified: post-generation sets
  the active character to the turn's speaker
  (`chat_service_generation_postgen_engine.dart:59`) before both passes run,
  and both read it (`afterglow_pass.dart:87`, `reply_facts.dart:61`), so the
  active character's card is the right source in groups too.
- `lib/services/chat/realism_tools/realism_tool_schemas.dart:371` — schema
  description "Cooldown turns (3-7)…" → "(0-12…)".

Tests:

- `test/services/chat/afterglow_independence_test.dart:124-128` pins
  `refractory_turns: 99` → **10** ("and it stays clamped"); with the 0–12
  clamp it becomes 12. This is the one existing assertion PR 1 changes
  (`approved-test-change`; rationale: the range widened on purpose). The
  missing-field fallback pin (`:117-123`, exactly 5) and the required-fields
  pin (`:89`) are unchanged.
- `test/services/chat/reply_facts_fusion_test.dart` — the existing parity
  asserts compile and pass with the optional parameter. **Append** a test that
  both prompts carry the identical rubric **with the physiology slot filled**
  (the guard that catches drift).
- `test/services/chat/climax_detection_tool_schema_test.dart` — has no
  range-text assertion; no edit needed.
- New guards, proven red then green: (a) the physiology text appears in the
  standalone and fused prompts; (b) `parseRefractory` of
  `{"is_climax":true,"refractory_turns":0}` returns 0, not 1, and applying it
  starts no refractory; (c) in a group, the physiology is the reply speaker's.
- `refractory_turns: 6` canned values (`tool_registry_test.dart:127`,
  `reply_facts_fusion_test.dart:247`, `climax_detection_tool_schema_test.dart:129`,
  `afterglow_independence_test.dart:100`, `integration_test/support/fake_backend.dart:558`)
  stay valid inside 0–12 — no edits needed.

Acceptance: `fake_backend` answers a canned 6 whatever the prompt says, so it
cannot show that personality changes the number — and a fake that varied by
personality would be a stub planting the answer (CLAUDE.md "No stub tests").
Acceptance is therefore (1) the unit guards above, and (2) a **live run on
the Linux media server** with a real local model: two cards with different
personalities, the same climax scene, visibly different `refractory_turns` in
the `[Afterglow]` debug log, numbers recorded in the PR; and a 0 answer
starts no refractory.

## PR 2 — recovery profile + structured sex (path-complete piece, with PR 3)

Data:

- `front_porch_extensions.dart` is **455 lines**; three new fields with
  constructor, `copyWith`, `toJson` and `fromJson` (plus PR 8's one) would
  push it to the 500-line bar. Put the recovery fields in a small value class,
  e.g. `lib/models/character/recovery_profile.dart` (`recoveryMode`,
  `recoveryMinutes`, and later `pcdMood`, with its own `toJson`/`fromJson`),
  held by one field on `FrontPorchExtensions`.
- `sex` on `FrontPorchExtensions` — stored normalized as `male` / `female` /
  `other` / blank; read leniently (case-insensitive; "man"/"woman"/"m"/"f"
  map; any other non-blank value → `other`). Persisted at chargen from the
  template / interview answer (`creator_template_schema.dart:60`,
  `narrative_voice.dart:278-314`). Additive JSON key so Stoop round-trips stay
  readable by older apps.
- `recoveryMode` (`auto`/`hard`/`soft`, default `auto`) and `recoveryMinutes`
  (int 0–180, default null) — decision 3. A missing key reads as the default,
  so old cards and old apps behave as today.
- Codec + round-trip: `toJson`/`fromJson`, `porch_exporter.dart`, both
  importers (`lib/services/character_store/character_importer.dart` and the
  web facade's `lib/services/web/facade/character/character_importer.dart`),
  and the web character save path — a card shared on the Stoop must not lose
  its profile. Add a round-trip test.
- **Web save bridge (data-loss trap, verified):** the phone's card editor
  saves through `frontPorchFromFields` / `frontPorchToJson`
  (`lib/services/web/util/realism_extensions_json.dart:40`, `:242`), which
  rebuild `FrontPorchExtensions` from an explicit field list. A field missing
  from that constructor call silently takes its default on every web save —
  the file records exactly this wiping starting inventory. `sex` and the
  recovery profile must be read there with the base as fallback (the profile
  nested, the way `inventory` is) and written back in `frontPorchToJson`.
  Test: a web edit that does not touch them keeps them.

Behavior:

- `AfterglowPass.runClimaxPass` / `applyClimaxEffects`: resolve the mode
  (decision 2). Hard: when `recoveryMinutes != null` the slider minutes
  **replace** the judge's number; when null, the judge's number stands. Soft:
  PR 3.
- `Refractory.fromMinutes(int)` becomes the canonical constructor;
  `fromJudgeTurns` (`refractory.dart:42`) becomes a legacy wrapper
  (`turns × 15`).
- Until PR 3 lands, `soft` (explicit or resolved from `auto`) behaves as hard
  — the field is stored, behavior unchanged.

UI (desktop **and** web — parity is law):

- Desktop: `lib/ui/widgets/realism_form_section/realism_optional_features_card.dart`
  — "Recovery after intimacy" block under the Afterglow toggle: the preset
  dropdown (decision 3's table) + 0–180 "Recovery minutes" slider (shown for
  every preset except "None / multiorgasmic" — maintainer ruling 2026-10-18,
  superseding the mockup's "always shown": the soft gate has no length, so it
  shows the fixed-window line instead of a slider whose first drag flips the
  card to a hard lock; moving it elsewhere selects Custom) + live "≈ N replies
  with the clock off" hint + a plain-English "resolves to" line naming the kind and
  the length (e.g. "Auto → soft gate (card says female)"). The block shows
  only when Afterglow and 18+ themes are on.
- Web: `web_ui/src/components/realism/RealismFormSection.tsx` +
  `realismTypes.ts` mirror the same block (this also covers web character
  creation, which uses the same section).
- Group: **no per-member override (ruled 2026-10-17).** Each member follows
  the recovery setting on their own card, which travels with the card; the
  refractory already keys per body (`group_member_realism.dart`). (The web
  app has no per-member realism settings, so a group override would have
  shipped desktop-only.)
- Chargen: persists `sex`, and **suggests** a preset from the intimacy answer
  (`interview_questions.dart:177-180`) — the author confirms, never silent.
  Auto stays the default; the suggestion says plainly that any preset other
  than Auto / "Lock, length by personality" sets a fixed length instead of the
  personality judge.

## PR 3 — soft-gate mode + cuddle decouple

- `nsfw_service.dart`: `applyClimaxEffects` branches on mode. Soft: peak-cost
  formula (decision 4), no zero, set the tenderness window instead of a lock.
  `applyEvalArousalDelta`: the soft window halves gains only (decision 4);
  hard-lock path untouched.
- `refractory.dart`: the tenderness window is a `soft` flag on `Refractory`
  (it already dual-ticks and receipts; a separate timer class would fork the
  clock math), plus the peak stamps (decision 5) and their `RefractoryKeys`;
  `noteRefractoryBeat` carries them. `elapse()` end-state: hard halves
  negative arousal (keep); a soft window just expires. Persistence: see the
  Persistence section.
- **Every reader of a running refractory must branch on `soft`**, or a soft
  body gets hard-lock copy and physics: `nsfw_service.dart`
  (`applyEvalArousalDelta`, the chip words), `nsfw_injection.dart`,
  `realism_prompt_fragments.dart:156-160`, `realism_prompt_builder.dart`,
  `realism_evals/realism_eval_calls.dart`, `realism_evals/realism_eval_one_shot.dart`,
  `bond_bars.dart`, web `ChatToolsRealism.tsx` / `ChatToolsShared.tsx`, and
  PR 6's chaos filter (hard lock only). Grep
  `refractoryMinutesRemaining|refractory\.running|refractoryMinutesLeft|isOpeningAfterglowTurn`
  before calling the list complete.
- `afterglow_pass.dart`: peaks age on the beat (decision 5) in
  `tickAfterClock` (clock on) and `tickPerReply` (clock off).
  `_moveRefractory` returns early when no lock is running
  (`afterglow_pass.dart:241`); peaks (and PR 4's tail) outlive the lock, so
  that guard becomes "nothing left to age" (no lock, no peaks, no tail).
- `describeRefractory` (`refractory.dart:130`): soft copy — "Tender for about
  N min · peak K" (rose chip, the mockup's wording) vs "Refractory: …" (frost
  chip). The web reads the same text as `refractoryLabel`
  (`ChatToolsShared.tsx:78-85`), so copy lands once.
- `afterglow_pass.dart` + `chat_service_regen_revert.dart:150-160`: stamp and
  restore `pre_climax_refractory` (see "Regen undoes a climax" under
  Persistence), and apply decision 4's one-peak-per-reply rule on Continue.
- Fix the "just climaxed" wording in the **eval note**
  (`realism_prompt_fragments.dart:156`, "NOTE: $charName just climaxed and is
  in the post-orgasm refractory"): it rides every turn of the lock and reads
  wrong late in a 3-hour one. The injection's "just climaxed"
  (`nsfw_injection.dart:99`) is opening-turn only and stays.
- `nsfw_injection.dart`: the soft ladder — glow → tender → warm-again
  (decision 6; copy in the mockup). Guard (red→green): the whole-word pronoun
  regex of decision 6 finds nothing in any ladder string — the shipped file
  passes it and the new rungs must too.
- `realism_prompt_fragments.dart:156-160`: the eval's refractory note
  branches — soft: "oversensitive but desire stays up; touch may read as too
  much — tenderness, not rejection" (keep the −3…+5 gentle band for both).
- Sidebar: `bond_bars.dart:118-142` renders the soft chip variant; the web
  sidebar mirrors.
- Porch Life: the Afterglow blurb line names both kinds — desktop
  `lib/ui/settings/tabs/porch_life_tab.dart`, web
  `PorchLifeSettings.tsx:702`.
- Integration: `fake_backend.dart` gains a soft-gate climax mode (this tests
  the app's mechanics on a given verdict, not the model's judgement); new
  end-to-end test that a multiorgasmic card climaxes twice in one scene,
  keeps arousal ≥ 50, takes a bigger drop on the second peak, and rewinds
  exactly on regen — regenerating peak 2 leaves peak 1 and its window in
  place. A Continue on the peak-1 reply adds no peak.

## PR 4 — warmth tail (maintainer-approved 2026-10-17; rides PR 1–3)

Research basis: sexual satisfaction stays measurably raised for about 48
hours after sex (Meltzer et al. 2017, *Psychological Science*; two samples of
newlywed couples keeping 14-day diaries) — effects fade
on a curve, not at a counter boundary. Today the character snaps to baseline
the instant the refractory expires; the ladder jumps from "deep in the
afterglow" straight to silence.

- **Tail window:** hard lock — starts when the lock ends; soft gate — starts
  when the warm-again beat ends (the last peak ages out). Length = half the
  cooldown total, floor 15 min, cap 120 min. No refractory, no tail (a hard
  lock of 0 starts neither). Clock off it lasts `ceil(tail/15)` speaker
  replies automatically (decision 1).
- **Storage:** a tail field beside `Refractory` in `refractory.dart` (reuse
  the value-object + `RefractoryKeys` + receipt plumbing; it dual-ticks and
  rewinds exactly like the lock; Persistence section). `elapse()` currently
  returns `none` when the lock ends (`refractory.dart:105`); it must hand back
  the started tail instead. Ages in `tickAfterClock` / `tickPerReply` past the
  PR 3 guard change.
- **Injection:** one new ladder rung, both modes, pronoun-free (guarded). It
  speaks of warmth, not desire: at lock end arousal is usually low (zeroed at
  climax, then halved, gentle −3…+5 deltas during the lock), and prose
  claiming desire under a low Lust bar is the bar-vs-prose break PR 6 exists
  to prevent. **One line for everyone (ruled 2026-10-17)** — nothing records
  whether a climax was wanted, so the tail does not pick between a "wanted"
  and a "duty" line; the wanted/duty condition lives in PR 7's eval sentence.
  Copy: "Body: $name is still riding a warm afterglow — ordinary warmth runs
  deeper than usual today; small kindnesses land harder, and any desire that
  has come back cools slowly."
- **Eval note** (`realism_prompt_fragments.dart`): during the tail, a
  non-romantic turn while arousal is above +10 returns 0 instead of −5…−10 —
  it holds what is there and never raises it. (The bond side of the tail
  belongs to PR 7.)
- **No chip, no new switch** — it belongs to Afterglow and stays subtle; the
  prose carries it.

Tests (red→green): the tail starts exactly when the lock (or the soft
warm-again beat) ends; ages on both clock modes; rewinds on
regen/swipe/delete receipts; survives reload and `.fpchat` export; the tail
rung exists and passes the pronoun guard; the hold-not-raise rule is in the
eval note text.

## PR 5 — mutual afterglow: `user_climaxed` on the existing call

The rubric already makes the judge distinguish user-only climax
(`climax_eval.dart:86-87`) and throws the fact away. Recover it for free.

- **Schema:** `user_climaxed` boolean in `kClimaxFields`
  (`realism_tool_schemas.dart:365-373`). The fused `kReplyFactsFields` spreads
  `kClimaxFields` (`:427-428`), so one definition serves both. **Required**
  alongside `is_climax`/`refractory_turns` (decision 8): add it to the
  standalone required list (`:403`) and the fused one (`:449`, only when
  `askClimax`). Description: "true only if {{user}} also climaxed in this
  reply."
- **File size first:** `realism_tool_schemas.dart` is **494 lines**; this
  field crosses the 500-line bar. Move the Afterglow schema block (climax +
  reply-facts fields and tools) into its own file under `realism_tools/`
  first, keeping it registered in `realismToolFieldsByTool` (an unregistered
  tool silently falls back to text forever).
- **Prompt:** the rubric and the text-floor key lists ask for it too
  (`climax_eval.dart:119-120`, `reply_facts_eval.dart:107`).
- **Parser:** lenient `parseUserClimaxed` in `climax_eval.dart`, same style as
  `parseRefractory` (bool or "true"/"yes" string); anything else, including a
  missing key, reads as false.
- **Persistence:** stamp `user_climaxed` into message metadata beside
  `climax_triggered` / `pre_climax_arousal` (`afterglow_pass.dart:115-117`).
  The mutual beat is opening-turn-only, so the receipt body is unchanged;
  regen re-rolls (new timeline), swipe/restore shows that timeline's stamp.
- **Ladder:** one mutual opening variant per mode in `nsfw_injection.dart`,
  replacing the "if {{user}} starts something…" clause only when the same
  detection said `user_climaxed` true. Pronoun-free, e.g. hard: *"Body: $name
  and {{user}} came undone together — the room went soft at the edges, both
  wrecked, neither willing to move first."* Soft: shared wind-down inside the
  tenderness window.
- **Eval note:** the refractory note may reference the shared wind-down on the
  opening turn only.
- **Tests:** the existing required-field pins use `contains`/`containsAll`
  (`afterglow_independence_test.dart:89`,
  `climax_detection_tool_schema_test.dart:84,96`,
  `reply_facts_fusion_test.dart:186-191`) and should pass unchanged — confirm
  before asking for a label. New: the field is required on both tools when
  climax is asked and not when it is off; parser guard; ladder-branch guard
  (mutual line appears only when the stamp is true).

## PR 6 — chaos respects the hard lock

Verified gap: the adult pool holds 82 events (`_spicy` 70 + `_needs` 12 in
`chaos_pool_adult.dart`); four assert the character's arousal state — lines
31 ("visibly aroused"), 40 ("hide a visible physical reaction"), 91
("suddenly, intensely in the mood") and 101 ("a long dry spell… restless,
flustered, and thinking about little else"). Selection is a wheel
(`chaos_pools.dart`, adult events take `kAdultWheelSlots`), so the fix is
surgical:

- **Tag:** `desireAsserting` flag on `ChaosEvent` (`chaos_event.dart`). The
  pool's events are plain strings turned into `ChaosEvent`s by a loop
  (`chaos_pool_adult.dart:112-115`), so move the four into their own lists
  built with `desireAsserting: true`.
- **Filter:** `buildChaosWheel` (`chaos_pools.dart:51`) takes a
  `hardLockActive` bool and drops desire-asserting candidates while it is
  true. Wiring (verified): `ChaosModeService` cannot see the refractory, so
  it gets an injected closure like its existing `isAdultAllowed`
  (`chaos_mode_service.dart:52`), supplied by ChatService. The event is
  attributed to `chanceTimeSpeakerName` — the upcoming group speaker, else
  the 1:1 host (`chat_service_turn_flow.dart:235-239`; it is a name, so map it back to that card). In a group, read
  that member's stored refractory (`group_member_realism.dart`), not the live
  scalars, which may still hold the previous speaker's. Every wheel goes
  through `ChatService.spinWheelEvents` (`chat_service_controls.dart:276-281`:
  desktop overlay, web, manual spin), so one change covers all three. The
  wheel keeps spinning — the other 78 adult events and all SFW events fire as
  before (they're funnier against an afterglow: the state colors the
  reaction, it doesn't contradict it). **Soft gate needs no gate** — its
  characters keep arousal up, so desire-asserting events are consistent for
  them.
- **Rationale** (maintainer Chance-Time discussion): Chance Time is comedy
  because the rules stay legible; the sidebar is the coin counter, and
  prose-arousal under `Lust: 0` makes players stop trusting the bar. The
  "body betrays her" contradiction stays legal as a CARD-authored trait,
  never a system coin flip.
- **Tests:** the wheel excludes the four tagged events under hard lock,
  includes them at baseline and under soft gate; chaos never takes a dead
  turn.

## PR 7 — bonding surge (cooldown and tail windows, conditional)

The eval's refractory note (`realism_prompt_fragments.dart:156-160`) steers
arousal only. Oxytocin and prolactin rise after orgasm in humans; the
pair-bonding mechanism itself is mostly established in animal studies, so
this is modeled as a gentle, conditional tilt. **Conditioned, not
unconditional** (maintainer stress-test: sex-worker/dissociation archetype):
the surge tracks *wanted* intimacy + existing warmth, not orgasm itself.

- **Prompt-only:** extend the refractory note, the PR 4 tail note, and the
  bond section of the fused eval: *"If the climax was wanted and $charName
  holds real warmth toward {{user}}, affectionate contact during the
  afterglow counts more toward short-term bond; if it was duty, transaction,
  or skill on autopilot, the body cools on schedule and the heart may not
  follow."*
- Both modes, both windows (cooldown and tail), **one shared condition
  string** so the copy cannot drift. PR 7 owns this text; PR 4 adds no bond
  line of its own. The existing wanted/unwanted bands and authored tastes in
  `arousalSection` are the levers it rides.
- **No state, no new fields.**
- **Tests:** prompt guard — the conditional sentence is present in both
  windows, and the duty clause is present (the sex-worker pin).

## PR 8 — post-coital dysphoria (opt-in flavor)

Real and transient (minutes to about two hours), occurs after wanted sex and
is not about the partner. About 46% of women report it at least once and
5.1% a few times in the previous four weeks (Schweitzer, O'Brien & Burri,
*Sexual Medicine* 2015; 230 university women). About 41% of men report it at
least once, 20% in the previous four weeks and about 4% regularly
(Maczkowiack & Schweitzer, *Journal of Sex & Marital Therapy*; 1,208 men,
self-selected online survey). The per-climax rates below are **flavor dials,
not prevalence**.

- **Field:** `pcdMood` tri-state in the PR 2 `RecoveryProfile` — `off`
  (default) / `rare` (~15% per climax) / `sometimes` (~35%) — per card (a
  group member uses their own card's), additive card round-trip key, carried
  by the web save bridge like the rest of the profile.
- **UI:** third control in the PR 2 Recovery block (desktop + web parity),
  shown when 18+ and Afterglow are on.
- **Mechanics:** roll at climax detection through an injectable random source
  (seeded in tests), stamp the result beside `climax_triggered` in message
  metadata (receipt-safe; regen re-rolls). Effects: opening-turn ladder
  variant (pronoun-free — *"…and under the warmth, a sudden grey drift — not
  sad about anything, and nothing {{user}} did"*), emotion-eval note
  ("wistful/tearful, cause: something unnameable after the peak — not a
  reaction to {{user}}"), lasting the opening turn plus the speaker's next two
  replies, then the normal ladder resumes. The duration is counted from
  message history (the stamped climax message's position among the speaker's
  replies), so it needs no new state and rewinds with regen/delete for free.
- **Hard guard:** bond/trust deltas unchanged, arousal unchanged — the
  rejection-band misread (−15…−25) is the failure mode that would poison it.
  Opt-in only; existing cards never get a surprise tone-shift.
- **Tests:** codec round-trip, default-off pin (a card without the key never
  rolls), rate pin (rare/sometimes map to 15/35 with a seeded source), the
  three-reply limit, fused-prompt guard that the bond-unchanged instruction is
  present.

## Explicitly out of scope

- Fusing the needs-impact eval into reply-facts (settled: not yet, capability
  gate first).
- Renaming `refractory_turns` in the tool schema.
- Per-chat or per-group-member recovery overrides — the card's setting is the
  only one (ruled 2026-10-17).
- A stored "was this climax wanted" verdict (ruled 2026-10-17; the eval
  judges it each turn instead).
- Changes to the hard-lock mechanics beyond what this plan names: its length
  input (PR 1, PR 2), the tail hand-off when it ends (PR 4), and chaos reading
  it (PR 6).

## Poke script (manual smoke, pre-landing)

1. Two cards, one "insatiable", one "delicate"; Realism + Afterglow on; run
   each to climax in similar prose → sidebar chips show clearly different
   cooldowns.
2. Set a card to `None / multiorgasmic`; climax → arousal stays ≥ 50, rose
   "Tender for about 15 min · peak 1" chip; flirt inside the window → gain
   visibly halved; Continue that reply → still peak 1; climax again in a new
   reply inside the window → peak 2, a **bigger** drop than the first, still
   ≥ 50. Regen that reply → back to peak 1 with its window, not to nothing.
3. Let the tender window end with a peak still counted → the warm-again beat
   (affectionate, not chasing), not "heavily aroused"; an hour after the last
   peak the normal arousal text returns.
4. Toggle Passage of Time off mid-lock → chip switches to replies; four of
   their replies clear a peak.
5. Regen the climax reply → arousal, lock/tenderness, and peak count all
   rewind exactly; swipe shows the alternative's post-beat state. Quit and
   relaunch mid-window → soft flag, peaks and tail are still there.
6. Let the cooldown expire → the warmth-tail line appears in the injection
   (no chip), arousal above +10 holds on non-romantic turns instead of
   cooling, and the tail ages with the clock (or per reply with it off).
7. Export the card PNG → import on a fresh install → sex, recovery mode,
   minutes and preset survive; a card with no sex stays hard-lock. A female
   card set to "Typical 90" locks for 90 minutes.
8. Mutual finish scene → opening line reads as a shared wind-down; a
   character-only finish → today's "if {{user}} starts something…" line.
   Regen the mutual reply → the beat re-rolls with the timeline (PR 5).
9. Chaos on during a hard lock → no "visibly aroused / in the mood / dry
   spell" event for the whole lock while the other adult and SFW events keep
   firing; the same events stay legal on a soft-gate card (PR 6).
10. Wanted-climax card in cooldown → affectionate contact moves Short-Term
    Bond more than the same contact at baseline; a duty/transaction-context
    card of the same personality does not budge (PR 7).
11. Card with `pcdMood = Sometimes` → occasional melancholy opening beat that
    fades after at most three replies, bond bar unmoved by it; a card left on
    `Off` never shows it, even after fifty climaxes (PR 8).
12. Group chat with a soft-gate member and a hard-lock member → each follows
    their own card's profile, and each one's chip and lines survive a speaker
    switch; a Chance Time spin for the locked member skips the four desire
    events while the soft member's spin can still land them.
13. Edit a card's description on the phone without touching recovery → back
    on the desktop, sex, recovery mode and minutes are unchanged.

## Labels / process notes for the executor

- Existing-test edits needing `approved-test-change`: PR 1 —
  `afterglow_independence_test.dart:124-128` (clamp ceiling 10 → 12) — done,
  labeled, merged. PR 5
  should need none (the required-field pins use `contains`/`containsAll`);
  confirm. Anything else that turns red is a finding to explain, not a pin to
  edit. Appending new `test(`/`group(` calls is unbounded.
- Every new guard proven red, then green. No stub tests.
- Behaviour changes run live on the Linux media server before merge.
- `dart format` touched files only; analyzer clean on touched Dart; < 500
  lines per handwritten file. Budgets today: `climax_eval.dart` 167,
  `refractory.dart` 195, `afterglow_pass.dart` 338, `nsfw_service.dart` 308,
  `nsfw_injection.dart` 166, `front_porch_extensions.dart` **455** (extract,
  PR 2), `realism_tool_schemas.dart` **494** (extract, PR 5).
