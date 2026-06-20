# STMacro — What's New (Nightlies)

These notes feed the in-app "Update Available" dialog for STMacro / cutting-edge builds.

## Recent improvements

- ⚡ **Character editor no longer lags while typing** — The full-page and create-character editors no longer rebuild their entire widget tree (including the Realism Engine form, Needs sliders, lore entries, and all four tabs) on every keystroke. Input latency dropped from ~1–2 seconds back to instant. The token counter badge still updates live.
- ✏️ **Fullscreen editor keeps your colors and spell check** — Clicking the expand icon now opens a fullscreen editor that looks and works just like the inline field. Your dialogue highlighting, macro coloring, and red wavy underlines for misspelled words are all still there. No more losing your formatting when you go big.
- 🎨 **Live `""`, `**` and `{{macro}}` highlighting in character editors** — Dialogue (amber), actions (blue), and macro tags (teal) are now highlighted as you type in greeting and example dialogue fields. `{{macro}}` tags are highlighted in all text fields. Spell check wavy underlines are layered on top of the coloring. Works in both the dialog and full-page editors.
- 🧩 **Prompt macros from cards & lorebooks (SillyTavern-style)** — `{{macro}}` tags now work inside character descriptions, system prompts, scenarios, and lorebook entries — just like in SillyTavern. They do **not** resolve from user chat input, so your typed messages stay exactly as you wrote them.

  **New macros available:**
  - `\{{` — put a literal `{{` in your card text (backslash escapes the braces)
  - `{{// your note here }}` — comment; everything inside is stripped from the prompt
  - `{{newline::3}}` — inserts multiple line breaks (great for spacing in cards)
  - `{{space::5}}` — inserts spaces for alignment
  - `{{random::a::b::c}}` — picks one at random each time the prompt is built
  - `{{pick::option1::option2::option3}}` — picks deterministically: same card, same position, same choice every time
  - `{{roll::2d6+3}}` — roll dice; `{{roll::bad}}` stays as-is in the prompt
  - `{{time}}` / `{{date}}` / `{{weekday}}` — live clock values in your character's text

## Lorebook & macro editor improvements

- 🎯 **Lorebook entry editing is now unified** — A single dialog handles all lorebook entry creation and editing, shared by the character dialog, full-page character editor, create-character wizard, group chat creator, and world manager. Every editor now supports `{{macro}}` highlighting in the content field and has an expand-to-fullscreen button.
- 🏷️ **All lorebook entry lists now show enable/disable toggle** — Every lorebook entry card includes a switch to quickly enable or disable an entry. Disabled entries are visually dimmed (duller border, gray icon and text) and are **not injected into prompts**. A tooltip explains the toggle: "Disable — entry won't be matched".
- 🖊️ **Edit character page gains lorebook entry name field** — The full-page character editor now shows and edits the name field in the lorebook entry dialog (was silently using the key as display name).
- 📦 **World lore entries moved to compact preview cards** — Instead of inline editing, world lore entries now show a compact preview card and open the shared dialog on edit — consistent with all other editors.
- 🔲 **Borders are just a bit thicker (1.5px)** — Lorebook entry cards now have a slightly thicker border so the enabled (blue accent) vs disabled (neutral) state is easier to distinguish at a glance.
- 🔧 **Fullscreen editor no longer flickers on macOS** — The expanded editor dialog no longer flips between grey and dark-grey when you click between windows. The M3 surface tint overlay has been disabled, and the hover flash on the text field is gone too. All color references now use the app theme so custom skins work correctly in both editors.
