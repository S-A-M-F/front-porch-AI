# Afterglow PR 5 — mutual afterglow (`user_climaxed`): path-complete fill

Design source: `docs/design/afterglow-recovery-overhaul.md` §PR 5. Rides
PR 1–4 on branch `feat/afterglow-pr2-recovery-profile` (PR #555), stacked as
its own commit.

## The physics

The climax judge already distinguishes "only the partner/user climaxing"
from the character's own release — PR 1's rubric says it — and throws the
fact away. PR 5 recovers it on the SAME call (decision 8: zero extra LLM
calls): a new `user_climaxed` boolean rides `kClimaxFields`, required
alongside `is_climax`/`refractory_turns` on the standalone climax tool and
in the fused reply-facts tool when `askClimax`. Lenient parser (bool, or
the strings "true"/"yes"); a missing key or junk reads false — the mutual
beat is opt-in per reply, never assumed.

## 1. Generation matrix

| Path | What happens | Verified by |
| --- | --- | --- |
| Normal send (1:1) | Judge answers → `meta['user_climaxed'] = true` stamped beside `climax_triggered`/`pre_climax_arousal` ONLY when true (absence is the default). The receipt BODY is unchanged — the mutual beat is opening-turn-only, nothing about the ledger moved | independence stamp guard |
| Continue | First-reading guard holds for the receipt BODY (arousal, pre-climax refractory, peak counting). The mutual flag alone merges MONOTONICALLY (review M1): a continuation that finally narrates both raises the stamp — the lock re-arms on that branch, so the opening turn must match the shared verdict — but a solo continuation never un-stamps it | independence merge guards (raise + no-un-stamp) |
| Regen | New call, new timeline: the re-roll re-asks and re-stamps — an old mutual stamp cannot outlive its swipe | swipe/restore shows that timeline's own meta (unchanged surface) |
| Group | Mutual opening resolves against the SPEAKER: `isOpeningAfterglowTurn` AND the latest assistant reply that carries `climax_triggered` AND resolves to the current speaker carries `user_climaxed`. A roster-mate's mutual beat is not this body's warmth | ladder guard test (non-speaker stamp must not leak) |
| Fused (reply-facts) | Same slice, same parsers: `parseRefractory` + `parseUserClimaxed` read the one fused answer | fusion parity + schema-required tests |

## 2. Prompt/Realism matrix

| Site | Change |
| --- | --- |
| Schema | `user_climaxed` in `kClimaxFields` ("true only if {{user}} also climaxed in this reply"); required lists: standalone `['is_climax','refractory_turns','user_climaxed']`, fused `askClimax ⇒ same three`. Registry inherits via the spread — an unregistered/undefined key is dropped by the whitelist |
| File size | `realism_tool_schemas.dart` (495) crosses the bar with the field: the Afterglow block (climax + reply-facts fields and tools) moves to `realism_tools/afterglow_tool_schemas.dart` FIRST, still registered in `realismToolFieldsByTool` (main file imports it back for the registry; the new file imports `kPocketsFields` — no initializer cycle) |
| Rubric | one appended ask: judge `user_climaxed` independently; "close for both" without narrated release is false; unsure ⇒ false |
| Text floors | standalone key list and fused `keys` list both name `"user_climaxed"` when climax is asked |
| Parser | `parseUserClimaxed` — same lenient style as `parseRefractory` |
| Ladder | one mutual opening variant per mode, replacing the "If {{user}} starts something…" clause (hard) / the closing beat (soft) ONLY when the beat's stamp says mutual. Pronoun-free (whole-word guard sweep extended) |
| Eval note | refractory note may append one shared-wind-down sentence on the opening turn only (`mutualOpening` param, wired through prompt_builder + eval_calls + one_shot like `warmthTailMinutes`) |
| Chip | none — a stamp, not a state |

## 3. Persistence

Message metadata only, beside the existing climax stamps. No schema bump,
no session columns, no member-map keys, no receipt change. `.fpchat`
carries message metadata as-is (generic passthrough). Pre-PR-5 replies
have no stamp → read non-mutual forever.

## 4. Test law (append-only, each red→green)

1. Schema: field defined; required on the standalone tool; required in the
   fused list when `askClimax`, absent when off; registry whitelist carries
   it. Existing required-pins use `contains`/`containsAll` — confirm they
   pass UNCHANGED before claiming no label scope creep.
2. Parser: true / "true" / "yes" / quoted forms read true; false, junk,
   and missing read false.
3. Stamp: harness judge answering `user_climaxed:true` lands the stamp;
   false/absent stamps nothing else.
4. Ladder: mutual hard/soft copy appears ONLY with the stamp closure true;
   default closure keeps today's copy verbatim; the non-speaker group case
   stays silent; pronoun sweep lists the mutual rungs.
5. Note: opening+mutual carries the shared sentence; absent otherwise.
6. Rubric + both text floors name the key (fusion parity keeps pinning the
   shared rubric).
7. Builder chain: `emotionalEvalPrompt(..., mutualOpening: true)` carries the
   sentence — a param silently dropped mid-chain fails something.

Red proofs (each patch → targeted guard fails → restored): fused required
list, registry whitelist, stamp line, parser `yes`-leniency, ladder gate
(default copy returns), builder chain. 6/6 red, then green.

## 4b. Hostile-review ledger

Reviewer: general subagent on `ae901b8f5`, ten-law attack. No BLOCKING.
Findings and disposition:

- **M1 (MAJOR, fixed, red-proven)** — Continue's re-verdict could declare
  mutual while the stamp stayed in the skipped first-reading branch, yet the
  hard path re-arms the lock there → the opening turn spoke the solitary
  rung for a beat just declared shared. Fix: monotonic merge of
  `user_climaxed` in the `newPeak = false` branch (raise only, never
  un-stamp; receipt body stays first-reading-owned). Guards: raise + no-
  un-stamp; red by removing the merge.
- **M2 (MINOR, fixed, red-proven)** — `hasMatch` anywhere-in-raw let a real
  `false` flip via a later quoted literal (fused `posture` prose) and let
  "yesterday"/"truest" read true. Fix: `firstMatch` on the whole word, then
  exact `true`/`yes` — same shape as `parseRefractory`.
- **M3 (MINOR, fixed, pinned)** — `{{user}}` in the rubric and the tool
  description reaches the JUDGE literally (judge lanes skip MacroResolver).
  Both reworded to plain "the user"; guards now pin no `{{user}}` token in
  rubric or description.
- **M4 (MINOR, fixed, red-proven)** — the fused TEXT floor was unpinned:
  deleting the keys entry kept every test green (the rubric alone satisfied
  a bare `contains`). Guard now targets the flat-JSON keys-list join.
- **M5 (disclosed)** — `dart format` on the touched schema test reflowed
  three existing lines (helper expressions + one `reason:` wrap), pure
  formatter, semantics identical. `approved-test-change` label is on the
  PR; recorded here so the label scope question is decided, not assumed.
- **M6 (MINOR, commented)** — tools-lane bool coercion accepts only
  "true"/"false" strings, so a tool arg `"yes"` falls through solo while
  text mode would read mutual. Fail-solo direction; documented on
  `parseUserClimaxed` rather than widening the shared coercion.
- **M7 (MINOR, fixed)** — the mutual scan in 1:1 took the freshest stamp
  without the guest-authorship check; a scene-guest chime could decorate
  the host. Scan now skips `_isGuestAuthoredMessage` replies (matching the
  regen path).
- Checked CLEAN under attack: 500-bar (main 430 / leaf 131), cyclic import
  has no initializer cycle, registry + barrels reachable from every
  consumer, helper bytes identical, persistence wholesale on every message
  path (fpchat, swipes, regen, rescore), opening-flag tick order, group
  speaker resolution fails solo not steals, fused is_climax-false ⇒ no
  stamp at all, ladder pronoun sweep, web parity.

## 5. Web parity

No web surface: no chip, no setting, no label. `refractoryLabel` unchanged.
The judge prompt is desktop/server-side; `web_ui` has no prompt copy to
mirror (the recovery-block "resolves to" text does not mention mutuality).
Recorded here instead of a diff.

## 6. Hygiene budget

Measured after the work: `realism_tool_schemas.dart` 495 → 430 via the
extraction; the new leaf is 131 lines. Every other touched file under 420
with room. `wc -l` re-checked against the 500 gate; format+analyze clean;
`test/services/chat/` green.

## 7. Consequences accepted

- Old models that ignore the new required field read non-mutual forever —
  the same graceful floor as every added judge field.
- `user_climaxed` is a VERDICT, never a state: it is stamped on one reply,
  read for one opening turn, and a regen re-rolls it with the timeline.
- A user-only climax still answers `is_climax:false` (PR 1 rubric) and thus
  starts no refractory — `user_climaxed` only rides an existing true, so
  solo-user beats stay silent by construction.
