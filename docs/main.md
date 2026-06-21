# What's New

These notes feed the in-app "Update Available" dialog for stable releases on `main`.

## Highlights

- 🎨 **Image Studio is now a first-class integrated experience** — Open a dedicated studio with buttons for Visualize Scene, Character Portrait, Chat Background, and Custom. Full settings (models, LoRAs, style, negative, steps, CFG, etc.) live inside as tabs. Visualize Scene uses a slider for the most recent N messages so the generated image matches what's actually happening. Prompts start clean without boilerplate. Old separate illustration button and dialogs removed for a much smoother flow.

- 🧠 **Realism Engine and character needs are dramatically more reliable** — Bond, Trust, and Lust deltas now consistently show in chips. Manual Needs Reprocess is safe, survives regens and empty responses, and works in groups with a "Director corrected" pill. Groups properly track per-speaker needs, decay, and scene rewards. Larger positive boosts from strong scenes, earlier natural hints from characters, dedicated Needs tab in group settings, and editable realism baselines.

- 🧬 **Character evolution now follows the schedule you set** — The "Evolve every N messages" slider finally works with its own independent counter (including in groups).

- 👤 **AI Character Creator local model picker finally works** — KoboldCpp (local) now scans and picks correctly using the exact same clean searchable interface as remote providers.

- 📁 **Home screen improvements** — Folders show quick 2×2 previews of characters inside. Refresh button for scanning external imports.

- ✨ **Better editing and SillyTavern-style macros** — Live syntax highlighting for dialogue, actions, and {{macros}} with no lag. Fullscreen editor keeps colors and spellcheck. Macros ({{random}}, {{roll}}, {{time}}, {{pick}}, comments, spacing) now work inside character cards, scenarios, and lorebooks. Unified lorebook editor with enable/disable toggles everywhere.

- 📤 **Export User Personas** — Export as full SillyTavern-compatible JSON (learned facts are a Front Porch-only feature and will be ignored by other apps).

- 🪟 **Windows install fixes** — Installs now land in the correct folder, and Stable, Beta, and Nightly install side-by-side without overwriting each other. If an earlier update placed your install in the wrong folder, it's repaired automatically on the next update — no reinstall needed. Plus: no more ghosting when restoring maximized windows.

- Many additional group chat, needs, realism, and stability fixes that make the experience feel much more consistent and alive.

For the complete list, see the GitHub release notes.