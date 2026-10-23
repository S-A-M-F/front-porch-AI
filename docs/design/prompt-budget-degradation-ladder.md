# Prompt budget degradation ladder — statement of work

Draft 1, 2026-10-23. Status at the end. Nothing here is built.

On a small context the app's own notes can crowd the conversation out. Every state-zone block is fixed-count and exempt from trimming by design, so when the context is 4K or 8K the Journal, the realism block, the world prose, the objectives and the frame can take a quarter of the window and the transcript falls to the overflow floor. This scopes a ladder: the notes give ground, in a fixed order, before the chat does.

## What the engine does today (from the code)

| Finding | Evidence |
| --- | --- |
| Every block but history and memories is counted once into `fixedCountText`, and the history budget is what is left after the reply reserve. Nothing in the zone yields. | `prompt_plan.dart` matrix; `chat_service_generation_plan.dart` `historyBudget = contextBudget - fixedTokens - generationReserve` |
| The Journal is the only block with its own cap (600 tokens). The realism block, the world block, the objectives and the recap have none beyond their own salience gates. | `state_zone_frame.dart` doc; `realism_state_injection.dart` |
| The frame alone is about 121 tokens of prefill a turn. | `state_zone_frame.dart` |
| The recap already has one yield rule: it is dropped when every message is visible, because then it can only contradict the transcript. That is a redundancy gate, not a budget one. | `recapIsRedundant` in `chat_service_generation_plan.dart` |
| Zero or negative history budget keeps only the last user line and everything after it. There is no floor above that. | `_overflowContinuityHistory` |
| Continue counts the fixed text before its zone is stripped, so it budgets as if the stripped blocks were present. This keeps its history window identical to the send before it, which is what a prefix cache wants. | `_stripContinuePlanSections` runs after the count |
| The sidebar's "Chat History pruning" surprise (#550) was the estimate, fixed in #563; the real send trims. | issue #550 |

## What changes and what stays

The ladder is a fixed order of concessions, taken one rung at a time until the transcript has a floor's worth of room. Concessions are prompt-only: nothing a block records is lost, and nothing a block decides changes. The order, the floor and the caps are constants the maintainer sets; there is no per-chat setting and no new screen.

Stays: every gate and switch as it is; the recap redundancy rule; Continue's budgeting (see below); the state frame's wording; the walk, the chunk rounding and the overflow floor; the Context Viewer's rows and Total.

## 1. The floor

A floor is the smallest transcript worth sending: the latest beat plus N earlier turns (default N = 6 user-and-reply pairs, in tokens the walk's own count). The ladder runs only when the fixed count leaves less than the floor. On a 16K or 32K context it never runs; on 8K it runs on long Journals and busy scenes; on 4K it runs most turns.

## 2. The rungs

Taken in this order, each only as far as needed, re-counting after each:

| Rung | Concession | Why this order |
| --- | --- | --- |
| 1 | World prose shrinks to its one-line place and weather facts | Setting colour is the least load-bearing note; the facts stay |
| 2 | Journal cap steps down 600 → 400 → 250 tokens (hot cards first, as the cap already orders them) | The Journal is the biggest block and already ranks its own cards |
| 3 | The recap is dropped | A compressed, older account of the same events; the transcript is the record |
| 4 | Secondary objectives leave the prompt (the primary stays) | Side wants are the first thing a stressed scene forgets |
| 5 | Realism keeps only the posture line and the time line | Feelings in words are the "truer guide" and go last |
| 6 | The frame is dropped with the zone when nothing is left in it | The existing salience gate, reached by the ladder |

The Author's Note, the card's post-history, the lore buckets, the speaker card and the catastrophe never yield: they are the user's or the card's instructions, or a one-shot event that must land.

## 3. Continue

Continue keeps counting the zone it strips. That is the cache-friendly choice (same history window as the send before it) and it stays; the doc comment in `prompt_plan.dart` describes it as inherited from the legacy assembly and should say it is deliberate. The ladder runs on Continue exactly as it ran on the send it extends, from the same inputs, so the window is the same.

## 4. Where it shows

- The Context Viewer's budget rows already report the shrunken blocks; a one-line note in the viewer says which rungs ran ("Notes trimmed to fit: world prose, Journal to 400"), desktop and web, next to the existing dropped-messages note.
- No sidebar change. The Journal, objectives and world panels keep showing everything the engine holds; the ladder hides, it never erases.

## Open questions for the maintainer

1. The floor: six pairs, or a token share (a quarter of the context)?
2. Rung 2's steps, or a single cut to 250?
3. Should rung 4 hide the primary objective too at 4K, or is the primary the one note that always goes out?
4. Does a Chaos or Porch Night turn skip the ladder (their one-shots must land) or ride it?

## Tests

Guards proven red then green, appended to `prompt_plan_test.dart` and the context budget tests: a 4K context with a 600-token Journal and a long realism block leaves the floor's worth of transcript; the rungs run in order and stop at the first that suffices; a 32K context runs no rung; Continue runs the same rungs as the send before it and keeps the same history window; the viewer's note names the rungs that ran. One journey on a real `ChatService` against the loopback backend with a 4K context and a 40-message chat, asserting the sent transcript carries the last six pairs.

## Desktop and web

One note in the Context Budget on both surfaces. No setting, so no parity-manifest entry.

## Status

- 2026-10-23: draft from the prompt-assembly audit. Awaiting the maintainer's word on the open questions.
