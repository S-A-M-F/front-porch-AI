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
- ⬜ `support/fakes.dart` — shared `FakeChatService`/`FakeStorageService`/… (promote the ad-hoc `_Fake*` from `test/ui/`); needed before provider-backed surfaces
- ⬜ `support/fixtures.dart` — canonical deterministic CharacterCard / chat / group / needs / lorebook

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
- ⬜ `message_bubble.dart` (user / char / with realism chips / with image — image stubbed)
- ⬜ `styled_chat_message.dart`

## Sidebar sections — `lib/ui/chat_components/sidebar/` (need FakeChatService)
- ⬜ realism, needs, chaos, nsfw, memory, lorebook, objective, author-note, summary, scene-time

## Chat overlays — `lib/ui/chat_components/overlays/`
- ⬜ generation status bar, objective check, RAG setup, realism processing

## Dialogs — `lib/ui/dialogs/` (25; skip `group_settings_dialog.dart.broken`)
- ⬜ all — pumped in a compact surface at a representative populated state

## Pages — `lib/ui/pages/` (21; heaviest, need shared MultiProvider of fakes)
- ⬜ home, chat, settings, character create/edit, creator wizard (per step),
  group create/edit, story (dashboard/setup/writer/reader/structure),
  model manager, cloud sync, world management, user persona, fork-to-group

## Image studio — `lib/ui/image_studio/`
- ⬜ main surfaces + generation options tab (extend existing `test/ui/image_studio/`)

## Settings + layout
- ⬜ `lib/ui/settings/*` panels
- ⬜ `lib/ui/layout/main_layout.dart` (shell: sidebar + content)
