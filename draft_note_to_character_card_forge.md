Subject / Message for the Character Card Forge dev:

---

Hey,

Quick heads-up from the Front Porch AI side: I just landed a small schema addition that touches the `sessions` table.

**What changed**
- Added column: `start_day_of_week INTEGER NOT NULL DEFAULT 0`
- This is schema version 28 (migration is a simple `ALTER TABLE sessions ADD COLUMN start_day_of_week INTEGER NOT NULL DEFAULT 0`)
- Purpose: Fix a bug where the narrative weekday ("Tuesday · Day 4", etc.) would drift after closing/reopening the app, even though `day_count` and `time_of_day` stayed correct. The weekday is now anchored per-session so it stays stable across restarts.

**Impact on Character Card Forge**
Your existing INSERTs into `sessions` should continue to work unchanged:
- The column has a safe default (`0`).
- When Front Porch loads a session with `start_day_of_week = 0` (or the column is omitted), it treats it as "legacy/unset" and computes a reasonable anchor so the weekday label doesn't jump around for the user.

If your INSERT statements for `sessions` use explicit column lists (the normal pattern), you don't need to change anything. If you ever want to seed a specific weekday anchor when creating sessions from the Forge, you can now include the column (1 = Monday … 7 = Sunday).

Let me know if this causes any issues on your side or if you'd like the exact migration snippet / load logic for reference. Happy to coordinate so the two tools stay in sync.

Thanks for the great integration work — the direct export path is really useful for people.

— [Your name/handle]

---

(Feel free to tweak the tone or add your GitHub handle / Discord name at the bottom.)