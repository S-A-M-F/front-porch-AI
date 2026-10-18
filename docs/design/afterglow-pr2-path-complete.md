# Afterglow PR 2 — recovery profile + structured sex (path-complete fill)

Companion to [afterglow-recovery-overhaul.md](afterglow-recovery-overhaul.md)
PR 2, filled per [path-complete-chat-work.md](path-complete-chat-work.md)
before code, as the overhaul plan requires. PR 2 adds two pieces of
**card-identity data** (`sex`, `RecoveryProfile`) and one **behavior input**
(a card-fixed hard-lock length that replaces the judge's number at climax).
It adds no new session/turn state — the refractory's existing minute ledger,
receipts and snapshot plumbing carry the (possibly overridden) number
untouched. PR 3 consumes the mode for real; until it lands `soft` behaves
as `hard` (stored, not acted on).

## 1. Turn-event matrix

The non-scalar state this change creates: `sex` + `recovery` on the card
(identity, like `intimateInto` — never session state). The refractory's
minutes value now may come from the card instead of the judge; every other
refractory mechanic is byte-identical to today.

| Event | Done? |
|-------|-------|
| **Normal send** (1:1) | Yes — `AfterglowPass.runClimaxPass` reads the active host's card, resolves the profile, and `applyClimaxEffects(fixedMinutes:)` starts the lock at the card's minutes when set, else the judge's turns × 15. A hard lock of 0 starts no refractory; arousal still resets. |
| **Normal send** (group, per speaker) | Yes — same code path; post-gen already makes the active character the turn's speaker (PR 1's pinned contract), so each member gets **their own card's** profile. No per-member override (plan ruling): the card's setting is the only one. |
| **Continue** | Yes — the pass reads the new text only, as pinned today; a climax found in a continuation applies the same resolution. Continue still does not tick the clock. |
| **Regenerate** | Yes — `chat_service_regen_revert.dart` reads `climax_triggered`/`pre_climax_arousal` and resets the refractory exactly as today; the length's *source* (card vs judge) is not revert state — the card still says the same thing. (PR 3 replaces `none` with the pre-climax snapshot; PR 2 changes nothing there.) |
| **Swipe** alternate | Yes — the post-beat receipt stores the full `Refractory`, which is minutes/total/opened regardless of where the minutes came from. |
| **Delete** (bot/user tail) | Yes — `restoreBeforeBeat`/pre-beat receipts unchanged; the rewind value is just data. |
| **Edit** history | Yes — state replay reads the same `RefractoryKeys`; no new keys added in PR 2. |

Prompt paths: PR 2 adds **no** new prompt injection. The refractory lines in
`nsfw_injection.dart` / `realism_prompt_fragments.dart` read
`refractory.minutes`, which is mode- and source-agnostic. Full generate /
Continue partial / overflow / impersonate therefore need no branch (N/A by
absence — the number they read is the number that ran).

## 2. Twin systems

| Twin | Status |
|------|--------|
| Desktop form ↔ web (`web_ui` + facade + routes) | Both ship: desktop `RecoveryBlock` in the Optional-features card; web block in `RealismFormSection.tsx`; `RealismValues.sex`/`.recovery` declared in `realismTypes.ts` (the "declare it or the next save drops it" rule); Dart bridge reads both with base fallback and writes both back. |
| Card codec (`toJson`/`fromJson`) ↔ web save bridge (`frontPorchFromFields`/`frontPorchToJson`) | Both wired; the bridge nests `recovery` (the `inventory` precedent) so a phone edit that doesn't touch them keeps them (pinned by test). |
| Creator paths: manual create (`create_character_saver` + `creator_realism_step`), AI creator (`creator_state_engine`, `…profile.dart`, `…core.dart`, `steps/realism_step`), edit page (`edit_character_draft/_save/_realism_section`) | All wired for recovery; `sex` persists at chargen — AI paths stamp `normalizeCharacterSex(narrativeSex)` beside `stampNarrativeVoice` (web AI chargen rides the same engine), the AI creator's ext build reads the template's `sex` field. Manual page and edit page carry `sex` unchanged (no new control — the author's explicit kind comes from the preset dropdown). |
| 1:1 ↔ group | One apply path (`applyClimaxEffects`) for both; group members' refractory already keys per body; per-member UI passes `showRecoveryBlock: false` (ruling: no per-member override). |
| Group seed (`group_chat_committer`) | N/A — group members' recovery is read from each member's own card at climax time, never from the per-chat seed ext; adding it to the seed would create a second, lying source. |
| `.porch` export + both importers + `.fpchat` | Pass-through by construction: exporters embed `toJson()` and importers call `fromJson()`; the two explicit field enumerations are the codec and the web bridge, and both learn the fields. |
| Stoop relay/backporch | Additive JSON under `realism_engine` (`sex`, `recovery`) — old apps ignore unknown keys, additive-only rule respected. |
| `ClimaxEval.physiologyFor` (reads the card for the judge) | Deliberately unchanged: the fixed-length preset replaces the judge's answer, not its detection; the physiology slot keeps feeding detection quality. |

## 3. Test law

- New guards appended to existing feature files (no edits to existing tests):
  `test/models/preferences_round_trip_test.dart` (card wire + web bridge +
  "an older web client that omits the keys keeps them" + junk reads),
  `test/services/chat/nsfw_service_test.dart` (`fromMinutes` canonical,
  fixed-minutes apply, 0 starts nothing),
  `test/services/chat/afterglow_independence_test.dart` (the speaker's card
  minutes replace the judge's number; a card without them keeps the judge's;
  group reads the speaker's card),
  new `test/models/recovery_profile_test.dart` (preset table, lenient sex,
  resolution incl. the blank→hard prior, suggestion).
- Web: vitest appended in `web_ui` next to the realism form tests (preset
  parity with the Dart table).
- Red→green evidence goes in the PR body.

## 4. Web parity

Shipped in this PR: `RealismFormSection.tsx` block (dropdown + slider +
"resolves to" + replies hint + suggestion), `realismTypes.ts` model +
defaults + preset/suggestion mirror, Dart bridge round-trip. No deferrals.

## 5. Known consequences (accepted, documented)

- Sub-15-min fixed values read as "1 reply" with the clock off — the same
  quantization floor the plan's decision 1 accepts (Needs precedent).
- With the clock **on**, a card-fixed length is honored exactly (the ledger
  is minutes-native); with it **off**, `ceil(minutes/15)` replies.
- A card whose `sex` is blank/other and profile `auto` is hard-lock =
  today's behavior; "no card gets surprised".
