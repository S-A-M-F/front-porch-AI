# Prompt budget degradation ladder — statement of work

Draft 2, 2026-10-23. Status at the end. Nothing here is built.

On a small context the app's own notes can crowd the conversation out. Every state-zone block is fixed-count and exempt from trimming by design, so when the context is 4K or 8K the Journal, the realism block, the world prose, the objectives and the frame can take a quarter of the window and the transcript falls to the overflow floor. This scopes two things: a ladder, where the notes give ground in a fixed order before the chat does, and compaction on approach, where the recap is rewritten when the chat is about to lose messages it has not yet read, instead of on a fixed interval.

## What the engine does today (from the code)

| Finding | Evidence |
| --- | --- |
| Every block but history and memories is counted once into `fixedCountText`, and the history budget is what is left after the reply reserve. Nothing in the zone yields. | `prompt_plan.dart` matrix; `chat_service_generation_plan.dart` `historyBudget = contextBudget - fixedTokens - generationReserve` |
| The Journal is the only block with its own cap (600 tokens). The realism block, the world block, the objectives and the recap have none beyond their own salience gates. | `state_zone_frame.dart` doc; `realism_state_injection.dart` |
| The frame alone is about 121 tokens of prefill a turn. | `state_zone_frame.dart` |
| The recap is the app's compaction: a model-written account of the chat up to a cursor, rewritten by the Journal pass. The pass runs every `journalInterval` user messages (default 10) or on a salient event kick. Nothing ties it to messages leaving the window, so between passes up to nine exchanges can fall out before the recap has read them. | `_maybeRunJournalPass` in `chat_service_turn_flow.dart`; `_summaryLastIndex` |
| The recap already has one yield rule: it is dropped when every message is visible, because then it can only contradict the transcript. That is a redundancy gate, not a budget one. | `recapIsRedundant` in `recap_injection.dart` |
| Zero or negative history budget keeps only the last user line and everything after it. There is no floor above that. | `_overflowContinuityHistory` |
| Continue counts the fixed text before its zone is stripped, so it budgets as if the stripped blocks were present. This keeps its history window identical to the send before it, which is what a prefix cache wants. | `_stripContinuePlanSections` runs after the count |
| The sidebar's "Chat History pruning" surprise (#550) was the estimate, fixed in #563; the real send trims. | issue #550 |

## What changes and what stays

Two mechanisms, one PR each.

**The ladder** is a fixed order of concessions, taken one rung at a time until the transcript has a floor's worth of room. Concessions are prompt-only: nothing a block records is lost, and nothing a block decides changes. The order, the floor and the caps are constants; there is no per-chat setting and no new screen.

**Compaction on approach** is a new reason for the Journal pass to run: a send that drops messages the recap has not read yet. The recap then covers what fell out, the way a compaction summary does, instead of waiting for the interval to come round.

Stays: every gate and switch as it is; the recap redundancy rule; Continue's budgeting (see below); the state frame's wording; the walk, the chunk rounding and the overflow floor; the Context Viewer's rows and Total; the Journal pass itself (one model call, same prompt, same cooling).

## 1. The floor

Ruled 2026-10-23: the latest beat plus six user-and-reply pairs, in the walk's own token count. The ladder runs only when the fixed count leaves less than that. On a 16K or 32K context it never runs; on 8K it runs on long Journals and busy scenes; on 4K it runs most turns. A share of the context was considered and set aside: pairs are what a person can check in the Context Viewer.

## 2. The rungs

Taken in this order, each only as far as needed, re-counting after each:

| Rung | Concession | Why this order |
| --- | --- | --- |
| 1 | World prose shrinks to its one-line place and weather facts | Setting colour is the least load-bearing note; the facts stay |
| 2 | Journal cap steps down 600 → 400 → 250 tokens (hot cards first, as the cap already orders them) | The Journal is the biggest block and already ranks its own cards |
| 3 | Secondary objectives leave the prompt; the primary never does (ruled 2026-10-23) | Side wants are the first thing a stressed scene forgets; the main goal is the one note that always goes out |
| 4 | Realism keeps only the posture line and the time line | Feelings in words are the "truer guide" and go last |
| 5 | The frame is dropped with the zone when nothing is left in it | The existing salience gate, reached by the ladder |

The recap is not a rung. On a small context it is the compaction of what fell out, so dropping it would lose the memory the ladder is trying to protect; it stays whenever messages were dropped (the existing gate) and keeps its own length. The Author's Note, the card's post-history, the lore buckets, the speaker card and the catastrophe never yield: they are the user's or the card's instructions, or a one-shot event that must land.

**Hysteresis.** A rung taken in a chat stays taken until the fixed count drops by a margin (a rung's worth), so a chat on the edge does not flap a block in and out of the prompt turn by turn. The rungs in force are kept with the session, like the sticky trim anchor.

## 3. Compaction on approach

The Journal pass gains a third trigger beside the interval and the event kick: the send's walk dropped messages whose index is at or past the recap cursor (`_summaryLastIndex`). The pass runs after the reply as today, never competing with the main call, and rewrites the recap over the window it has not read, so the next send carries them in compressed form. The interval still runs on long chats that never drop; the event kick is unchanged. The pass's own cooling keeps a 4K chat that drops every turn from compacting every turn: at most one compaction per interval's worth of drops, with the recap cursor as the record of what has been read.

## 4. Continue

Continue keeps counting the zone it strips. That is the cache-friendly choice (same history window as the send before it) and it stays; the doc comment in `prompt_plan.dart` describes it as inherited from the legacy assembly and should say it is deliberate. The ladder runs on Continue from the same inputs as the send it extends, so the window and the rungs are the same. Continue never triggers compaction (it drops nothing new).

## 5. Where it shows

- The Context Viewer's budget rows already report the shrunken blocks; a one-line note in the viewer says which rungs ran ("Notes trimmed to fit: world prose, Journal to 400"), desktop and web, next to the existing dropped-messages note.
- No sidebar change. The Journal, objectives and world panels keep showing everything the engine holds; the ladder hides, it never erases.

## Open questions for the maintainer

1. Rung 2's steps, or a single cut to 250?
2. Does a Chaos or Porch Night turn skip the ladder (their one-shots must land) or ride it? (Recommended: skip; the one-shots are not zone members and are never trimmed anyway, so the question is only whether the ladder may run on the same turn. Letting it run is simpler.)

## Tests

Guards proven red then green, appended to `prompt_plan_test.dart`, the recap tests and the context budget tests: a 4K context with a 600-token Journal and a long realism block leaves the floor's worth of transcript; the rungs run in order and stop at the first that suffices; the primary objective is in the prompt at every rung; the recap stays when messages were dropped; a 32K context runs no rung; a rung taken stays taken until the count drops by the margin; Continue runs the same rungs as the send before it and keeps the same history window; a send that drops past the recap cursor queues a Journal pass and one that does not, does not; the viewer's note names the rungs that ran. One journey on a real `ChatService` against the loopback backend with a 4K context and a 40-message chat, asserting the sent transcript carries the last six pairs and the recap covers the lines that fell out.

## Desktop and web

One note in the Context Budget on both surfaces. No setting, so no parity-manifest entry.

## Status

- 2026-10-23: draft from the prompt-assembly audit. Awaiting the maintainer's word on the open questions.
- 2026-10-23, rulings: the floor is six pairs; the primary objective never leaves the prompt. The maintainer asked whether the chat could compact the way an agent compacts near its context limit; that is what the recap is, and the gap is its trigger, so compaction on approach (part 3) is in and the recap is no longer a rung. Two PRs: the ladder, then compaction.
