# Widget golden coverage ledger

Tracks full-app UI-regression golden coverage across `lib/ui/` (154 files: 21
pages, 25 dialogs, 36 top-level widgets, 10 sidebar sections, chat
overlays/bubbles, image studio, settings, layout). Every surface is a target,
captured in **light + dark** via `expectThemedGoldens`.

Status: ✅ covered · 🔶 in progress · ⬜ pending · 🚫 not feasible (with reason).

The infrastructure is complete and proven end-to-end on the first area; the
remaining areas are intentionally landed in reviewable batches (see the plan's
Phase 4) rather than one giant PR. Pick up the next ⬜ area, add a focused
`<area>_golden_test.dart` using `expectThemedGoldens`, generate PNGs on Linux,
and flip the row to ✅.

## Infrastructure
- ✅ `support/golden_app.dart` — `pumpGolden` / `expectThemedGoldens` (light+dark, fixed surface)
- ✅ `flutter_test_config.dart` — google_fonts fetch disabled + bundled Roboto
- ✅ `dart_test.yaml` + `@TestOn('linux')` gating + CI `--tags golden` step
- ✅ `support/creator_test_support.dart` — path_provider mock + `makeGoldenStorage`
- 🔶 `support/fakes.dart` — timer-free service doubles for provider-backed goldens.
  `FakeLLMProvider` ✅ (unblocked ReviewStep). `FakeChatService` 🔶 (grows per
  section; now covers sidebar + MessageBubble surface). `FakeTtsService` ✅ (unblocked
  MessageBubble). `FakeUserPersonaService` ✅.
- ⬜ `support/fixtures.dart` — canonical deterministic CharacterCard / chat / group / needs / lorebook

## Character Creator — `lib/ui/character_creator/`
The June-6 "Stage 4" refactor shipped a *functionally dead* creator to stable
(stubbed engine + step screens gutted to placeholders — see `.claude/changelog.md`
2026-06-21). This area is covered on two axes so neither failure can recur silently:
- ✅ **Engine behavior** — `creator/creator_engine_golden_test.dart` (behavioral,
  not pixel): `saveCharacter` persists a real card to the repo with realism seeding
  + lorebook filtering (freezes the saved JSON shape); `generateFromMode` actually
  drives the LLM and yields a model-derived card (kills the hardcoded-dummy stub).
  A pixel golden cannot catch a stubbed engine — these assert the behavior directly.
- ✅ **Wizard screens** — `widget/creator_steps_golden_test.dart`: `ModeSelectStep`
  (3 mode cards), `QuickConfigStep` (concept + options), `RealismStep` (full
  realism/needs form), `ReviewStep` (avatar panel + editable card fields, via
  `FakeLLMProvider` + bounded-frame pump for the cursor ticker). Light + dark.
- ⬜ `SetupStep` (backend config) — Provider-heavy (ModelManager/Kobold/
  PseudoRemote/BackendManager state drives live model lists + status dots);
  needs those service doubles too.
- ⬜ `GuidedConfigStep`, `AutomatedConfigStep`, `GeneratingStep`.

## Leaf widgets — `lib/ui/widgets/` (prop-only, no provider tree)
- ✅ `needs_bar.dart` — `NeedsBar` (healthy/critical/mini) + `NeedsGrid` (full set)
- ⬜ `fixation_chip.dart`, `realism_progress_row.dart`, `slider_with_input.dart`,
  `styled_dropdown.dart`, `app_text_field.dart`, `character_name_input.dart`,
  `age_gender_row.dart`, `nsfw_toggle.dart`, `persona_selector_dropdown.dart`,
  `model_selector.dart`, `local_model_card.dart`, `hf_model_card.dart`,
  `kcpps_selector.dart`, `greeting_tone_selector.dart`,
  `avatar_art_style_selector.dart`, `first_message_length_dropdown.dart`,
  `alternate_greetings_slider.dart`, `description_detail_chip_row.dart`,
  `_hoverable_card.dart`, `log_view.dart`, `download_queue_panel.dart`, …
- ⬜ `chat_components/widgets/` — `eval_pill.dart`, `settings_menu_item.dart`

## Chat bubbles — `lib/ui/chat_components/bubbles/`
- ✅ `message_bubble.dart` — `widget/chat_golden_test.dart`: user message, AI plain,
  AI with realism chips (bond/mood/trust row). `FakeTtsService` + `FakeUserPersonaService`
  unblocked the `Consumer2<TtsService, StorageService>` and persona consumer. Chat text
  renders as Ahem boxes (storage font family not bundled) — deterministic; layout
  regressions and chip-row regressions are caught. Light + dark.
- ✅ `styled_chat_message.dart` — rendered inside every MessageBubble golden above;
  its `Provider<StorageService>` reads (textScale, colors, font family) are covered
  by those captures.

## Sidebar sections — `lib/ui/chat_components/sidebar/` (`widget/sidebar_golden_test.dart`, FakeChatService)
- ✅ scene-time (evening/day-3 + dawn/day-1), author-note, summary, nsfw,
  chaos (enabled w/ pressure gauge), lorebook (header), objective (empty/propose),
  realism (seeded bond "Close"/long-term "Friendly"/trust "Trusting" + emotion +
  needs + decay — RelationshipService + NeedsSimulation wired into FakeChatService)
- ⬜ memory — reads `Provider<EmbeddingSidecar>` (RAG subprocess manager) +
  CharacterRepository + StorageService; needs those doubles (deferred)

## Chat overlays — `lib/ui/chat_components/overlays/`
- ⬜ generation status bar, objective check, RAG setup, realism processing

## Dialogs — `lib/ui/dialogs/` (25; skip `group_settings_dialog.dart.broken`)
- ⬜ all — pumped in a compact surface at a representative populated state

## Pages — `lib/ui/pages/` (21; heaviest, need shared MultiProvider of fakes)
- ✅ creator wizard — see "Character Creator" above (4 user-facing steps + engine)
- ✅ **home screen — character grid** (`CharacterCardGrid` widget) —
  `widget/home_golden_test.dart`: empty library state ("This folder is empty") +
  3-character grid (cards with name labels, tag chips, placeholder avatar icons,
  grid header with sort/scale controls). `FakeCharacterRepository` +
  `FakeFolderService` + `FakeGroupChatRepository` supply the three repo
  dependencies; `CharacterCardGrid` is fully param-driven so no heavy provider
  tree is needed. Light + dark.
- ⬜ **chat page** (`chat_page.dart`, ~3800 lines) — the MessageBubble surface is
  now covered (see Chat bubbles above). Full page golden deferred: needs
  `FakeExpressionClassifierService` + a seeded `ChatService` with a message list;
  the component-by-component path (individual consumers extracted) is the route.
- ⬜ settings, character create/edit, group create/edit, story (dashboard/setup/
  writer/reader/structure), model manager, cloud sync, world management,
  user persona, fork-to-group

### Next infrastructure step
Build `FakeExpressionClassifierService` in `support/fakes.dart` to cover the
expression/avatar panel (used on the chat page and character cards with avatars).
Also `FakeAppState` + `FakeKoboldService` to cover the home page status bar. With
those, the remaining pages become component-by-component goldens like the sidebar.

## Image studio — `lib/ui/image_studio/`
- ⬜ main surfaces + generation options tab (extend existing `test/ui/image_studio/`)

## Settings + layout
- ⬜ `lib/ui/settings/*` panels
- ⬜ `lib/ui/layout/main_layout.dart` (shell: sidebar + content)
