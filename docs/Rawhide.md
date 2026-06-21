# Rawhide — What's New (Nightlies)

These notes feed the in-app "Update Available" dialog for Rawhide / cutting-edge builds.

## Recent improvements

- 📥 **Bulk-import Backyard AI characters (files *or* folders)** — the "Import BYAF" picker now lets you select **multiple `.byaf` files at once** (a single file still shows the full preview). And **"Import Folder" now imports both V2 PNG cards and `.byaf` files together**: it shows a breakdown of what's in the folder with independent checkboxes ("12 V2 PNG cards" / "5 Backyard AI files" + "also import chat history"), so a mixed folder imports exactly what you choose — no surprises. Everything runs through one progress bar with success/fail counts.

- 🎭 **AI Character Creator fully restored — it generates and saves real characters again** — At some point the creator had been quietly broken in two ways. On the surface, its setup screens were stripped down to bare boxes. Underneath it was worse: "generating" a character actually just produced a hardcoded placeholder (no AI was ever called), and the final Save step never saved anything. Everything is back and working: **Quick**, **Guided**, and **Automated** setup with all their options — the appearance builder, archetype quick-start presets, personality/backstory/NSFW trait chips, world-lore URL + file attachment, and the "magic wand" that writes a description for you. The **Realism** screen (seed a character's starting bond/trust/mood/needs) is wired up again, and the **Review** screen is back with avatar regenerate/crop, an editable card, and lorebook cherry-pick. Real AI generation and saving work end-to-end once more, with the original look and accent colors.

- 📁 **Subfolders no longer create phantom duplicate characters** — If you had a folder with characters, made a subfolder, and dragged a character into it, a duplicate copy used to appear back on the parent-folder screen — and deleting that "duplicate" would delete your real character too. Fixed: a character now lives only where you put it, with no phantom copy to accidentally delete. Large libraries also reload a little faster when you organize folders.
