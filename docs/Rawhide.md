# Rawhide — What's New (Nightlies)

These notes are the in-app "Update Available" text for Rawhide builds. The
nightly takes every bullet under **Unreleased** as that build's release
body, and `tools/rotate-rawhide-notes.sh <tag>` then removes the bullets it
shipped, so a note is read here once and lives on in the GitHub release.
Write one bullet per change, on one line, with a bold title. Nothing else
goes in this file; `test/hygiene/rawhide_notes_test.dart` checks that.

Last shipped nightly: `nightly-rawhide.20261020.601968c`

## Unreleased

- 👥 **Cleaner group prompts** — every group turn is now built the same tidy way: your group prompt sets only the writing style, Front Porch adds its own turn rules (or Director Mode's) after it, and the speaking character's notes, card and examples sit in one block right before their reply. Fixes instructions running into the previous message in groups without a scenario, visitors forgetting where the scene is, card post-history instructions being ignored in groups, example lines being mistaken for recent chat, Continue only stopping the model from writing for you rather than the rest of the cast, and Impersonate while directing now writes your next stage direction. On the desktop and the web app.
- 🎬 **Director Mode keeps its rules under your own prompt, and one Group system prompt for every group** — a custom group prompt no longer drops the rules that keep you out of a directed scene, and while you direct the cast is no longer told you are the person they are talking with, so characters stop turning to you and auto-chat stops pausing. Settings → General now has a Group system prompt that every group uses (a group can still set its own in Group Settings), the Director prompt is rewritten, and the With you / Away check gets its line breaks back. On the desktop and the web app.
- 📝 **Saved prompts for both Settings prompts, and built-ins you can't overwrite** — the Fallback system prompt and the Group system prompt each keep their own pick from one shared list of your saved prompts, with a badge saying whether the box holds a built-in, a saved prompt (and whether you've edited it), or unsaved text. Save updates the prompt you loaded, Save as new never overwrites a name you already have, and Reset to built-in (with Undo) replaces the old preset buttons, so the shipped prompts stay out of the list and can't be saved over. On the desktop and the web app.
- ⚡ **More of the graphics card for KoboldCpp** — while a local model is reading or writing, the app now does less drawing of its own: the blur behind a Realism check is drawn once instead of every frame, a streaming reply redraws only the transcript and the status bar instead of the whole chat page, the KoboldCpp console updates a few times a second rather than on every token (and not at all while Home is hidden), and small portraits are decoded small. Replies on a busy card start and stream sooner. On the desktop.
