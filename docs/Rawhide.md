# Rawhide — What's New (Nightlies)

These notes feed the in-app "Update Available" dialog for Rawhide / cutting-edge builds.

## Recent improvements

- 📥 **Bulk-import Backyard AI characters (files *or* folders)** — the "Import BYAF" picker now lets you select **multiple `.byaf` files at once** (a single file still shows the full preview). And **"Import Folder" now imports both V2 PNG cards and `.byaf` files together**: it shows a breakdown of what's in the folder with independent checkboxes ("12 V2 PNG cards" / "5 Backyard AI files" + "also import chat history"), so a mixed folder imports exactly what you choose — no surprises. Everything runs through one progress bar with success/fail counts.

- 🎭 **AI Character Creator fully restored — it generates and saves real characters again** — The creator's setup screens had been stripped down, and underneath it was worse: "generating" a character actually produced a hardcoded placeholder (no AI was ever called) and the final Save step never saved. It's all back and working: **Quick**, **Guided**, and **Automated** setup with every option (appearance builder, archetype presets, personality/backstory/NSFW trait chips, world-lore URL + file attachment, the "magic wand" description writer), the **Realism** screen (now with custom needs baselines + decay rates), and the **Review** screen (avatar regenerate/crop, editable card, lorebook cherry-pick). The three modes now share one polished, unified look — same bubbles/cards, each tinted a different accent (Quick=green, Guided=teal, Automated=amber) — and avatar image-gen settings are reachable right from the creator. Generated cards also now use {{char}} (not the literal name) and reliably include a first message.

- 📁 **Subfolders no longer create phantom duplicate characters** — Making a subfolder and dragging a character into it used to spawn a duplicate on the parent screen — and deleting that "duplicate" deleted your real character. Fixed: a character lives only where you put it, with no phantom copy. Large libraries also reload a little faster when you organize folders.
