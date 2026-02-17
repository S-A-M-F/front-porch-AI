# Plan: Sync Brain Artifacts to Repository

The goal is to store "brain" artifacts (tasks, plans, walkthroughs) inside the project repository so they are synchronized across different development environments (Windows, Linux, macOS) via Git.

## Proposed Changes

### Project Root
#### [NEW] .antigravity/brain/
This directory will store the artifacts for the current conversation. We will use the conversation ID as a subfolder to maintain organization.
- `.antigravity/brain/885ed0f0-ab29-4cc4-a0bf-296905e78dc7/`

#### [MODIFY] [.gitignore](file:///C:/Users/linux/.gemini/antigravity/scratch/kobold_character_card_manager/.gitignore)
Ensure that the `.antigravity/brain` directory is NOT ignored by Git. We will add an explicit "allow" rule if needed, though by default hidden folders are not ignored unless specified.

#### [NEW] [.agent/workflows/sync-brain.md](file:///C:/Users/linux/.gemini/antigravity/scratch/kobold_character_card_manager/.agent/workflows/sync-brain.md)
Create a workflow that explains how to synchronize the "brain" folder between the system path and the repository.

## Verification Plan

### Manual Verification
1. Verify that the `.antigravity/brain` folder is created and contains the current artifacts.
2. Use `git status --ignored` to confirm that the folder is tracked and not ignored.
3. Verify that the workflow file is correctly placed and contains clear instructions.
