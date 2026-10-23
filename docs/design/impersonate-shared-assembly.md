# Impersonate on the shared assembly — statement of work

Draft 1, 2026-10-23. Status at the end. Nothing here is built.

Impersonate builds its own prompt. `impersonateUser` in `chat_service_impersonate.dart` re-does about 200 lines of what `_assembleGenerationBlocks` and `_buildGenerationPlan` do for a reply: base prompt, lore buckets, persona, growth, user persona, scenario, macros, its own `PromptPlan`, its own budget walk, its own stop list and stream loop. `GenerationMode.impersonate` already exists on the turn carrier and the blocks, request and stream stages already branch on it, but nothing drives a turn through them in that mode. Two assemblies for one prompt drift; this scopes putting impersonate on the shared one.

## What the two paths do today

| Piece | Reply path | Impersonate | Drift |
| --- | --- | --- | --- |
| Base prompt, additions, group scene rules | `_assembleGenerationBlocks` | copied | none today |
| Identity | card first | `[IMPERSONATE…]` first, then the card frame | by design |
| Lore buckets, depth lore | shared injector | shared injector | none |
| Persona, growth, user persona | shared desks | copied | none today |
| Scenario | shared; a Scene Guest's is blanked | copied; never blanked | yes |
| Scenario fade | `wrapForChat` | `wrapScenario` with the same count | none today |
| Examples | card examples | omitted (few-shot the character's voice) | by design |
| Post-history | card + global | global only | by design |
| Author's Note | strength wrapper + per-character + entrance + director + guest notes | strength wrapper only | partly by design (no guest), partly drift (no per-character note in a group) |
| Macros | every block (AN since this PR) | every block (AN since this PR) | none |
| State zone (recap, Journal, objectives, world, realism, catastrophe) | registered | never registered | by design for feelings; a gap for facts |
| Time of day, weather, place | inside the realism block | absent | yes: the user's line is written without the hour or the weather |
| Memories (RAG) | retrieved | absent | by design? never decided |
| Budget walk | shared, `splitLatestTurn` | shared, no split | the latest beat is not pulled after the zone (no zone, so moot) |
| Stop list | `buildPrioritizedStops(impersonating:)` | same builder | none |
| Stream | shared stage with `isUserTarget` | own loop with think filtering and a stop trim | duplicated |
| Context Viewer | recorded | not recorded | the user cannot see what an impersonate sent |

## What changes and what stays

Impersonate becomes a `_GenTurn` with `mode: GenerationMode.impersonate` run through the same four stages. The stages gain the mode-aware choices the table marks "by design", as explicit branches with a comment each, instead of a second file. The identity block, the card frame, the director frames, the prefix rule and the suffix stay exactly as they are, in `impersonate_prompt.dart`.

Stays: what the user sees (the composer fills with the user's line, Director Mode writes a stage direction), the stop list, think filtering, output sanitising, the `[Director:` closer, the "no card examples, no card post-history" rule, and no feelings in the prompt.

## 1. Mode branches in the shared stages

- **Blocks.** Examples and card post-history are blank in impersonate mode. The per-character group note rides the Author's Note seat as it does for a reply (today it does not). Guest and host-with-guests notes stay out. A Scene Guest's scenario is blanked as on the reply path.
- **Plan.** The state zone registers only its scene-facts members: the time line, the weather line and the place line, framed as facts, no feelings, no objectives, no Journal, no recap. The frame is not used; a one-line fact seat needs no attribution. Memories stay out (open question 2).
- **Request.** The Context Viewer records the impersonate send like a reply, so the prompt record shows it. The stop list is unchanged.
- **Stream.** The shared stage already keys on `isUserTarget`; the impersonate loop's stop trim and think filter move into it or are shown to be already there.

## 2. What is deleted

The hand-copied assembly in `chat_service_impersonate.dart`: about 200 lines, leaving speaker selection, the `onToken` plumbing and the director closer. `impersonate_prompt.dart` is untouched.

## Open questions for the maintainer

1. Time, weather and place in the user's line: in, as facts? (Recommended: yes. The user writing "good morning" at midnight is the visible bug.)
2. Retrieved memories: should the user's line see what the character remembers? (Recommended: no. They are the character's memories.)
3. The per-character group Author's Note: should a note written for a character shape the user's line to them? (Recommended: yes, it is the author's steer for that pairing.)

## Tests

The existing guards stay and must stay green unchanged: `impersonate_prefix_test.dart`, `impersonate_thinking_timer_test.dart`, the impersonate assertions in `global_prompt_additions_test.dart`, `author_note_macro_test.dart`, `prompt_source_picker_test.dart`, and the director-mode impersonate cases. New guards proven red then green: an impersonate with a Scene Guest in the scene sends no guest scenario; a group impersonate carries the per-character note; the sent prompt has the time line and no Journal, objectives or recap; the Context Viewer records the impersonate; and a byte-comparison of the old and new assembly on one fixed chat (recorded before the deletion) differs only in the lines this SOW adds.

## Desktop and web

No UI change. The web composer's Impersonate button calls the same service method. The Context Viewer on both surfaces gains the impersonate record for free once it is recorded.

## Status

- 2026-10-23: draft from the prompt-assembly audit. Awaiting the maintainer's word on the open questions.
