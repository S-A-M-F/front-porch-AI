# What's New in v0.9.9

🎉 Biggest update yet — here's what's new:

**macOS users:** The recommended download is now the signed and notarized `Front_Porch_AI.pkg` (Developer ID + Apple notarization). It installs cleanly to /Applications, handles the Python sidecars properly under hardened runtime, and plays nicely with Gatekeeper. The `Front_Porch_AI.dmg` is still provided as an unsigned legacy "shim" so the in-app auto-updater continues to work for everyone during the transition. Old clients that expect a DMG will keep working; new or fresh installs should prefer the .pkg.

👥 **Fork-to-Group Wizard** — Fork any 1:1 chat into a group with a guided wizard. Drag to set arrival order, give each newcomer a custom entrance (your own words, an AI-written direction, or silent), and the round-robin picks up naturally after.

🧠 **Needs Simulation** — Hunger, Bladder, Energy, Social, Fun, Hygiene, and Comfort are now a live simulation. Characters react when levels drop. Per-character decay rates are configurable, and a new Manual Reprocess button lets you tell the Director exactly what happened (e.g. *"she ate a granola bar"*) to correct Needs on the fly.

🧠 **Needs refinements** — Characters now get earlier subtle hints about needs (mild "background sensation" language is visible again) and will act on them before they become critical. Comfort and Hygiene are no longer completely drowned out by faster-decaying needs; up to two relevant low needs can color the prompt each turn. Strong replenishing scenes (big meal, deep rest, caring attention) can now restore a full +100 to a need in one go while downside swings remain conservatively capped.

🎭 **Group Settings Redesign** — Dedicated Needs tab with per-character baseline sliders. Realism tab now has editable bond, trust, starting emotion, and time-of-day per member. All changes seed future sessions.

📤 **Export User Personas** — Export your personas as SillyTavern-compliant JSON, learned facts and all.

✨ **Home Screen Refresh Button** — Rescan for new character files without leaving the page.

📁 **Folder previews on the home screen** — folders now show a 2×2 thumbnail of the first few characters inside them instead of a plain folder icon, so you can tell at a glance what's in each one. The preview scales with your grid size; empty folders keep the classic folder icon.

🛠️ **Database Cleanup Tool** — Find and purge orphaned records left behind by deleted characters or stale sessions.

🔧 **Major Internal Modularization** — The core god files have been decomposed into focused, testable modules with 1,100+ new tests. You won't see it directly, but the app is meaningfully more stable and easier to build on.

---

## 🤝 Contributors

- **MisterLotto** — Fork-to-Group wizard with custom entrance sequences (PR #50)
- **S-A-M-F** — Massive internal modularization and test suite overhaul
- Everyone in Discord who tested and filed bugs — thank you ❤️

— SosukeAizen