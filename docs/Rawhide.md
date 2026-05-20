# What's New on Rawhide (Nightly)

This file contains the friendly, non-technical notes that appear in the in-app **Update Available** dialog for users running Rawhide nightlies.

These notes are pulled from the GitHub Release body for the matching Rawhide-tagged build. Keep this file concise, benefit-focused, and written for normal users (not developers).

---

## Current Major Work (May 2026)

- **Deep Needs Simulation** — Characters now have realistic per-character needs (hunger, energy, social, comfort, and more) that decay over time and meaningfully influence their mood, focus, and dialogue in a natural way.

- **Realism Engine + Group Chat Maturity** — Major investment in making group chats feel as rich and consistent as 1:1 conversations. Recent highlights include:
  - Per-character group-scoped system prompts
  - Private inter-character relationship tracking (with safety limits)
  - Much improved, less mechanical needs and realism injection in groups
  - Better handling of per-character realism state when deleting messages in groups
  - UI and sidebar refinements in Group Settings and active group chats

- **Better In-App Update Experience** — Friendly changelogs now appear directly inside the update dialog so you can quickly see what’s new without having to visit GitHub or Discord.

Nightly builds include everything above plus whatever is actively being developed today.

---

**Note for contributors & AI agents**: When you land user-visible changes on the Rawhide branch, please also update this file with a short, friendly summary. This text will be used for the in-app update notes when the next Rawhide build goes out.