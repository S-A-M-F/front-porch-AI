# What's New

These notes feed the in-app "Update Available" dialog for stable releases on `main`.

## Highlights

- 🎭 **AI Character Creator — fully restored and overhauled** — The creator had quietly broken: its setup screens were stripped down, and underneath, "generating" a character just produced a hardcoded placeholder (no AI was ever called) and the Save step never actually saved. It's all back, and better than before. **Quick**, **Guided**, and **Automated** setup return with every option — the appearance builder, archetype quick-start presets, personality/backstory/NSFW trait chips, world-lore URL + file attachment, and a "magic wand" that writes a description for you — now sharing one clean, unified look (matching cards and bubbles, each mode tinted its own accent). The **Realism** screen seeds a character's starting bond/trust/mood and full needs (custom baselines + decay rates), and the **Review** screen has avatar regenerate/crop, an editable card, and lorebook cherry-pick. Real AI generation and saving work end-to-end again.

- 🛠️ **Configure & launch your backend right from the creator** — The Setup step now has dedicated KoboldCpp (local) and Pseudo-Remote sections with `.kcpps` preset + model selectors, a live status dot (Stopped → Starting… → Loading model… → Ready), a Start/Stop button, and a foldable "Extra Settings" panel (GPU layers, context size, KV quantization). Remote/oMLX share one searchable model picker — no more leaving the creator to start or tune your backend.

- 🤖 **Smarter, more reliable character generation** — Generated characters now reliably include a first message (the thinking-model edge cases that used to drop it are handled), and their description and personality use the portable `{{char}}` macro instead of the literal name, so they behave better in chat.

- 📥 **Bulk-import Backyard AI characters** — Select multiple `.byaf` files at once, and **"Import Folder" now imports both V2 PNG cards and `.byaf` files together** — with a per-type breakdown (and a "also import chat history" option) so a mixed folder imports exactly what you choose, no surprises. Everything runs through one progress bar with success/fail counts.

- 📁 **Subfolder fix** — Dragging a character into a subfolder no longer creates a phantom duplicate on the parent screen (and deleting that "duplicate" no longer deletes your original character). Organizing large libraries is a little faster, too.

For the complete list, see the GitHub release notes.
