# Rawhide — What's New (Nightlies)

These notes are the in-app "Update Available" text for Rawhide builds. The
nightly takes every bullet under **Unreleased** as that build's release
body, and `tools/rotate-rawhide-notes.sh <tag>` then removes the bullets it
shipped, so a note is read here once and lives on in the GitHub release.
Write one bullet per change, on one line, with a bold title. Nothing else
goes in this file; `test/hygiene/rawhide_notes_test.dart` checks that.

Last shipped nightly: `nightly-rawhide.20261020.601968c`

## Unreleased

- ⚡ **More of the graphics card for KoboldCpp** — while a local model is reading or writing, the app now does less drawing of its own: the blur behind a Realism check is drawn once instead of every frame, a streaming reply redraws only the transcript and the status bar instead of the whole chat page, the KoboldCpp console updates a few times a second rather than on every token (and not at all while Home is hidden), and small portraits are decoded small. Replies on a busy card start and stream sooner. On the desktop.
