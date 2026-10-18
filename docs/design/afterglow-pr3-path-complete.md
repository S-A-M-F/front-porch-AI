# Path-complete fill — Afterglow PR 3 (soft-gate mode + cuddle decouple)

Companion to [afterglow-recovery-overhaul.md](afterglow-recovery-overhaul.md)
(decisions 1–6, Persistence section, § PR 3) and
[afterglow-pr2-path-complete.md](afterglow-pr2-path-complete.md). PR 3 is a
stacked commit on the PR 2 branch (`feat/afterglow-pr2-recovery-profile`), so
the tip stays the single end-to-end testable branch of the maintainer's
stacking ruling.

State added by PR 3 (all on `Refractory`, all on the minutes ledger):

- `soft` — the body recovers through a tenderness window, not a capacity lock.
- `peaks` — up to three "story minutes since that peak" stamps; a stamp drops
  at 60 min; `peaksLastHour` is the list length.

## 1. Turn-event matrix

| Event | Behaviour for `soft` + `peaks` | Done? |
|-------|-------------------------------|-------|
| Normal send (1:1) | Climax stamps `climax_triggered`, `pre_climax_arousal` AND `pre_climax_refractory` (full pre-climax body: minutes/total/opened/soft/peaks) under the same first-reading guard; peak cost `arousal −= round(0.2 × max(arousal−50,0) × peaks)` applied in `applyClimaxEffects`; window restarted at `kTendernessWindowMinutes`. Beat ticks (clock on: this beat's minutes; off: 15/reply) age the window AND every peak stamp through `elapse`. | yes |
| Normal send (group, per speaker) | Same code path — mode/sex read from the SPEAKER's card (post-gen already activated them); peaks/window live in the member map via `toSnapshot` keys added to `RefractoryKeys.all`, so `loadNsfwScalarsForSpeaker` / `saveNsfwScalarsToGroup` carry them. Observable behaviour identical to 1:1 for that card. | yes |
| Continue | Pass reads only the new text. If the reply already carries `climax_triggered`, a climax found in the continuation **restarts the window but adds no peak and costs no arousal** (`newPeak: false`) — a misread of the aftermath cannot stack peaks (decision 4). Continue still does not tick the clock or the ledger. | yes |
| Regenerate | Revert restores `pre_climax_refractory` (peaks + window included) instead of `Refractory.none`; replies stamped before PR 3 (key missing) fall back to `none` — exactly today's semantics. The fresh swipe then re-applies from its own post-gen verdict. Regenerating peak 2 leaves peak 1's stamp and its window in place. | yes |
| Swipe alternate | Receipts (`_bodyJson` → `toSnapshot`) now carry soft + peaks; `refractoryReceipt`/`Refractory.read` restore them; the swipe-merge realism_state snapshot spreads `toSnapshot()` at both capture sites, so it round-trips unchanged. | yes |
| Delete (bot/user tail) | Pre-beat receipts put every body back as the beat found it — peaks included, because they ride the same receipt. | yes |
| Edit history | Same revert path as regen (`chat_service_regen_revert`). | yes |

Prompt paths: the soft rungs and the soft eval note are assembled in the same
leaves as the hard ones (`NsfwInjection.buildNsfwCooldownInjection`,
`RealismPromptFragments.arousalSection`) — full generate, Continue suffix,
impersonate, and overflow continuity all consume those same builders, and the
scalar validity contract (speaker loaded before assembly) is unchanged.
Pronoun-free contract on new rungs: whole-word, case-insensitive
`\b(she|her|hers|herself|he|him|his|himself)\b` — guard test covers every
ladder output (hard and soft), shipped strings pass, new rungs must.

## 2. Twin systems

| Touched | Twin updated |
|---------|--------------|
| `applyClimaxEffects` hard path | Soft branch in the SAME method — both transports (standalone + fused) route through `runClimaxPass`, parity by construction |
| `applyEvalArousalDelta` (hard: halve both, −10 floor) | Soft branch: halves POSITIVE deltas only, no floor change (decision 4); one apply path for multi-call + one-shot still |
| Injection ladder (hard rungs ship unchanged) | Parallel soft ladder (glow → tender → warm-again) + warm-again while any peak is counted; `_moveRefractory` gate widened to "nothing left to age" so peaks age after the window |
| `describeRefractory` (desktop chip words) | Web reads `refractoryLabel` from the server snapshot — copy lands once; TS mirror of the Recovery "resolves to" line updated |
| `RecoveryProfile.resolvedMode` (Dart) | `recoveryResolvesLine` Dart + `realismTypes.ts` mirror updated: the "until PR 3 ships" caveat becomes the real physics; vitest pin updated with the `approved-test-change` label on the PR |
| Sessions table (DB) | Snapshot (`realism_snapshot`), member map (`group_member_realism`), receipts, session hydrate/save/import, `.fpchat` export, web snapshot — every Persistence-section site carries soft + peaks; NULL/missing reads hard / no peaks |
| Desktop Porch Life blurb | Web `PorchLifeSettings.tsx` line names both kinds |
| Eval refractory note | Hard note loses the per-turn "just climaxed" lie; soft note is its own branch; both keep the −3…+5 gentle band |

## 3. Test law

New guards (each proven red before green, all append-only; the PR already
carries `approved-test-change` for the two existing-test edits — the vitest
`realismTypes.ts` string-pin and the `avatar_repository_test` schemaVersion
58→59 pin, the latter required by the additive v59 columns and re-guarded by
`refractory_legacy_load_test`):

1. `Refractory` ledger: peaks age with `elapse`, drop at 60; soft window
   expiry does NOT halve negative arousal (hard still does); `toSnapshot`/
   `read` round-trip soft+peaks; defaults omit keys (byte-stable receipts).
2. `NsfwService`: peak math exactly (100→90, 95→77, 90→66, cap ×3 keeps the
   ≥50 floor, climax below 50 costs nothing, no arousal zero, `newPeak: false`
   restarts without a peak); soft `applyEvalArousalDelta` halves gains only.
3. `AfterglowPass`: soft card lands `15 min (soft …)` window; `pre_climax_
   refractory` stamped once; Continue re-climax adds no peak; hard path
   untouched (existing pins stay green).
4. Injection: soft rungs exact copy; warm-again fires after the window while a
   peak is counted; whole-word pronoun guard over every ladder string.
5. Eval prompts: soft note branch; hard note no longer says "just climaxed";
   −3…+5 band survives both.
6. Regen revert: soft body restored with peaks+window; pre-PR-3 stamp → `none`.
7. Persistence: session row round-trip (DB columns v59), `.fpchat` round-trip,
   group member-map round-trip.
8. Integration (`integration_test/climax_refractory_test.dart`, the soft-gate test): multiorgasmic
   card climaxes twice in one scene, arousal stays ≥ 50, second peak bites
   harder, regen of peak 2 leaves peak 1 and its window, Continue on the peak-1
   reply adds no peak. `fake_backend` answers a given verdict (marker-driven,
   repeated while the marker is in the quoted exchange) — the fake does not
   judge personality, so this is mechanics-on-a-verdict, not a stub.

Red ledger (each break applied to live code, test observed failing, restored):
peak-cost multiplier (95→77 became 86); `newPeak` bypass (95→77 became 95);
pass resolving `soft: false` (window pin failed); `_moveRefractory` gate
revert (peaks 0 became 1); soft-expiry thaw (−20 became −10); soft ladder
bypass (glow copy missing); stamp-write removal (`pre_climax_refractory` pin
failed — the pre-beat receipt alone keeps regen peaks, so the stamp's own pin
is the true guard); hydrate key drop (soft row read back hard); import-seed
key drop (`.fpchat` soft body read back hard — caught only after a dedicated
round-trip test was appended to `clock_import_fork_test`; that test also
pinned the minutes-key gate: a head with soft/peaks but no
`refractory_minutes_remaining` reads as no-refractory by design, and real
capture always writes the key, even 0).

## 4. Web parity

- Sidebar chip: web renders `nsfw.refractoryLabel` verbatim — soft copy ("
  Tender for about 15 min · peak 2") appears on the phone with zero web logic
  change; type widened with optional `refractorySoft` for icon parity is NOT
  needed (the web stat line has no icon today — unchanged surface).
- Recovery "resolves to" copy mirror updated (`realismTypes.ts`).
- Porch Life blurb updated in both stacks.
- No new controls in PR 3 → no editor/RealismFormSection change.

## 5. Known consequences (accepted, documented)

- Clock off, the 15-min tenderness window lasts one reply of the speaker's
  (the quantization floor, Needs precedent); warm-again then holds the cuddle
  beat for the rest of the peak hour.
- Peak stamps age only when a beat moves the body (reply/clock advance) — same
  ledger as everything else, no reply counters.
- `peaks` capped at 3 by construction; the peak count the cost formula uses
  is the list length after pruning, so the ≥50 floor always holds.
- A soft card that later flips back to `hard` finishes its window as a hard
  lock (minutes left are minutes left); mode is read at climax time only.
