# STMacro — What's New (Nightlies)

These notes feed the in-app "Update Available" dialog for STMacro / cutting-edge builds.

## Recent improvements

- ⚡ **Character editor no longer lags while typing** — The full-page and create-character editors no longer rebuild their entire widget tree (including the Realism Engine form, Needs sliders, lore entries, and all four tabs) on every keystroke. Input latency dropped from ~1–2 seconds back to instant. The token counter badge still updates live.
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
