# Rawhide — What's New (Nightlies)

These notes feed the in-app "Update Available" dialog for Rawhide / cutting-edge builds.

## Recent improvements

- 🖥️ **Pseudo-Remote backend fully delivered** (PR #36) — Run KoboldCPP locally on your machine but talk to it through a clean OpenAI-compatible `/v1` endpoint. Choose your `.kcpps` preset, hit Start, and get full support for chat, Realism, Needs, and reasoning. The entire settings UI, model switching, process logs, autostart, and connection status now work consistently for managed Kobold instances.

- 🧠 **Major Realism & Needs upgrade** — Per-character group Realism is now first-class. Every character in a group chat maintains their own independent bond, trust, emotion, arousal, fixation, and full Needs state. Much richer proactive pre-response Needs pressure with natural OOC guidance. The strong "Enjoys low hygiene" personality inversion is fully supported — filthy characters are properly rewarded for enjoying it. Characters in groups finally feel like distinct individuals instead of sharing one blob of state.

- 🧼 **Enjoys low hygiene toggle** — Characters who love being musky and gross now get proper mechanical and narrative rewards. The inversion is strong and intentional, exactly as requested.

- 📖 **Story & stability fixes** — LLMs returning doubles instead of ints in Story projects no longer break things. Narrative weekday progression is now stable across app restarts. AUR nightly automation continues to work as before.

(The Pseudo-Remote backend code was left 100% untouched except for one small authorized addition to display per-character fixation in group member panels.)
