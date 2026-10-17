# SOW — Chat prompt picker + web settings parity

Builds on PR #546 (global prompt additions) by @josh-hemphill. His PR surfaced the
prompt-taxonomy problem this SOW fixes; commits here that relocate or extend his
widget carry `Co-Authored-By: josh-hemphill <j1.robofan@gmail.com>`. The web drift
this SOW corrects is ours, not his — we fix it, we don't shovel it onto a contributor.

## Phase 0 — Merge #546 with the desktop placement fixed by us

Do not send Josh a change request. Check out the PR branch and finish it ourselves:

- Move `GlobalPromptAdditions` out of `generation_tab.dart`; mount it flat in
  `general_tab.dart` directly under the Fallback system prompt box (subheading +
  two fields, no `ExpansionTile` — it would be the only accordion in Settings).
- Ripple: the PR's own widget test drops the accordion tap; `docs/Rawhide.md` and
  `docs/design/global-chat-prompt-additions.md` flip "Settings → Generation" to
  "Settings → General".
- Web placement stays as-is on purpose; Phase 2 owns it.
- Gate: `flutter analyze` clean on touched files, scoped suite green, web e2e
  unchanged and green (single scrolling page, text selectors — must still pass).
- Commit with the co-author trailer, merge.

## Phase 1 — Per-chat prompt source + new-chat picker

### Model

Two nullable fields on `ChatGenerationSettings` (per-session JSON blob — no DB
migration, same additive pattern as the sanitizer rules):

- `systemPromptSource`: `'card' | 'user'` — which base wins.
- `promptAmendmentsEnabled`: `bool` — whether #546's global additions append.

`null` on both = inherit = today's behavior (card prompt + amendments). Resolution
happens at the existing chokepoint in `chat_service_generation_blocks.dart`,
before the addition append: `source == 'user'` selects the fallback system prompt
as the base; amendments append only when enabled.

The picker presents three named presets mapping to the pair:

1. **Card + my amendments** (default — today's behavior)
2. **Card only**
3. **My prompt**

### Trigger

New chat with a character whose card has a non-empty `systemPrompt` opens the
picker. "Remember my choice" flips a global pref that stops the ask; the choice
is editable any time in the sidebar Chat Tools (which already writes per-chat
overrides).

### UI requirements

- Dialog body is a `SingleChildScrollView` inside a `ConstrainedBox` capped at
  ~85% of viewport height — the dialog itself never overflows the screen.
- The card prompt and the user's prompt are both shown **in full** in scrollable
  preview panes; long prompts scroll, they never truncate or push buttons off
  screen. Side-by-side panes on desktop, stacked on phone.
- Segmented control for the three presets; the preview highlights which base is
  selected and where the amendment lands.

### Scope

- v1 is 1:1 only. Groups keep group-prompt + amendments unchanged.
- Continue, regenerate, swipe, impersonation read the current per-chat state at
  the same chokepoint; forks carry the override.
- Reset-block sync at all four reset sites (session load, chat entry, group entry,
  0-session) — the v39 gen-settings bleed is the cautionary tale.
- Web ships the same dialog (parity rule) or the maintainer defers it explicitly
  in the implementing conversation.

### Tests

- Assembly regression extending `test/services/chat/global_prompt_additions_test.dart`
  patterns: real `ChatService` transport, source switching, amendments off,
  exactly-once, macros.
- Widget test: pump a ~5k-char card prompt, assert the dialog renders with no
  overflow exception and both panes scroll.
- Budget parity: live estimate equals the sent prompt under each preset.

## Phase 2 — Web settings parity (Dart is standard-bearer)

Canonical standard is the rendered Dart tab order:
**General → Porch Life → Generation → Voice & Media → Backend → Advanced**.
Web keeps its single-scroll layout; parity means matching grouping, order, and
naming — not adding tabs.

- Reorganize `SettingsPage.tsx` into ordered sections mirroring the six tabs.
- Moves: fallback system prompt + global additions → General; Chat speech →
  Backend; Model transport → Generation; message side / follow streaming /
  reading size / chat colors / chat theme → grouped under "Chat appearance" in
  General; idle unload + keep-recent-chats → Backend; personas → audit against
  the Dart home and place accordingly.
- Update e2e specs whose selectors change (`globalPromptAdditions.spec.ts` first).
- **Parity manifest guard**: one JSON map of setting-key → section, consumed by a
  Dart hygiene test and a Vitest guard. A future PR mounting a field in the wrong
  section fails CI the way the god-file ratchet and theme lint do.

## Sequencing

Phase 0 first (small, unblocks the taxonomy). Phases 1 and 2 are independent and
may run in parallel; the Phase 1 web dialog does not depend on the Phase 2
settings layout.

## Poke script (done means)

1. Download a card with a prompt, start a new chat → picker shows both prompts in
   full, scrollable. Choose "My prompt", send, inspect the sent prompt: fallback
   base, no card prompt.
2. Switch to "Card only" → amendments gone from the sent prompt. "Card + my
   amendments" → both present, exactly once.
3. Continue, regenerate, impersonate under each preset; budget estimate matches
   the sent prompt.
4. Fork the chat → override carries. Start another new chat with the same
   character → remembered choice (or re-asks per the pref).
5. Web: settings sections match the Dart order; e2e suite green.

## Out of scope

Group per-speaker prompt sources, per-chat post-history overrides (global only),
model-specific presets, web tabs.
