# Prompt budget degradation ladder — statement of work

Draft 3, 2026-10-23. Status at the end. Nothing here is built.

On a small context the app's own notes can crowd the conversation out. Every state-zone block is fixed-count and exempt from trimming by design, so when the context is 4K or 8K the Journal, the realism block, the objectives, the world block and the frame can take a large share of the window and the transcript falls to the overflow floor. Draft 1 proposed a ladder of blocks to shrink. The maintainer's review of it found, rung by rung, that each block is read by something besides the model, and shrinking it moves that something. This draft records those side effects, keeps the one mechanism that has none, and puts measurement before any further ladder.

## What the engine does today (from the code)

| Finding | Evidence |
| --- | --- |
| Every block but history and memories is counted once into `fixedCountText`, and the history budget is what is left after the reply reserve. Nothing in the zone yields. | `prompt_plan.dart` matrix; `chat_service_generation_plan.dart` `historyBudget = contextBudget - fixedTokens - generationReserve` |
| The Journal is the only block with its own cap (600 tokens). | `state_zone_frame.dart` doc |
| The frame alone is about 121 tokens of prefill a turn. | `state_zone_frame.dart` |
| The recap is the app's compaction: a model-written account of the chat up to a cursor, rewritten by the Journal pass. The pass runs every `journalInterval` user messages (default 10) or on a salient event kick. Nothing ties it to messages leaving the window, so between passes up to nine exchanges can fall out before the recap has read them. | `_maybeRunJournalPass` in `chat_service_turn_flow.dart`; `_summaryLastIndex` |
| The recap is dropped when every message is visible (it can only contradict the transcript then). A redundancy gate, not a budget one. | `recapIsRedundant` in `recap_injection.dart` |
| Zero or negative history budget keeps only the last user line and everything after it. | `_overflowContinuityHistory` |
| Continue counts the fixed text before its zone is stripped, so it budgets as if the stripped blocks were present and keeps the same history window as the send before it. | `_stripContinuePlanSections` runs after the count |
| The last send's per-row token counts are saved with the session (`context_budget_json`) and, since #609, at the tokenizer's count. | `chat_service_context_budget.dart` |

## Side effects found in the draft-1 rungs (2026-10-23)

| Proposed rung | What else reads the block | Why it was withdrawn |
| --- | --- | --- |
| World prose to one line | The scene itself | Maintainer: the setting is where the scene is, not colour the model can do without |
| Recap dropped | Compaction of the messages that fell out | On a small context it is the memory the ladder protects; it stays whenever messages were dropped |
| Secondary objectives hidden | The goal sync and the stuck-step count | A hidden goal cannot be pursued; its checks see no movement, the stuck count climbs, the sync can set it `dormant`. A goal would drift to dormancy because the context was small. Gain about 100 tokens |
| Realism to posture and time | The composer's eleven fragments | Four of them are not realism features: the promise ledger, ambitions, the plan line and Likes and Dislikes, which is ungated on purpose so it survives the engine being off. The composer's own doc records that a blanket cut "silently deleted all eleven fragments"; this rung would redo that bug by budget instead of by switch |
| Journal cap stepping down | RAG dedup | The injected cards are `journalCoverLines`, which drop retrieved windows the diary already covers. Fewer cards shown means fewer windows dropped, so retrieval refills part of the room the cap freed, and memories are budget-fitted, so they take it. Net gain unknown without measuring |
| Hysteresis stored with the session | Regen determinism | "Regen with the same inputs reproduces the same deltas." A sticky rung state is an input the regen does not share with the original turn unless it is stamped on the message like `story_clock_before`. More machinery than the rung |

What is left of the ladder with no side effect is the frame's own salience gate, which already exists. The ladder as a mechanism is withdrawn.

## 1. Compaction on approach (kept, narrowed)

The Journal pass gains a third trigger beside the interval and the event kick: the send's walk dropped messages whose index is at or past the recap cursor (`_summaryLastIndex`). The recap then covers what fell out, the way a compaction summary does, instead of waiting for the interval.

Narrowed after the trace: the trigger must rewrite the recap only, not run the full maintenance pass. The pass also reviews and cools Journal cards, and Growth deliberately keeps its own cursor because the Journal's "per-pass cooling is tuned to journalInterval" (`growth_service.dart`, `chat_service_wiring_memory.dart`). Firing the whole pass off-interval would change card cooling on every small-context chat. Whether a recap-only rewrite can be split out of `runMaintenancePass` is the first thing to establish; if it cannot, this item waits.

Continue never triggers compaction (it drops nothing new). The pass's own cooling and the recap cursor keep a 4K chat from compacting every turn.

## 2. Measure before any further ladder

The per-send rows are already saved with every session at the tokenizer's count. A read-only script over a library (`tools/`, like the notes rotator) reports, per chat and in aggregate: the zone's share of the context on each send, which rows carry it, how often the transcript fell below six exchange pairs, and at which context sizes. The maintainer's own library is the measurement, as it was for the state zone and the recap. If the zone's share is small the question is closed; if one row dominates, that row gets its own design with its readers traced first.

## 3. Continue

Continue keeps counting the zone it strips. That is the cache-friendly choice (same history window as the send before it) and it stays; the doc comment in `prompt_plan.dart` describes it as inherited from the legacy assembly and should say it is deliberate.

## Tests

For compaction: a send that drops past the recap cursor queues a recap rewrite and one that does not, does not; the rewrite touches no card and no Growth ring (the cooling guard); Continue never queues one. One journey on a real `ChatService` against the loopback backend with a 4K context and a 40-message chat, asserting the recap covers the lines that fell out. For the measurement script: a fixture library with known rows reports the known shares.

## Desktop and web

No UI change in either item.

## Status

- 2026-10-23: draft from the prompt-assembly audit. Awaiting the maintainer's word on the open questions.
- 2026-10-23, rulings: the floor is six pairs; the primary objective never leaves the prompt; the world block never yields. The maintainer asked whether the chat could compact near its limit the way an agent does; that is what the recap is, and the gap is its trigger.
- 2026-10-23, draft 3: the maintainer's review found a side effect behind each rung (table above), and the agent's own trace found two more (RAG dedup, regen determinism) and a third in compaction (card cooling). The ladder is withdrawn. Compaction on approach stays as a recap-only rewrite, pending a check that it can be split from the pass. A measurement over the library comes before any new shrink proposal.
