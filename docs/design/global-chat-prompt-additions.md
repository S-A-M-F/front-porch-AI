# Global chat prompt additions

Settings → Generation → Global prompt additions provides two optional fields:
Additional system prompt and Additional post-history instructions. They are
shared across all characters, groups and chat models until changed or cleared.
There is no automatic model selection or model-specific preset in this feature.

The existing Model Instructions editor under desktop General (System prompt on
web) supplies the fallback for one-to-one chats without a character system
prompt. Groups select their own prompt or a group default. The new system
addition follows that selection and applies even when the fallback is unused.
Web Settings presents backend and Generation sections on one scrolling page;
desktop Settings separates them into tabs.

Desktop saves edits automatically. Web uses the existing Save settings flow and
unsaved-changes protection. Both fields default to empty and use the existing
channel-aware settings persistence. No character card or database schema changes.

## Composition

The system addition follows the effective system prompt after existing group,
character and fallback selection. It does not replace any of those prompts.
The post-history addition follows the existing card post-history block; group
speaker-card instructions keep their existing position. Blank additions preserve
the existing prompt bytes. Nonblank additions receive a paragraph separator;
post-history retains its section boundary newline.

Composition happens before the existing macro-resolution and PromptPlan budget
passes. Macros such as {{char}} and {{user}} use the current speaker and persona.
The context budget includes both additions. The live estimate includes the
additions without resolving state-mutating macros, as with other estimated text;
the actual sent-prompt view contains their resolved forms.

Impersonation applies the additions within its own prompt plan and keeps its
user-identity frame. Auxiliary Realism/Needs evaluators, Journal/Growth, summaries,
character creation and other tool prompts do not acquire the additions.

## Path-complete checklist

| Turn event | Behavior |
| --- | --- |
| Normal send, 1:1 | Append once after effective base selection; preserve card instructions. |
| Normal send, group | Append once for the selected speaker; keep group/member overrides. |
| Continue | Same additions and macro context; no new clock tick or state-zone injection. |
| Regenerate | Read current global additions; existing rewind/receipts remain unchanged. |
| Swipe | A newly generated alternate uses current additions; existing alternates stay unchanged. |
| Delete | No new state or receipts to rewind. |
| Edit history | Existing rewrite behavior unchanged; later generation uses current additions. |

| Prompt path | Coverage |
| --- | --- |
| Full generation | Shared block assembly → macro resolution → PromptPlan. |
| Continue suffix/partial | Same assembly; existing think stripping and suffix stay unchanged. |
| Overflow/context trimming | Additions enter fixed-token budgeting before history trimming. |
| Impersonate | Same global fields, dedicated identity frame retained. |

Twins checked: 1:1/group/scene-guest reply assembly, Continue/regenerate,
impersonation, live Context Budget and actual sent prompt, desktop/web settings.
No Realism/Needs/Journal/Growth/Pockets state application or storage changes.

## Verification and poke script

The feature regression exercises real ChatService request assembly with the
existing test transport, not a helper-shaped reconstruction. It checks custom
card and group bases, both speakers, resolved macros, exactly-once additions,
Continue/regeneration/impersonation, clearing, saved settings, and the actual
Generation tab. Removing the production system-addition call must make it fail.
The browser journey uses the real settings form and server to save/reload/clear.

1. Enter short additions in Settings → Generation and return to an existing chat.
2. Send, regenerate and Continue; inspect the sent system and post-history text.
3. Repeat with a group using its own system prompt and switch speakers.
4. Restart/reload settings, confirm the fields persist, then clear them and verify
   the next request contains only its original card/group instructions.
5. Repeat saving and clearing from phone web. Use synthetic data for review.
