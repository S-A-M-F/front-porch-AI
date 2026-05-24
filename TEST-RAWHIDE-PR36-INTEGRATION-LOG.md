# Test Branch Integration Log: PR #36 + User's Needs Work

**Branch:** test-rawhide-pr36-plus-my-needs-work
**Purpose:** Reproducible integration of GitHub Rawhide + PR #36 + selective porting of user's high-value Needs/Realism work (pre-response pressure, per-character group state, Enjoys low hygiene), while strictly protecting PR #36 code except where explicitly authorized.

**Date started:** 2026-05-23
**Rule:** PR #36 changes take precedence. User's code is adapted around the PR. Explicit exception authorized for "Enjoys low hygiene" stronger version.

## Baseline at creation
- Commit: e7ecc1a (GitHub Rawhide 463e65b + full PR #36 merged)
- Plus limited successful ports from user's 13 commits that survived -X ours:
  - 54e3f8d (needs fulfillment verification post-response)
  - 7dac885 (arousal suppression + erotic buffers)
  - 3183595 (partial per-character Realism/Needs polish — only tiny net change survived)

## Step 1: Enjoys low hygiene override (explicitly authorized)
- PR author changed the feature to "mild scaling bonuses".
- User prefers the strong version (full personality inversion, rich "FILTHY CONTENTMENT" narrative text, bigger Fun/Comfort/arousal effects, proper hygieneInversionActive path).
- Source of strong version: commit 317b82d and related Needs work in user's history.
- On this test branch, the strong version was already active in chat_service.dart due to earlier successful ports (0233525 etc.).
- Result: The PR author's milder implementation was overridden by the user's preferred strong implementation in the simulation logic.
- File modified (authorized exception): lib/services/chat_service.dart (hygiene inversion section only).

## Commits currently on this branch (as of last update)
- e7ecc1a Merge PR #36 ...
- b67a2f8 (from PR)
- 463e65b (GitHub Rawhide)
- 7f7e1b2 (from PR)
- 317b82d (user's strong hygiene work)
- 54e3f8d (user)
- 7dac885 (user)
- 3183595 (user, partial)

## Next priorities to integrate (same rules)
1. Pre-response Needs pressure enhancements (richer OOC, better triggers)
2. Full per-character group-scoped Realism/Needs (complete the wiring beyond what survived)

All changes will be made only by extending safe files (primarily chat_service.dart) or by adapting user's code around PR-introduced structures.

This log will be updated at every significant step for 100% reproducibility on the real origin/Rawhide later.

## Step 2: Pre-response Needs pressure (priority #1) - explicitly authorized

- User confirmed: "yes in this case bring my code in"
- Reason: Conflicts for d614d58 were primarily against pre-existing Rawhide code, not new changes introduced by the PR #36 author in the pre-response pressure subsystem.
- Action: Replaced the current `_buildNeedsOOCGuidance()` function with the version from the user's commit d614d58 on the test branch.
- Result: Richer OOC guidance logic from d614d58 is now active (more specific handling for various needs, including adjustments in the hygiene case within this function).
- Note: This brought in the user's intended pre-response enhancements while respecting that the PR author did not heavily rewrite this particular area.
- Commit on test branch: 0c86dc6 "test: bring in richer pre-response Needs pressure from d614d58"
- File changed: lib/services/chat_service.dart (only the OOC guidance function)

This step is fully documented for exact replay on the real Rawhide branch later.

## Current state of the three priorities on test branch (as of this update)

1. Pre-response Needs pressure → User's richer version from d614d58 now active
2. Per-character group-scoped Realism/Needs → Partial (only small net change from 3183595 survived earlier)
3. Enjoys low hygiene → Strong version active (from previous ports + 317b82d influence)

Next: Continue with deeper analysis/adaptation for full per-character group Needs if desired.

## RULE CLARIFICATION (2026-05-23) - Direct from user

"Any code directly changed by the PR author is not to be touched (except for the ones I told you to override already).

If it touches existing code that was not edited by the PR author, that is safe to modify/change.

The only sacred cow is the code written by SAMF.
My existing code can be changed to make my commits work."

### Interpretation we are now following:
- **Untouchable (sacred)**: Any lines/hunks/sections that the PR author (S-A-M-F) directly modified or added in PR #36.
  - Exception: The "Enjoys low hygiene" stronger version override has been explicitly authorized.
- **Safe to edit/adapt**: Any code that existed in the baseline before the PR landed (pre-PR Rawhide code), even if it is in the same file as PR changes.
- Goal: Make the user's desired functionality (pre-response pressure, per-character group Needs, Enjoys low hygiene) work by modifying only non-PR-author code where possible.

This rule now governs all future work on this test branch.


## Major Step: Forcing per-character group Realism/Needs work (explicit user request)

User said: "force my version to merge or whatever that is called" and later "ok my version wins" for the per-character group system.

Action taken:
- Cherry-picked 81deb66 with -X theirs (user's per-character group-scoped prompts win on conflicts)
- Cherry-picked 0233525 with -X theirs (the big "complete per-character Realism engine + Needs polish" wins on conflicts)

Result:
- The user's stronger, more complete per-character group Realism/Needs implementation is now active on the test branch.
- This overrides the PR author's shallower version in the group per-character areas (as explicitly authorized by the user).

Files modified as part of forcing these commits: chat_service.dart, group_settings_dialog, chat_page, edit_character_page, memory_service, database (these were areas where the PR author had made changes).

This is recorded as an authorized exception to the normal "PR code is sacred" rule, similar to the Enjoys low hygiene override.

Current high-value user's work now active on test branch (approximate):
- Pre-response pressure (d614d58)
- Arousal/erotic buffers (b92d332)
- Post-response verification (3849c7a)
- Per-character group prompts + full Realism/Needs polish (81deb66 + 0233525)
- Strong Enjoys low hygiene behavior

Next: Address any other remaining commits the user wants (cfdfad2 hygiene toggle if not fully satisfied, 5e50272, docs, etc.) using the same forced approach where requested.


## Step: Weekday narrative stability (5e50272)

- User requested as "easy win".
- Cherry-picked 5e50272 with -X theirs.
- Result: Landed cleanly with only minor net change (1 insertion, 3 deletions).
- File touched: lib/services/chat_service.dart + database files (small adjustments).
- This was a low-conflict commit and did not require overriding any significant PR-author code.


## Decision: Keep user's version of Rawhide → AUR automation

User explicitly requested: "keep my version of this as well" regarding the automatic AUR beta package updates from Rawhide nightlies.

Current state on test branch:
- The publish-aur-beta job that updates the AUR from Rawhide nightlies is present in nightly.yml.
- This job was removed by the pure PR #36 changes.
- Because we have applied the user's later commits on the test branch, the functionality is currently preserved.

Action: We will ensure this automation remains active. When replaying on the real origin/Rawhide, we must prevent the PR from deleting this job (or restore it from the user's commits).

This is recorded as another authorized exception / preference to keep the user's CI automation working.


## Explicit Boundary - Pseudo-Remote Backend (2026-05-23)

User statement: "I just want to keep the pseudo remote backend un modified since that is what the PR author really wanted to work without making any changes."

Rule going forward:
- The entire Pseudo-Remote backend feature (including all UI, selectors, wiring, start/stop/autostart logic, and supporting changes) must remain exactly as delivered by the PR author.
- No modifications are allowed to any code that implements or supports the Pseudo-Remote option, even if it lives in files we are otherwise allowed to edit.
- This takes priority over bringing in any of the user's other work if there is a conflict.

This is now a hard boundary for all remaining work on the test branch and for the final replay on real origin/Rawhide.


## Step: cfdfad2 - Enjoys low hygiene UI toggle (explicit user request to keep his version)

- User confirmed: "keep mine" for the hygiene toggle.
- Cherry-picked cfdfad2 with -X theirs.
- Result: Landed successfully (net 14 insertions, 195 deletions — mostly because baseline had extra code from PR in the UI files).
- Files modified: character_card.dart, chat_service.dart, character_creator_page, chat_page, edit_character_page, create_character_page, realism_form_section.
- Note: This overrides some PR-author changes in the character UI files (as explicitly authorized by the user for this feature).
- Pseudo-Remote verification after this change: PASSED (no modifications to any Pseudo-Remote files).

This is recorded as another authorized exception.


## Step: 7b62c84 - Story double-to-int coercion fix + tests (backport of PR #31)

- User requested to bring this in to avoid regression vs main.
- This commit originated from @MisterLotto's PR #31 on dev (backported by the user).
- Cherry-picked with -X theirs.
- Adds safe handling for LLMs returning doubles instead of ints in Story models, plus first batch of story_project tests.
- Also removes accidental junk (chat_service.dart.bak2 and broken submodule).
- Does not touch Pseudo-Remote in any way.

Pseudo-Remote verification: PASSED (still 100% intact).

