# God File Refactoring Guide

## Guiding Principles

1. **Never refactor and add features simultaneously** — each PR does one thing.
2. **Extract, don't rewrite** — pure mechanical moves, no behavioural changes.
3. **Each stage is independently mergeable** — no half-broken main.
4. **Keep imports compiling at every commit** — remove old file only after all references are updated.
5. **One god file per stage** — never split two files in the same PR.
6. **No Riverpod migration during extraction** — keep `ChangeNotifier`/`Provider` pattern. Refactor structure first, migrate state management later.
7. **No file stem collides with a folder name** — e.g. no `chat_service.dart` sitting next to a `chat/` directory. New folders use distinct names where needed.

## Name Conflict Map

Before creating any new directory, verify there is no existing file (minus extension) with the same name in the parent directory.

| New folder | Collides with | Safe? |
|---|---|---|
| `lib/services/chat/` | `chat_service.dart` — different stem | Yes |
| `lib/ui/chat_components/` | nothing | Yes |
| `lib/ui/character_creator/` | `character_creator_page.dart` — different stem | Yes |
| `lib/ui/settings/` | `settings_page.dart` — different stem | Yes |
| `lib/services/web_server/` | `web_server_service.dart` — different stem | Yes |
| `lib/services/storage/` | `storage_service.dart` — different stem | Yes |

## Deprecation Shim Pattern

When extracting code from a god class, leave a forwarding shim so existing callers continue to compile:

```dart
// In the original god class, after extraction:
@Deprecated('Access via NeedsSimulationService directly')
Map<String, int> get needsVector => _needsSimulation.needsVector;
```

This makes extraction a **pure additive change** — nothing breaks, nothing moves. Old callers can be migrated to the new import at leisure. The shims are removed in a final cleanup PR once all references are updated.

## Extraction Priority Order (file-by-file)

The order below maximises early wins (reducing the largest files first) while keeping risk low:

| Stage | God file | Lines | New location | Strategy |
|---|---|---|---|---|
| 1 | `chat_service.dart` — enums + model | 11.3K | `lib/models/chat_message.dart` | Lift top-level declarations only |
| 2 | `chat_page.dart` — sidebar sections | 11.1K | `lib/ui/chat_components/` | One widget per file, public rename |
| 3 | `chat_service.dart` — domain services | 11.3K | `lib/services/chat/` | Plain class extraction, not ChangeNotifier |
| 4 | `character_creator_page.dart` — steps | 7.8K | `lib/ui/character_creator/` | State object + step widgets |
| 5 | `settings_page.dart` — tabs | 5.9K | `lib/ui/settings/` | Tab files + dialog files |
| 6 | `web_server_service.dart` — route handlers | 5.3K | `lib/services/web_server/` | Handler classes per route group |
| 7 | `storage_service.dart` — domain settings | 1.9K | `lib/services/storage/` | Plain settings classes |

---

## Stage 1: Lift `ChatMessage` and enums from `chat_service.dart`

**Goal:** Extract `ChatMessage`, `GenerationMode`, `GenerationPhase` into their own file.

**Why first:** Zero behavioural change. Teaches the extraction pattern on the safest possible target.

### Steps

1. Create `lib/models/chat_message.dart` containing the three declarations.
2. Add `export 'chat_message.dart';` to `lib/models/models.dart`.
3. In `chat_service.dart`, replace the three declarations with `import 'package:front_porch_ai/models/models.dart';` (or `chat_message.dart`).
4. Run `grep -rn 'ChatMessage' lib/ --include="*.dart"` to find all other files referencing `ChatMessage`. Update them to import from the barrel or the new file.
5. Delete the three declarations from `chat_service.dart`.
6. Run `flutter analyze` — zero warnings required.

### Verification

- All existing imports of `chat_service.dart` that also use `ChatMessage` must have the new import added (whether or not they already import `models.dart`).
- Session save/load and display must produce identical results.

---

## Stage 2: Extract `chat_page.dart` private widgets

**Goal:** Move each private widget class into its own public file under `lib/ui/chat_components/`.

### Directory layout after extraction

```
lib/ui/chat_components/
├── bubbles/
│   ├── message_bubble.dart         ← _MessageBubble, _MessageBubbleState
│   ├── styled_chat_message.dart    ← _StyledChatMessage
│   └── external_image_widget.dart  ← _ExternalImageWidget, _ExternalImageWidgetState
├── sidebar/
│   ├── sidebar_section.dart        ← _SidebarSection, _CollapsibleSidebarSection
│   ├── lorebook_section.dart       ← _LorebookSection, _GroupLorebookSection
│   ├── scene_time_section.dart     ← _SceneTimeSection
│   ├── author_note_section.dart    ← _AuthorNoteSection
│   ├── summary_section.dart        ← _SummarySection
│   ├── memory_section.dart         ← _MemorySection
│   ├── realism_section.dart        ← _RealismSection
│   ├── nsfw_section.dart           ← _NsfwEnhancementsSection
│   ├── chaos_mode_section.dart     ← _ChaosModeSection
│   └── objective_section.dart      ← _ObjectiveSection, _EditableTaskRow
├── overlays/
│   ├── rag_setup_dialog.dart       ← _RagSetupDialog
│   ├── realism_processing_overlay.dart  ← _RealismProcessingOverlay
│   ├── objective_check_overlay.dart     ← _ObjectiveCheckOverlay
│   └── generation_status_bar.dart       ← _GenerationStatusBar, _PulsingIcon
└── widgets/
    ├── eval_pill.dart              ← _EvalPill, _AnimatedEvalPill
    └── settings_menu_item.dart     ← _SettingsMenuItem
```

### Extraction pattern (per commit)

1. Create the new file. Copy the widget class(es) verbatim, minus the leading `_`.
2. Add whatever imports were implicitly available from `chat_page.dart`'s top-of-file.
3. In `chat_page.dart`, replace the class body with a re-export or a `typedef` alias:
   ```dart
   typedef MessageBubble = _MessageBubble; // temporary, removed in cleanup
   ```
   Alternatively, replace constructor calls with new public names and leave the old private class dead code (to be removed in the cleanup PR).
4. `flutter analyze` must pass.
5. Repeat for each widget in the order listed above, one commit each.

### Cleanup commit (2z)

After all widgets are extracted:
1. Delete all dead code from `chat_page.dart`.
2. `flutter analyze` — zero warnings.
3. Smoke-test: open a 1:1 chat and a group chat, verify all sidebar sections render, overlays appear, messages display.

---

## Stage 3: Split `chat_service.dart` into domain services

**Critical rule:** Each extracted service is a **plain Dart class**, not a `ChangeNotifier`. `ChatService` continues to own instances of them via private fields and delegates to them. This avoids provider tree churn and stale-snapshot bugs.

### Directory layout

```
lib/services/chat/
├── needs_simulation.dart      ← needs decay, stepping, catastrophe, climax detection
├── chaos_mode_service.dart    ← chance time, pressure gauge, event pools
├── relationship_service.dart  ← affection, trust, inter-character feelings, scores
├── expression_classifier.dart ← emotion-to-expression (LLM + ONNX)
├── time_service.dart          ← time passage, nudge, day-of-week resolution
├── nsfw_service.dart          ← cooldown, arousal tier
├── lorebook_scanner.dart      ← keyword matching, depth tracking
├── prompt_injection/          ← all _get*Injection builders (8 files)
│   ├── author_note_builder.dart
│   ├── relationship_injection.dart
│   ├── emotion_injection.dart
│   ├── behavioral_injection.dart
│   ├── time_injection.dart
│   ├── nsfw_injection.dart
│   ├── chaos_injection.dart
│   └── needs_injection.dart
├── llm_eval_engine.dart       ← _fireLLMEval, JSON extractors, _stripThinkBlocks
├── realism_evals.dart         ← 5 evaluation calls (rel, emotion, phys, narr, one-shot)
├── objective_service.dart     ← objectives CRUD, tasks, completion checking
├── summary_service.dart       ← auto-summary generation
├── fact_extraction.dart       ← fact extraction + consolidation
└── evolution_service.dart     ← trigger, extract, reset character evolution
```

### Extraction order

Extract **leaf dependencies first** (no references to other extracted code), then work upward:

| Order | File | Depends on |
|---|---|---|
| 1 | `needs_simulation.dart` | nothing |
| 2 | `chaos_mode_service.dart` | nothing |
| 3 | `relationship_service.dart` | nothing |
| 4 | `expression_classifier.dart` | nothing |
| 5 | `time_service.dart` | nothing |
| 6 | `nsfw_service.dart` | nothing |
| 7 | `lorebook_scanner.dart` | nothing |
| 8 | All `prompt_injection/*` | needs_simulation, time_service, etc. |
| 9 | `llm_eval_engine.dart` | prompt_injection (for prompt building) |
| 10 | `realism_evals.dart` | llm_eval_engine |
| 11 | `objective_service.dart` | llm_eval_engine |
| 12 | `summary_service.dart` | llm_eval_engine |
| 13 | `fact_extraction.dart` | llm_eval_engine |
| 14 | `evolution_service.dart` | llm_eval_engine |
| 15 | Refactor remaining `ChatService` | all of the above |

### Extraction pattern (per commit)

1. Create the new file. Copy all methods + private fields for that domain.
2. The constructor receives whatever state it needs (scalar values, other services). For the initial extraction, pass the whole `ChatService` as a parent reference via an interface or callback. (Granular callbacks are an acceptable implementation for the initial leaf per the Stage 3 needs_simulation precedent: they avoid import cycles, enable isolated unit tests with a small factory helper, and remain friendly to future extractions that will shrink the surface. The plan text is satisfied by documenting the choice; see docs/refactor-god-file-modularization.md Fix Round 1 and the sim header for rationale.)
3. In `ChatService`:
   ```dart
   late final _needsSimulation = NeedsSimulation(
     onNotify: notifyListeners,
     // ... other deps
   );

   // Deprecated shim
   @Deprecated('Access via NeedsSimulationService directly')
   Map<String, int> get needsVector => _needsSimulation.needsVector;
   ```
4. `flutter analyze` — zero warnings.
5. Verify: send a message in a chat with realism mode on. Needs should decay identically.

### Communication pattern

Extracted services signal back to `ChatService` via a callback function (e.g. `VoidCallback onNotify`, or specific callbacks like `Future<void> Function(String prompt) onInjectPrompt`). This keeps them testable and decoupled from the parent.

---

## Stage 4: Extract `character_creator_page.dart` steps

### Directory layout

```
lib/ui/character_creator/
├── character_creator_page.dart       ← thin shell (~200 lines)
├── creator_state.dart                ← ChangeNotifier with all 60+ shared fields
├── steps/
│   ├── setup_step.dart               ← backend/model selection
│   ├── mode_select_step.dart         ← Auto/Guided/Quick picker
│   ├── quick_config_step.dart        ← minimal config
│   ├── guided_config_step.dart       ← free-text config
│   ├── automated_config_step.dart    ← full structured form
│   ├── generating_step.dart          ← progress + streaming preview
│   ├── realism_step.dart             ← initial realism state
│   └── review_step.dart              ← avatar + editable card
└── widgets/
    ├── backend_chip.dart             ← backend selector pill
    ├── mode_card.dart                 ← mode selection card
    └── styled_text_field.dart         ← auto-saving text field wrapper
```

### Strategy

1. Extract `creator_state.dart` first — move all `_pref*` keys, `_loadSavedState`, `_saveState`, all step-index and form-field fields. This is a pure lift.
2. Extract `review_step.dart` first (largest at ~1,900 lines).
3. Extract each remaining step.
4. Main page becomes an `AnimatedSwitcher` keyed on `creatorState.currentStep`, building the appropriate step widget.

---

## Stage 5: Extract `settings_page.dart` tabs

### Directory layout

```
lib/ui/settings/
├── settings_page.dart                ← TabBar shell (~150 lines)
├── tabs/
│   ├── general_tab.dart              ← dark mode, font, colours, prompts
│   ├── generation_tab.dart           ← temperature, penalties, limits
│   ├── voice_media_tab.dart          ← TTS, STT, image gen, expressions
│   ├── backend_tab.dart              ← backend mode, API config, model select
│   └── advanced_tab.dart             ← storage, web server, GPU, launch flags
├── dialogs/
│   ├── color_picker_dialog.dart      ← _showColorPicker
│   ├── prompt_save_dialog.dart       ← _showSavePromptDialog
│   ├── prompt_delete_dialog.dart     ← _showDeletePromptDialog
│   └── model_search_dialog.dart      ← _showModelSearchDialog
└── widgets/
    ├── color_row.dart                ← _buildColorRow
    ├── vram_gauge.dart               ← VRAM bar + legend
    ├── mode_chip.dart                ← _buildModeChip
    ├── preset_chip.dart              ← _buildPresetChip
    ├── api_preset_chip.dart          ← _buildApiPresetChip
    ├── slider_setting.dart           ← _buildSlider
    └── section_header.dart           ← _buildSectionHeader
```

### Strategy

1. Extract `voice_media_tab.dart` first (largest tab at ~1,050 lines).
2. Extract helper dialogs (`color_picker_dialog.dart`).
3. Extract remaining tabs.
4. Keep `_SettingsPageState` owning shared state (controllers, currently selected model, etc.). Pass it to tabs via constructor or `Provider`.

---

## Stage 6: Extract `web_server_service.dart` route handlers

### Directory layout

```
lib/services/web_server/
├── web_server_service.dart        ← server lifecycle, middleware wiring, router setup (~400 lines)
├── middleware/
│   ├── auth_middleware.dart       ← PIN login, Bearer token validation
│   ├── cors_middleware.dart
│   └── client_tracker.dart        ← active-client state tracking
├── routes/
│   ├── auth_routes.dart
│   ├── character_routes.dart
│   ├── chat_routes.dart
│   ├── settings_routes.dart
│   ├── backend_routes.dart
│   ├── tts_routes.dart
│   ├── image_gen_routes.dart
│   ├── story_routes.dart
│   ├── cloud_sync_routes.dart
│   └── ... (per feature group)
├── sse/
│   ├── chargen_stream.dart
│   └── story_pipeline_stream.dart
└── helpers/
    ├── image_cache.dart
    ├── web_asset_server.dart
    └── route_utils.dart           ← _crc32, _basename, _normalize*, _parseUserAgent
```

### Strategy

1. Each route group becomes a class with a constructor that receives `WebServerService` (for service access) and a `Router` to register handlers.
2. The main `WebServerService.start()` constructs the router, instantiates all route classes, and passes each the router.
3. SSE streaming classes are extracted last — they're the most coupled to shared mutable state (`_chargenStatus`, etc.).

---

## Stage 7: Decompose `storage_service.dart` into domain settings

### Directory layout

```
lib/services/storage/
├── storage_service.dart           ← directory management only (~300 lines)
├── directories.dart               ← rootPath, modelsDir, chatsDir, etc.
├── settings/
│   ├── backend_settings.dart
│   ├── generation_settings.dart
│   ├── ui_settings.dart
│   ├── tts_settings.dart
│   ├── stt_settings.dart
│   ├── image_gen_settings.dart
│   ├── expression_settings.dart
│   ├── web_server_settings.dart
│   ├── cloud_sync_settings.dart
│   ├── realism_settings.dart
│   ├── memory_settings.dart       ← RAG, summary, evolution intervals
│   └── preset_settings.dart       ← system prompts, kcpps presets
```

### Strategy

1. Each settings file follows a consistent pattern — private field, public getter, `Future<void> setX(value)` that writes to `SharedPreferences` and calls `notifyListeners()`.
2. A shared `SettingsBase` mixin provides the `_prefs` reference, key prefix, and `notifyListeners`.
3. `StorageService` keeps backward-compat shims:
   ```dart
   @Deprecated('Use TtsSettings instead')
   Future<void> setTtsEnabled(bool v) => _ttsSettings.setEnabled(v);
   ```
4. Once all shims are migrated by callers, `StorageService` drops to pure directory management.

### Why not use multiple `ChangeNotifier`s here?

Same reasoning as Stage 3 — `StorageService` already notifies listeners on every setter. Widgets that need a subset of settings use `context.select`. Premature decomposition to multiple notifiers adds provider tree depth with no measurable gain. Extract as plain settings classes, consider promotion later if profiling warrants it.

---

## Rollback Plan

If a PR introduces regressions:

1. **Revert the extraction commit** — old code is intact in the parent commit.
2. Never fix forward in the same PR. Merge the revert, then re-apply with smaller scope.
3. Pure mechanical extractions never touch `.g.dart` files, database schema, or `pubspec.yaml`, so rollbacks are safe and conflict-free.

## Verification Checklist (every PR)

- [ ] `flutter analyze` — zero warnings (new or existing).
- [ ] `flutter test` — all existing tests pass.
- [ ] Manual smoke test of the affected page (e.g. after sidebar section extraction, verify chat page opens, sidebar toggles, all sections render).
- [ ] No new files added to `lib/services/services.dart` barrel unless they are used from 3+ locations.
- [ ] No state-management pattern change (still `ChangeNotifier`, not Riverpod).
- [ ] Old API preserved via `@Deprecated` shim where callers exist outside the extracted file.

## Lint Hygiene Pass (Stage 1 Worktree)

During the god-file refactoring on `stage1-experiment`, a dedicated cleanup eliminated all warnings (unused_*, dead_code) from group_settings_dialog.dart and chat_page.dart by removing confirmed-dead placeholder methods/fields left from 2026 UX changes. Also fixed:

- All 9 curly_braces_in_flow_control_structures (mechanical blocks added in tier color helper).
- ~23 easy `withOpacity` → `withValues(alpha:)` deprecations limited to 4 small files (stable_db_import_dialog, chance_time_overlay, app_text_field, slider_with_input) — no god-file churn.
- 12+ unintended_html_in_doc_comment via minimal &lt;/&gt; entities or {groupId} in path/type examples (database, models/chat_message + group_member, embedding_sidecar) — no prompt string changes or large diffs.
- use_null_aware_elements and Radio deprecations left as wontfix (non-straightforward or would alter structure/prompt fidelity).

Result: 138 → 85 issues (0 warnings). All changes followed "0 new private methods", barrel/AppColors rules, and were verified with analyze + model tests after each batch. This work is recorded here because it occurred inside the isolated stage1 worktree. See /tmp/grok-impl-summary-47207bb1.md for full details.
