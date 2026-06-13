# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Front Porch AI is a Flutter desktop application (Windows/Linux/macOS) for AI-powered character chat using local LLMs via KoboldCpp. It features a "Realism Engine" for emotion/trust/relationship tracking, RAG memory via ONNX embeddings, TTS/STT, cloud sync, and a novel generator.

**License:** AGPL-3.0 (v0.9.0+), GPLv3 (earlier)
**State management:** Provider (migrating to Riverpod for new code)
**Database:** SQLite via Drift ORM

## Key Commands

```bash
# Setup
flutter pub get

# Development
flutter run                          # Debug run
flutter analyze                      # Lint (now at 0 warnings on active rules; CI runs on changed .dart files only for PRs + full scheduled job)
flutter format --set-exit-if-changed .  # Format check

# Tests
flutter test                         # Run all tests
flutter test --coverage              # With coverage
flutter test test/path/to/file.dart  # Single test file
flutter test -n "test name"          # Run specific test by name

# Build embedding server (Rust, required for RAG)
cargo build --release --manifest-path tools/embed_server/Cargo.toml

# Release builds
flutter build linux                  # Linux (then copy embed_server to build/linux/x64/release/bundle/embed_server/)
flutter build windows                # Windows (then copy embed_server.exe to build/windows/x64/runner/Release/)
./scripts/build-macos.sh             # macOS (bundles embed_server automatically)
```

## Architecture

### Directory Structure

```
lib/
├── main.dart                    # Entry point; initializes all services, window config, SIGINT handling
├── app_version.dart             # Version constant + isPreRelease flag
├── database/
│   ├── database.dart            # Drift schema (characters, chats, messages, lorebooks, worlds, etc.)
│   ├── database.g.dart          # Generated Drift code
│   ├── database_cleanup.dart    # Helper utility for database cleanup operations
│   └── data_migration_service.dart # Service managing data migrations between schemas
├── models/                      # Data models (character_card.dart, lorebook.dart, world.dart, etc.)
├── providers/
│   └── app_state.dart           # Global app state (ChangeNotifier)
├── services/                    # Business logic (~50 services)
│   ├── chat/                    # Domain subservices managing chat mechanics (leaf services extracted in Stage 3 god-file modularization; orchestration + group state remains in god for now)
│   │   ├── chaos_mode_service.dart # Pure simulation core for Chaos Mode / Chance Time events
│   │   ├── expression_classifier.dart # Extracted plain ExpressionService (wraps low-level classifiers for use inside ChatService)
│   │   ├── needs_simulation.dart # Sims-style per-character needs simulation logic (decay, buffers, apply/compute deltas)
│   │   ├── needs_impact_evaluator.dart # Consolidated needs impact (rich LLM JSON + Proposal A table + modifiers pipeline); sibling to sim; thins in god
│   │   ├── realism_evals.dart # 5 realism evaluation calls (relationship, emotional state, physical state, narrative, one-shot) + their prompt builders/orchestration/parse for deltas (bond/trust/emotion/arousal/fixation/spatial/time + pending chips); plain leaf sibling to llm_eval_engine (step 10 per order table); depends on engine for fire/strip/extract cbs (granular); full in leaf; thins/delegates at every prior call site in god + full excision; 0 new god private _ methods (thins as public surface; void _ count stays 15); stateless/prompt-only (no reset calls needed; reset comments expanded at all ~15+ sites + both startNew explicit + "incomplete zeroing... now complete"); dedicated test with factory (live cbs/group maps for real dispatch); aug/integration tests receive *only* qualified passive notes in headers (no leaf-specific edits; "aug exercising only passive/qualified (no realism-evals-specific aug file edits; full in dedicated + manual; qualified notes only in dedicated header + god + MD per precedent)"); 1:1 vs group + oneShot vs normal + Realism/Needs/Objectives parity 1:1 equivalent deltas preserved exactly (cbs + impersonation); anti-accumulation dead audit done.
│   │   ├── objective_proposal.dart # objective proposal path handling (autonomous "none" vs value + dedup + autoGenerateTasks:true *only* for autonomous + correct target even under group impersonation), generateObjectiveTasks (2000 + central strip for thinking), _checkTaskCompletionInBackground (2000 + strip; task vs taskless) + related prompt/strip/parse; plain leaf sibling to llm_eval_engine (step 11 per order table); engine provides strip cb (granular); full in leaf; thins/delegates at every prior call site in god + full excision from engine; 0 new god private _ methods (thins as public surface; void _ count stays 15); stateless/prompt-only (no reset calls needed; reset comments expanded at all ~15+ sites + both startNew explicit + "incomplete zeroing of secondary config on group/0-session/new-chat now complete" with _isChecking + messagesSince + objectives zeros in round 2 at ~8+ sites); dedicated test with factory (live cbs/group maps for real dispatch; 11 bodies post mandatory del + round 2); aug/integration tests receive *only* qualified passive notes in headers (no leaf-specific edits; "aug exercising only passive/qualified (no objective-proposal-specific aug file edits; full in dedicated + manual; exercised via god thins generate/check ; qualified notes only in dedicated header + god + MD per precedent)"); 1:1 vs group + oneShot vs normal parity for proposed "none"/value + dedup + auto only autonomous + correct target (even under impersonation; gen prompt timing dep qualified) + task vs taskless + 2000+strip preserved exactly (cbs + impersonation); anti-accumulation dead audit done.
│   │   └── relationship_service.dart # Bond/trust/fixation/spatial/inter-char relationship tracking
│   │   └── fact_extraction.dart # fact extraction + consolidation + quality gate (step 13); plain leaf after summary; cbs for llm/fire/strip/flag/persona/char/group/messages; full prompt/gate/LLM/JSON/consolidate in leaf; thins + cadence in god.
│   │   └── evolution_service.dart # character evolution (step 14); plain leaf after fact; owns trigger/extract/LLM/persist + effective layering + group per-char counts; thins for periodic/_trigger/manual/getEffective* in god ("thin delegation here; full character evolution in step 14"); 0 new god privs (stayed 15); stateless/prompt-only (no reset calls needed on leaf); dedicated test 15 bodies post del; aug only qualified passive exact; 1:1 vs group parity qualified; anti-accum; barrel not.
│   ├── cloud_providers/         # Implementations of cloud storage backends (Google Drive, OneDrive, WebDAV)
│   ├── grpc/                    # gRPC-generated code and services for external API integrations (e.g. Draw Things)
│   ├── chat_service.dart        # Core chat logic, context building, message streaming, Realism orchestration, _groupRealism map, post-gen wiring
│   ├── expression_classifier.dart # Legacy ExpressionClassifierService (ChangeNotifier) + low-level LLM/ONNX classifiers + Emotion* models. Still the home of core classifier impls; chat/ version delegates to it. Exported from services barrel.
│   ├── kobold_service.dart      # KoboldCpp API client
│   ├── llm_provider.dart        # Abstraction over Kobold/OpenRouter/external APIs
│   ├── character_repository.dart # Character CRUD via Drift
│   ├── storage_service.dart     # File system paths, beta/stable data dir isolation
│   ├── embedding_sidecar.dart   # Rust subprocess manager for ONNX embeddings
│   ├── memory_service.dart      # RAG memory extraction and retrieval
│   ├── tts_service.dart         # TTS orchestration (Kokoro, ElevenLabs, OpenAI, Piper)
│   ├── stt_service.dart         # Whisper STT via Python subprocess
│   ├── cloud_sync_service.dart  # Google Drive / WebDAV sync
│   ├── hardware_service.dart    # GPU detection, VRAM estimation
│   ├── backend_manager.dart     # KoboldCpp lifecycle (start/stop/restart)
│   ├── services.dart            # Curated high-frequency public barrel (see "Barrel files..." policy below; exports chat_service, llm_*, tts/stt, cloud_sync, character/group repos, etc. Note: does *not* re-export the chat/ domain leaves)
│   └── ... (40+ other top-level service files)
├── ui/
│   ├── chat_components/         # Componentized chat UI elements (refactored out of main pages/widgets)
│   │   ├── chat_components.dart # Main barrel for chat components
│   │   ├── bubbles/             # Chat bubbles (message bubbles, styled message content)
│   │   ├── overlays/            # Overlays (RAG setup, generation status, realism processing, check overlay)
│   │   ├── sidebar/             # Chat sidebar tab sections (memory, realism, chaos, nsfw, scene time, etc.)
│   │   └── widgets/             # Granular interactive chat buttons and pills
│   ├── layout/main_layout.dart  # Main shell with sidebar + content area
│   ├── pages/                   # Screen pages (chat_page, home_page, settings_page, character_creator_page, etc.)
│   ├── dialogs/                 # Modal dialogs
│   ├── theme/
│   │   └── app_colors.dart      # Central theme definitions and dark/light color resolution helpers
│   └── widgets/                 # Reusable layout widgets (inputs, cards, sliders, selector dropdowns, etc.)
└── utils/                       # Helpers (emotion_labels, vram_estimator, gguf_parser, etc.)
```

### Critical Services

- **ChatService** (`lib/services/chat_service.dart`): Orchestrates chat sessions, builds context windows, handles message streaming, Realism Engine evaluations + post-generation needs/climax/sexual/daily checks, _groupRealism map + load/save scalars for group per-char state, chip delta attachment, and all cross-service wiring/callbacks. (Stage 3 step 15 complete: remaining god refactored via audit + pure cleanup of orchestration/_groupRealism/core flows/builds/TTS/mood/swipe/restore/periodic+post thins/resets to thin coordinator shell + minimal god-owned state per plan; 0 new god private _ methods; live grep stayed exactly 15; see in-file step15 marker + docs/refactor-god-file-modularization.md Step 15).
- **NeedsSimulation** (`lib/services/chat/needs_simulation.dart`): Domain service owning Sims-style needs (hunger, bladder, energy, social, fun, hygiene, comfort) decay, post-climax arousal suppression/afterglow buffers, catastrophe narrative triggers, applyNeedsDeltas, applySceneImpact, computeNeedsDeltasWithReasons, and context helpers for injection. Pure class; all cross-state (group, time, arousal, enjoysLowHygiene) via callbacks.
- **NeedsImpactEvaluator** (`lib/services/chat/needs_impact_evaluator.dart`): Consolidated needs impact/eval layer (rich LLM "needs_impact" JSON + declarative Proposal A table + ordered modifiers pipeline for romance/stance/enjoys etc). Produces NeedsImpact and applies via sim. Plain class; god late final (after sim) + thins (_runPostGenNeedsChecks + 4 _check*); cbs for engine fire/strip/extract + cross services. 0 new god privs; aug passive only; reset hygiene (stateless); parity qualified.
- **ChaosModeService** (`lib/services/chat/chaos_mode_service.dart`): Domain service owning Chaos Mode pressure growth, Chance Time wheel random event selection, and custom event text prompt injection.
- **RelationshipService** (`lib/services/chat/relationship_service.dart`): Bond/trust/fixation/spatial stance/inter-character feelings. Extracted; scalars loaded/saved via group impersonation paths in ChatService.
- **ExpressionClassifier** (`lib/services/chat/expression_classifier.dart`): ONNX + LLM emotion classification and reclassification (inertia, manual overrides, avatar selection). Extracted with many granular callbacks.
- **Prompt injection builders** (step 8): 8 files under `lib/services/chat/prompt_injection/` (author_note_builder, relationship_injection, emotion_injection, behavioral_injection, time_injection, nsfw_injection, chaos_injection, needs_injection). Plain classes; god wires late finals + thins with cbs for group/1:1 + service deps. Some injection text stayed thin in god per plan. 0 new god privates.
- **LlmEvalEngine** (step 9): `lib/services/chat/llm_eval_engine.dart` — _fireLLMEval (full streaming+retry+cancel+4000/0.1/no-reasoning), central _stripThinkBlocks (completed+unclosed), extractJson*, evaluateNeedsImpactCall. Plain class; god late final (after prompt_injection) + thins (0 @Dep); objective proposal coord + some mgmt stayed thin in god per plan for step9/11. 0 new god private _ methods beyond the required thin delegates (fire/strip/extract thins; void _ count grep stayed 15; +1 late final only; thins/calls/late final only per plan). The 5 realism eval calls + prompts moved to sibling realism_evals (step 10); objective proposal/gen/check moved to sibling objective_proposal (step 11); engine provides fire/strip/extract cbs to them. aug passive/qualified only; reset hygiene expanded (stateless; no calls needed). 1:1/group/oneShot parity qualified.
- **RealismEvals** (step 10): `lib/services/chat/realism_evals.dart` — owns the 5 realism evaluation calls (relationship, emotional state, physical state, narrative, one-shot) + their prompt builders, orchestration, parse for realism results (bond/trust deltas, emotion/arousal/fixation/spatial/time + pending metadata for chips/reasons) + side effects (apply on rel/nsfw, set emotion scalars, updateFixation, setObjective thin cb for autonomous, snapshot in oneShot). Plain leaf sibling to llm_eval_engine; depends on it for fire/strip/extract cbs (granular); some coordination stayed thin in god per precedent (qualify). god late final (after engine) + thins/delegates at *every* prior call site for the 5 (full excision); 0 @Dep shims; 0 new god private _ methods (thins as the public surface per plan; void _ count stays 15 confirmed live grep after every edit; +1 late final only). Stateless/prompt-only (no reset/seed/load owned; no reset calls needed); god reset "keep blocks in sync" comments expanded at *all* documented sites (full prior+current list + realism_evals (stateless or prompt-only; no reset calls needed) + "incomplete zeroing of secondary config on group/0-session/new-chat now complete"; both startNew branches explicit; cross-refs e.g. setActiveCharacter:1572). Dedicated test under test/services/chat/realism_evals_test.dart with factory for ctors (live closures over group maps + cbs for real dispatch without forcing god internals); 15-25+ test() bodies (via live grep -c '^\s*test(' confirmed post mandatory dead noop/placeholder/vestigial/factory-setup deletion *as part of task*). Coverage of public surface + roundtrips + group vs 1:1 via cbs + edges (guards, !ready, cancel, empty, error, "none", strip, impersonation/proposal parity, oneShot vs normal, Realism/Needs/Objectives parity 1:1 equivalent deltas, chips/sidebar/group per-char, no random, etc.). aug/integration tests (realism_engine_test etc.) receive *only* qualified passive notes in headers/comments — no leaf-specific logic edits ("aug exercising only passive/qualified (no realism-evals-specific aug file edits; full in dedicated + manual; qualified notes only in dedicated header + god + MD per precedent)"). 1:1 vs group + oneShot vs normal + Realism/Needs/Objectives parity 1:1 equivalent deltas/behavior at all times (dispatch preserved exactly via cbs + impersonation; strict one-shot parity for affected fields). Anti-accumulation: explicit dead code audit of affected methods in god (no new _*Eval/*Realism privates in god). Barrel not added (internal to ChatService; per "unless 3+ locations"). All per plan/CLAUDE/AGENTS (0 new god privs, deletion part of task, claims vs on-disk exact via live greps/gates/re-reads, gate hygiene with cd+abs+EXIT+literal raw in MD/summary, main pristine read-only, interactive manual smoke required pre-landing).
- **ObjectiveProposal** (step 11): `lib/services/chat/objective_proposal.dart` — owns the objective proposal path handling support (autonomous "none" vs value + dedup + autoGenerateTasks:true *only* for autonomous + correct target even under group impersonation via god's dance), generateObjectiveTasks (2000 + central strip cb for thinking models), _checkTaskCompletionInBackground (2000 + strip; task vs taskless) + closely related prompt/strip/parse inside. Plain leaf sibling to llm_eval_engine; depends on it for strip cb (fire/extract not used for these custom-budget paths); objective mgmt cbs (get/setActiveObjectives, setObjective, load/save/deact, tasksFor, isChecking, primary) stay thin/stayed in god per plan for step9/11 (qualify explicitly: "thin delegation here; full objective proposal in step 11"). god late final (after _realismEvals) + thins/delegates at *every* prior call site for generate + _check (full excision from engine + old thin bodies). 0 @Dep shims; 0 new god private _ methods (thins as public surface; void _ count stays 15 confirmed live grep after every edit + final; +1 late final only). Stateless/prompt-only (no owned reset/seed/load for objectives; no reset calls needed on leaf); god reset "keep blocks in sync" comments expanded at *all* ~15+ sites (full prior+current list + objective_proposal (stateless or prompt-only; no reset calls needed) + "incomplete zeroing of secondary config on group/0-session/new-chat now complete"; both startNew branches explicit; cross-refs e.g. setActiveCharacter:1572). Dedicated test under test/services/chat/objective_proposal_test.dart with factory (createTestObjectiveProposal) using live closures over group maps + cbs for real dispatch without forcing god internals; 15-25+ test() bodies (via live grep -c '^\s*test(' confirmed post mandatory dead noop/placeholder/vestigial/factory-setup deletion *as part of task*). aug/integration tests receive *only* qualified passive notes in headers/comments (exact: "aug exercising only passive/qualified (no objective-proposal-specific aug file edits; full in dedicated + manual; exercised via god thins generate/check ; qualified notes only in dedicated header + god + MD per precedent)"); no leaf-specific logic edits. 1:1 vs group + oneShot vs normal parity for proposed_objective "none" vs value + dedup + auto only for autonomous + correct target (even under impersonation); task vs taskless; 2000 + central strip. Dispatch preserved exactly via cbs + god's impersonation dance. Anti-accumulation: explicit dead code audit of affected in god (no new _Proposal/*Objective/Gen/Check/Task privates in god). Barrel not added (internal to ChatService; per "unless 3+ locations"). All per plan/CLAUDE/AGENTS (0 new god privs, deletion part of task, claims vs on-disk exact via live greps/gates/re-reads, gate hygiene with cd+abs+EXIT+literal raw in MD/summary, main pristine read-only, interactive manual smoke required pre-landing).
- **SummaryService** (step 12): `lib/services/chat/summary_service.dart` — owns the Chat Summary (periodic user-msg count driven background gen using active LLM + RAG grounding, prompt macros {{words}}/{{user}}/{{char}}, history cond, think+numbered analysis strip + trim, update+persist). Cadence/force/pause/paused/enabled/flag/scalars/save-load/reset thin/stayed in god per plan ("thin delegation here; full summary in step 12"). god late final (after _objectiveProposal) + thins/delegates at *every* prior call site for _generateSummaryInBackground / _maybeUpdateSummary / force (full excision). 0 @Dep shims; 0 new god priv _ methods (thins as public surface; void _ count stays 15 after every + final; +1 late final only). Stateless/prompt-only (no owned reset/seed/load for scalars; no reset calls needed on leaf); god reset comments expanded at *all* ~15+ sites (full list + summary_service (stateless or prompt-only; no reset calls needed) + "incomplete zeroing of secondary config on group/0-session/new-chat now complete"; both startNew explicit; cross-refs e.g. setActiveCharacter:1572). Dedicated test under test/services/chat/summary_service_test.dart with factory (createTestSummaryService) using live closures over group maps + cbs for real dispatch (no forcing god internals); 15 test() bodies (via live grep -c '^\s*test(' confirmed post mandatory dead noop/vestigial del as part of task). aug/integration tests receive *only* qualified passive notes (exact: "aug exercising only passive/qualified (no summary-specific aug file edits; full in dedicated + manual; exercised via god thins _maybeUpdateSummary/force/generate ; qualified notes only in dedicated header + god + MD per precedent)"); no leaf edits. 1:1 vs group parity for summary text/last/flag/force/pause/cadence + correct context names/RAG at trigger (cbs + god dance). Anti-accumulation: explicit dead audit in god (no new _Summary/*Summary privates); deletion of moved as part of task. Barrel not added (internal; per "unless 3+ locations"). All per plan/CLAUDE/AGENTS (0 new god privs, deletion part of, claims exact via live greps/gates/re-reads, gate hygiene cd+abs+EXIT+literal raw in MD/summary, main pristine read-only, interactive manual smoke 1:1+group required pre-landing).
- **FactExtraction** (step 13): `lib/services/chat/fact_extraction.dart` — owns the fact extraction + consolidation + quality gate (auto persona / learned facts: RP-aware prompt with universal timeless rules + char exclusion via cbs for current+group, stream early-break + strip + JSON/codeblock, _isValidFact length+garbage patterns+name reject, add with embed pass-through, cap→consolidate merge dense or truncate fallbacks). Flag/cadence/periodic/_maybe/_run thin in god per plan ("thin delegation here; full fact extraction in step 13"). god late final (after _summaryService) + thins at every prior (full excision); 0 @Dep; 0 new god priv _ (thins as public surface; void _ count stayed 15 after every + final; +1 late final only). Stateless/prompt-only (no owned reset for counter/flag; god zeros at ~15+ sites + "now complete" + both startNew explicit + cross-refs e.g. setActiveCharacter:1572). Dedicated test with factory (live cbs/group maps); 15 bodies post mandatory del as part of task. aug/integration receive *only* qualified passive notes (exact: "aug exercising only passive/qualified (no fact-extraction-specific aug file edits; full in dedicated + manual; exercised via god thins _maybeRunPeriodicEvals/_runPeriodicEvalsInSequence/_extractFactsInBackground ; qualified notes only in dedicated header + god + MD per precedent)"); no leaf edits. 1:1 vs group parity for rejection/prompt context qualified (dispatch via cbs; facts user-global). Anti-accumulation: explicit dead audit (no new _Fact privs in god); deletion of moved as part of task. Barrel not. Some coord thin in god per plan.
- **EvolutionService** (step 14): `lib/services/chat/evolution_service.dart` — owns the character evolution (trigger/extract/LLM for traits + persist via cb + effective personality/scenario layering with [Growth]/[Situation] blocks + group per-char counts + manual trigger + status/error during op). Periodic coordination / enabled / _maybe/_run / _trigger call sites / load/save of evolved maps / reset/zero of transients / public surface stay thin in god per plan ("thin delegation here; full character evolution in step 14"). god late final (after _factExtraction) + thins/delegates at *every* prior call site for trigger/manual/getEffective* (full excision); 0 @Dep shims; 0 new god priv _ methods (thins as public surface; void _ count stays 15 after every + final; +1 late final only). Stateless/prompt-only (no owned reset/seed/load for maps/flags/counts — god owns; no reset calls needed on leaf); god reset "keep blocks in sync" comments expanded at *all* ~15+ sites (full list + evolution_service (stateless or prompt-only; no reset calls needed) + "incomplete zeroing of secondary config on group/0-session/new-chat now complete"; both startNew explicit; cross-refs e.g. setActiveCharacter:1572). Dedicated test under test/services/chat/evolution_service_test.dart with factory (createTestEvolutionService) using live closures over group maps + cbs for real dispatch (no forcing god internals); 15 test() bodies (via live grep -c '^\s*test(' confirmed post mandatory dead noop/vestigial del as part of task). aug/integration tests receive *only* qualified passive notes (exact: "aug exercising only passive/qualified (no evolution-specific aug file edits; full in dedicated + manual; exercised via god thins _maybeRunPeriodicEvals/_runPeriodicEvalsInSequence/_triggerCharacterEvolution ; qualified notes only in dedicated header + god + MD per precedent)"); no leaf edits. 1:1 vs group parity for evolution (per-char counts, effective layering, trigger target under impersonation for group; dispatch preserved via cbs + god dance; timing qualified). Anti-accumulation: explicit dead audit in god (no new _Evol/*Evol/Evolution privates); deletion of moved as part of task. Barrel not added (internal; per "unless 3+ locations"). Some coord thin in god per plan.
- **KoboldService** (`lib/services/kobold_service.dart`): HTTP client for KoboldCpp API (`/api/v1/generate`, `/api/extras/abort`, etc.)
- **StorageService** (`lib/services/storage_service.dart`): Manages data directories. Beta builds use `FrontPorchAI-Beta/` with `beta_` prefixed SharedPreferences keys
- **EmbeddingSidecar** (`lib/services/embedding_sidecar.dart`): Manages the Rust `embed_server` subprocess for ONNX-based text embeddings (RAG memory)

### Python Sidecars

TTS and STT use Python subprocesses communicating via JSON over stdin/stdout:
- `kokoro_tts.py` — Kokoro TTS engine
- `whisper_stt.py` — Whisper speech-to-text
- `embed_server.py` — Fallback embedding server (Rust binary preferred)

Protocol: read JSON from stdin → process → write JSON result to stdout → errors to stderr with non-zero exit.

### Database

Drift ORM with SQLite. Schema in `lib/database/database.dart`. Run `dart run build_runner build` after schema changes to regenerate `database.g.dart`.

Key tables: `characters`, `chats`, `chat_messages`, `lorebooks`, `worlds`, `group_chats`, `story_projects`, `learned_facts`, `avatars`

**Important note on external tools**: At least one companion application (Character Card Forge at https://github.com/FrozenKangaroo/Character-Card-Forge) performs direct raw SQL `INSERT`/`UPDATE` operations into the database files (primarily `characters`, `sessions`, `messages`, `avatar_images`, and `sync_meta`). It is the first external tool with deep Front Porch integration, including emotion image export and initial Realism Engine state. Schema changes can break it.

### Realism Engine

A multi-component system spanning `chat_service.dart` (orchestration + _groupRealism + post-gen hooks + message metadata), the extracted domain services under `services/chat/`, and the LLM provider:
- Emotion tracking with inertia between turns (ExpressionClassifier)
- Bond/trust relationship scoring (bond clamped to ±300, arousal ±100) (RelationshipService)
- Deterministic time progression (advances every 6 turns) (still mostly in god; TimeService planned)
- Fixation engine (emotional obsessions)
- Character evolution (trait development)
- Chaos Mode ("Chance Time" random events handled via `ChaosModeService`)
- Sims-style Needs Simulation (decay, stepped descriptions, afterglow/lust-haze/post-climax-crash buffers, catastrophe narrative triggers, hygiene inversion for "enjoys low hygiene" handled via `NeedsSimulation`)
- Escape hatch: `cancelRealismEval()` aborts in-flight evals via `_isCancellingRealismEval` flag + `abortGeneration()`

**Known gotcha**: GBNF grammar constraints cause many KoboldCPP models to return empty eval responses. Evals use stop sequences + regex parsing (no grammar). Remote APIs work fine without grammar.

**One-shot vs Normal Path Parity (strict)**: When `_storageService.realismOneShotEval` is true, `_evaluateOneShotCall` **must** produce 1:1 equivalent outputs for Bond/Trust/Emotion/Arousal/Fixation/Spatial Stance/Time/Needs deltas as the normal multi-call path (`_evaluateRelationshipCall` + `_evaluateEmotionalStateCall` + `_evaluatePhysicalStateCall` + `_evaluateNarrativeCall`). Differences in what gets evaluated or how deltas are computed between the two paths are bugs. The one-shot path exists purely for token/latency optimization — it must not change observable Realism or Needs behavior.

**Realism & Needs Parity (1:1 vs Group)**: The observable behavior (bond/trust deltas, emotion inertia, needs decay + scene rewards + buffers + catas, time advance every 6, climax refractory, etc.) must be identical whether the character is in a 1:1 chat or a group (per-speaker). Orchestration differs (scalar fields vs _groupRealism map + load/save + impersonation of _activeCharacter + speaker-specific preTurn for chips), but the simulation results and UI must not diverge. Any change touching these areas requires auditing both paths + the "keep reset blocks in sync" sites in chat_service.dart.

### Path Map for Tracing Realism/Needs/Group Post-Generation, Chips, Sidebar & Climax Checks

Because god-file modularization (Stage 3) moved core simulation into plain classes under `lib/services/chat/` while leaving orchestration, the _groupRealism map, message metadata, UI attachment, and cross-speaker coordination in the god (`chat_service.dart`), tracing bugs in post-turn effects, needs deltas, climax/sexual/daily verification, chip computation, or sidebar updates requires following a specific set of execution paths.

**We built/updated this map while diagnosing the double-climax-eval + group needs not persisting + wrong chips/sidebar bug (the one that required temp impersonation before _runPostGenNeedsChecks, the groupSpeakerPreDecayNeeds snapshot before tick, the post-gen _saveScalarsIntoGroupRealism, and the if(delta==0) skip in chips).**

Use this map the next time you see symptoms like:
- Needs chips or sidebar not updating / showing stale values after a turn (especially in groups)
- "Model output 0 for bladder" or other single-need anomalies in logs + chips
- Climax (or sexual/daily) LLM eval firing twice for the same response
- Group member needs not reflecting scene rewards (fun/social/hygiene from sex, eating, bathing) or decay
- Chips showing cross-character deltas or all "X 0"

**Core files & responsibilities (post-extraction state):**

- **God file orchestration + group state + pre/post wiring + chip attachment** (`lib/services/chat_service.dart` — the majority of the tracing surface):
  - Pre-turn capture (in sendMessage, before/around realism eval block): `preTurnVector`, `groupSpeakerPreDecayNeeds = _getGroupNeeds(sid from nextCharacter)` (before `tickDecay`), store in pending.
  - Group per-speaker pre-gen (called from _generateResponse after pickNext): `_evaluateRealismForUpcomingGroupSpeaker` does `_loadGroupRealismIntoScalars(charId)` (sets _needsSimulation vector + other scalars from map), captures local preTurnVector (post-decay), runs the relationship/emotion/etc. evals under impersonation, `_saveScalarsIntoGroupRealism` (for pre effects), puts realism_state (with embedded 'needs' vector + deltas-at-capture-time) + top-level needs_deltas=0s into _pendingRealismMetadata (stamped on the new ChatMessage at creation).
  - Post-gen finalization (late in _generateResponse, after tokens, before tts etc.): 
    - For group non-obs: temp re-set `_activeCharacter = speakingCharacter; _loadGroupRealismIntoScalars(...)` so the *checks* see the correct character for prompt text ("Did $charName reach climax...") and personality injection.
    - `await _runPostGenNeedsChecks(finalResponse)` — this is the central dispatcher: climax (if conditions), then sexual, daily, fulfillment. All three _check* methods contain the LLM _fireLLMEval + parse + applyNeedsDeltas (or set cooldown/crash).
    - `_needsSimulation.applyLongGenerationNeedsDecay(...)`
    - Then `_saveScalarsIntoGroupRealism(speaker from _messages.last.sender)` — **this is the critical persist that was missing**; without it scene deltas never made it into _groupRealism.
  - Chip delta computation/attach (right after await _generateResponse in the sendMessage caller, and similar in regen paths): the big `if (_needsSimEnabled && _messages.isNotEmpty)` block. For 1:1 uses the outer preTurnVector. For group uses the pre-decay snapshot (or fallback from the just-created msg's realism_state['needs']['vector']). Sets `activeMetadata['needs_deltas']` (what the bubble reads). Also the needs_pre_turn_vector for regen revert.
  - Group helpers you will hit constantly: `_groupRealism`, `_getGroupNeeds`/`_setGroupNeeds`, `_loadGroupRealismIntoScalars`/`_saveScalarsIntoGroupRealism`, `getNeedsForGroupCharacter`/`getTopUrgentNeedsForGroupCharacter` (used by UI), `_getCurrentSpeakerIdForRealism` (used by tickDecay group branch + cbs), `nextCharacter`.
  - The individual check methods also live here (until nsfw_service extraction in later step): _checkClimaxInResponse (the one with the refractory + llm hygiene/bladder deltas), _checkSexualActivityInResponse, _checkDailyActivityEffects (the one that consults enjoysLowHygiene and afterglow for bathe hygiene gain), _verifyNeedFulfillmentCall.
  - Pre-gen realism evals (the 5: rel/emotion/phys/narr/oneShot for bond/trust/emotion/arousal/fix/spatial/time) now thin-delegate to _realismEvals (step 10 leaf) which owns the prompt builders + parse + side effects; still orchestrated from god (sendMessage pre blocks, _evaluateRealismForUpcomingGroupSpeaker with impersonation for group per-speaker, post-greeting baseline, regen paths); god thins preserve the call names/signatures exactly. (See realism_evals.dart header + god thins + dedicated test for cbs/impersonation parity.)
  - Objective proposal (narr/oneShot proposed_objective "none" vs value + dedup + autoGenerateTasks:true only for autonomous + correct target even under group impersonation) + gen tasks + check completion now thin-delegate to _objectiveProposal (step 11 leaf) which owns the gen/check + internal prompt/strip/parse (2000 + central strip); god thins (generateObjectiveTasks, _checkTaskCompletionInBackground) + impersonation dance for target + objective mgmt (setObjective etc) stay thin/stayed in god per plan for step9/11 (qualify). Engine provides strip cb to the leaf. (See objective_proposal.dart header + god thins + dedicated test for cbs/impersonation parity.)
  - Summary (post-gen _maybeUpdateSummary thin + force + cadence per storage.summaryInterval + flag/paused/scalars/save-load/reset thin coord) now delegates generate to _summaryService (step 12 leaf) which owns the prompt/RAG/strip/update logic; god thins _generateSummaryInBackground etc + state stay thin per plan (qualify "thin delegation here; full summary in step 12"). (See summary_service.dart header + god thins + dedicated test for cbs.)
  - Fact extraction (periodic via _maybeRunPeriodicEvals / _runPeriodicEvalsInSequence thin + cadence counter/flag in god; full extract/consolidate/gate/prompt/LLM in fact_extraction step 13 leaf) exercised post-gen; user-global facts but chat-specific rejection of current+group char names (via cbs, must be identical 1:1/group); timing qualified (post saveScalars, no impersonation dance needed for facts). (See fact_extraction.dart header + god thins + dedicated test for cbs.)
  - Character evolution (periodic via _maybeRunPeriodicEvals / _runPeriodicEvalsInSequence thin + unified cadence in god; full trigger/extract/LLM/persist/layering + group per-char target via cbs/impersonation in evolution_service step 14 leaf) exercised post-gen; per-char counts + effective layering must be 1:1/group parity; timing qualified (post save for context). (See evolution_service.dart header + god thins + dedicated test for cbs.)
  - Reset sites (there are many documented "keep these in sync" comments listing needs/chaos/relationship/expression/time): startNew, setActiveGroup, loadLastSession, empty sessions, etc. All must call the corresponding reset on the extracted services + clear _groupRealism etc. (now also lists + summary_service (stateless or prompt-only; no reset calls needed) + fact_extraction (stateless or prompt-only; no reset calls needed) + evolution_service (stateless or prompt-only; no reset calls needed)).

- **Domain simulation (no ChangeNotifier, callback-driven, testable in isolation)** (`lib/services/chat/needs_simulation.dart`):
  - `applyNeedsDeltas(Map, {fromSexualActivity})` — the source of the "[Realism:Needs] Applied deltas: {...}" and afterglow buffer logs. Clamps, triggers afterglow if high positive impact from sexual, calls onSaveChat + onNotify.
  - `applySceneImpact(NeedsImpact)` — entry for consolidated impact (deltas + startAfterglow + crash + fulfillments).
  - `computeNeedsDeltasWithReasons(preTurn)` — exactly what feeds the chips (and the 'deltas' inside realism_state['needs']). Compares pre vs current _vector, chooses reason (Afterglow buffer, Post-orgasm exhaustion, Natural decay, Stable, Scene action...).
  - `tickDecay()` — has the explicit group vs 1:1 branch: `if (getIsGroupNonObserverMode()) { sid = getCurrentSpeakerIdForRealism(); needs = getGroupNeeds(sid); mutate the map copy; setGroupNeeds; return; } else { full scalar + catas + enjoys mutation + buffers tickdown }`.
  - Buffers and state: afterglowTurnsRemaining, postClimaxCrash, arousalSuppression, pendingCatastrophe, vector.
  - Fresh start: `initializeFresh()` (all 100) vs legacy 80s.
  - Context helpers (getInjectionEffectiveStep etc) for injection delegation.
- **Needs impact / eval (consolidated)** (`lib/services/chat/needs_impact_evaluator.dart`):
  - `evaluateAndApply(responseText)` — the single post-gen entry (via god thin). Builds rich prompt (via engine), parses, table base + modifiers (romance A first for energy/hunger/hygiene), produces NeedsImpact, applySceneImpact + onClimax cb.
  - activityEffects table (Proposal A tuned).
  - Modifiers pipeline (romance context, enjoys, explicit mess/stance, etc).
  - Callbacks (passed at construction in ChatService): getTimeOfDay, getIsGroupNonObserverMode, getCurrentSpeakerIdForRealism, getGroupNeeds/setGroupNeeds, getEnjoysLowHygiene, getNeedsSimEnabled, setArousalLevel, etc. This is how it stays decoupled from the god and from group vs 1:1.

- **Display consumers (chips + sidebar + cards)**:
  - Verifier (new leaf realism_verification.dart): called from inside realism_evals (after each of 5 fire+strip) and needs_impact_evaluator (after impact fire+strip) with full latent bundle (prompt, injections, pre scalars+vector from capture/preTurn/group pre-decay, messages, char+frontPorch, group, kind, raw, strictness, max). On active, sets isVerifyingRealism + pass/max (god cb) for overlay "🕵️ Verifying Realism output (pass X/Y)" reuse of same widget; returns accepted/corrected for effective text/deltas + metadata map attached to pending (and stamped on ChatMessage) for bubble chip in _buildRealismIndicator (status + passes using existing row/chip style). 1:1/group/oneShot parity via cbs + god dance. Stateless/prompt+rule; no reset calls; keep-sync lists updated at all sites + both startNew. (See dedicated test + qualified aug notes only.)

- **Display consumers (chips + sidebar + cards)**:
  - Per-message needs chips (the "Fun +7" "Bladder 0" row under AI messages): `lib/ui/chat_components/bubbles/message_bubble.dart` in `_buildRealismIndicator`. Reads `metadata['needs_deltas']` (the map of need -> {delta, reason}). The forEach now does `if (delta == 0) return;` before building a chip (prevents clutter; only changed needs appear in the dedicated second row). Falls back to single classic realism row when no needs movement.
  - Sidebar (the always-visible current levels + progress bars when Needs Simulation enabled): `lib/ui/chat_components/sidebar/realism_section.dart` (RealismSectionState, inside Consumer<ChatService>). Renders the list of needs with LinearProgressIndicator using `chat.needsVector` (1:1) or the group getters. Also contains the master toggle and the per-char enjoys low hygiene in some contexts.
  - Group member cards (the rich cards in the member list or when focusing a speaker in group): `lib/ui/widgets/group_member_card.dart`. Calls `chat.getNeedsForGroupCharacter(...)` then `NeedsGrid(needs: needs...)`.
  - The actual bar/grid widgets: `lib/ui/widgets/needs_bar.dart` (NeedsBar for single, NeedsGrid for the 2-col layout used in cards).

- **Other related surfaces**:
  - Regen/swipe/timeline: the preTurnNeeds restore from 'needs_pre_turn_vector' or realism_state, then re-compute deltas after the re-_generateResponse.
  - "Enjoys low hygiene" static pref: CharacterCard.frontPorchExtensions, defaultMemberRealismState JSON perChar in group settings/creation, read by getEnjoysLowHygiene cb (used in daily bathe hygieneGain and some needs prompts).
  - The _runPostGenNeedsChecks (thin delegate to _needsImpactEvaluator) + the 4 _check* thins are the current home of the (now consolidated) LLM "did they do X" evals that produce the needs side-effects. Full in needs_impact_evaluator (table + Proposal A modifiers).

**Tracing recipe (from the actual debug session)**:
1. Reproduce with logging on (the [Realism:Needs], [Realism:Climax], [Realism:RawEval] prints are your friends).
2. At the post-gen block in chat_service.dart, print the current _activeCharacter?.name and the speaker of the message being finalized.
3. Check whether _saveScalarsIntoGroupRealism was reached for the right sid (add a temp print if needed).
4. For chips: print what pre vector was passed to computeNeedsDeltasWithReasons and what the resulting map looks like.
5. For sidebar/group cards: after the turn, call getNeedsForGroupCharacter in a debug print or the REPL and compare to the scalar _needsSimulation.vector at that moment.
6. If in group, walk the load → (tick on map) → per-speaker load (which sets scalar) → gen → post apply (on scalar) → saveScalars (writes map) flow.
7. Remember the impersonation dance is only for the *checks* (so LLM prompts name the right character); the scalars are already the right speaker's when post runs.
8. For the consolidated needs impact (post rework): the _runPostGenNeedsChecks thin calls _needsImpactEvaluator.evaluateAndApply; look for "[Realism:Needs] Consolidated impact" and the engine "[Realism:Needs] Running consolidated impact eval (via engine)" logs. The table/modifiers are in the evaluator; Proposal A romance guards are there.

When you touch any of the above for a realism/needs/group change, you **must**:
- Keep the 1:1 and group paths producing equivalent observable deltas/behavior.
- Update this path map in CLAUDE.md if the tracing surface changes.
- Run the dead-code audit + the mandatory analyze/format/build gates.
- Consider whether the new logic belongs in a future extracted service or should stay in god coordination.

This section exists because these paths are the most common source of subtle "needs stopped working after refactor X" or "group vs 1:1 divergence" bugs. Keep it current.

(Post 2026-06 spaghetti thinning for needs impact authority: the post-gen needs_impact path (evaluator thin + god _runPostGenNeedsChecks thin + verifier) is now the primary diagnosis site for "model narrative vs. structured output vs. gates"; the approved plan thinned in favor of verified/corrected impact authority under the new per-char card flag while preserving all parity/reset/leaf rules. One-sentence update per plan; tracing surface for god orchestration/impersonation/_groupRealism unchanged. Also: _lastSceneReason in sim now properly zeroed on all reset paths + listed in god keep-sync + "incomplete zeroing... now complete" at every site + both startNew (per Past Issues to Avoid).)

**Step 15 (refactor remaining `ChatService`)**: Completed the final row in the Stage 3 extraction order (docs/refactoring-guide.md). Comprehensive audit + pure cleanup (no new god private _ methods; void _ count stayed exactly 15 live after every edit + final; thins + god-owned coordination only). Removed last vestigial/obsolete attributions in god briefing (e.g. stale "step 8 for full nsfw injection" for checks now in needs_impact_evaluator) + fix round cleaned remaining per-thin at _getNsfwCooldownInjection:7742 (3 vestigial phrases total cleaned). Added explicit step-15 completion marker in god documenting what stayed ( _groupRealism + scalar helpers, send/generate/load/save/build* orchestration, pick/eval dance + impersonation for group, post-gen _runPostGenNeedsChecks thin + periodic thins, TTS drain/buffer, mood decay, swipe/restore, _applyMoodDecay, observer/auto/call, all reset "keep blocks in sync" + "incomplete zeroing of secondary config on group/0-session/new-chat now complete" + both startNew + full 14 leaves list + god-owned). No heroic extraction (prefer pure cleanup + thin consistency per "smallest change" / "no proliferation" / count gate). 1:1/group parity, cbs dispatch, reset hygiene, anti-accum all preserved. aug/integration: only qualified passive notes (no step-15 aug edits). Tracing surface for this path map unchanged (god remains the orchestration + _groupRealism home). See god in-file marker, docs/refactor-god-file-modularization.md full Step 15 record (modeled on step 14), and refactoring-guide table. All "user cannot review" rules + gates + main pristine followed.

### Story Pipeline (Porch Stories)

`StoryPipelineService` is created via `ChangeNotifierProxyProvider2` in `main.dart`. The `update` function must NOT return the previous instance early — it must recreate the service with `llmProvider.activeService` each time so backend switches (Kobold ↔ OpenRouter/Nano-GPT) take effect.

## Branch Workflow

This project uses a branching model designed to keep rapid development moving while providing stable channels for maintenance and release stabilization:

### Rawhide (Primary Development Branch)
- `Rawhide` is the main rolling development branch.
- **All new features, UI changes, major refactors, and experimental work must target Rawhide.**
- Rawhide is always moving forward. It represents the current state of ongoing development.

### dev (Current Stable Maintenance)
- `dev` is used exclusively for **bug fixes** targeting the current stable release.
- When no beta branch is active, bug fixes for the latest released version should be submitted against `dev`.

### Beta Branches (Release Stabilization)
- Beta branches are named using the pattern `0.9.x-Beta` (e.g., `0.9.8-Beta`).
- A beta branch is created when we begin the stabilization process for an upcoming release.
- **While a beta branch is active, only bug fixes for that specific beta build are accepted on the beta branch.**
- New features are not permitted on active beta branches. Any feature work must be developed against Rawhide.
- Beta branches exist to polish and stabilize the next release without blocking forward progress on Rawhide.

### main (Stable Releases Only)
- `main` contains only final, tagged stable releases.
- Direct PRs to `main` are almost never accepted.

### Summary of Where Changes Should Target

| Change Type                    | Target Branch          |
|--------------------------------|------------------------|
| New features & experiments     | `Rawhide`              |
| Bug fixes for current stable   | `dev`                  |
| Bug fixes for active beta      | The active `*-Beta` branch |
| Release tagging                | `main`                 |

When a new release cycle begins, a beta branch is typically created from the current state of Rawhide. From that point on, Rawhide continues to receive new development, while the beta branch is reserved strictly for stabilization work. Once the stable release ships, ongoing maintenance for that version moves to `dev`.

This structure ensures Rawhide remains the fast-moving line for new work, while still providing focused stabilization periods before each release.

## Important Constraints

- Beta builds MUST isolate data: `FrontPorchAI-Beta/` directory, `beta_` prefixed SharedPreferences keys
- All AI processing is local/offline by default; cloud APIs (ElevenLabs, OpenRouter) are opt-in
- Character cards follow V2/V2.5 spec (PNG/JSON with embedded metadata)
- Drift database uses UUID primary keys for cloud sync merge compatibility

- **Database schema changes affecting external direct writers**: A community companion app (Character Card Forge) performs direct SQL writes into the database. Any schema modification that could break such tools (non-nullable new columns, removed/renamed columns, structural changes to `characters`/`sessions`/`avatar_images`/`sync_meta`) requires explicit maintainer approval before implementation. See the Database section and "Never touch without discussion" for details.

## Files Requiring Discussion Before Changes

### Never touch without discussion
- `database/migrations/` — schema changes require migration planning. **Do not introduce breaking changes to the database schema (especially columns or tables written to by external tools such as `characters`, `sessions`, `messages`, `avatar_images`, and `sync_meta`) without direct confirmation from the maintainer.** A companion tool (Character Card Forge) relies on direct raw SQL writes into these tables.
- `lib/main.dart` — core service initialization order is delicate
- `pubspec.yaml` — **do not edit unless directly instructed to do so**. The CI/CD pipeline is responsible for normalizing the release version. Local development should use a standard semver (e.g. `0.9.8+1`).
- `analysis_options.yaml` — linting rules
- `scripts/` — release/build scripts

### Sensitive areas (extra caution)
- Authentication and API key handling
- Database queries (performance implications)
- UI layout changes (affect all three desktop platforms)
- Network request patterns
- File system operations

### Require architecture review
- New services or major refactors
- State management changes
- External API integrations
- Performance-critical code paths

## Rules When the Human Cannot Review Code

Because the user has **no ability to read or evaluate Dart code**, the following rules are **non-negotiable** and take precedence over normal task execution:

- **You are the only line of defense.** You must act as a paranoid, hostile reviewer of your own output. Do not assume your changes are clean.
- **Deletion is part of the task, not optional.** Any time you implement or modify behavior, you **must** audit the files you touch for dead code, duplicate logic, or obsolete methods and delete them.
- **New private methods are expensive.** Before creating any new private method or helper, you **must first** check whether an existing method can be extended, generalized, or refactored. Creating new methods is a last resort.
- **Method proliferation is forbidden.** If you introduce more than **two** new private methods while completing a piece of work, you must stop and either consolidate existing logic or explicitly justify in your response why deletion was not possible.
- **Parallel implementations are banned** unless the user explicitly approves. Do not create separate code paths for 1:1 vs group chat, or old vs new systems, without first attempting to unify them.
- **Mandatory commands at the end of non-trivial work** (you must run these and report the results):
  - `flutter analyze --no-fatal-warnings --no-fatal-infos`
  - `dart fix --dry-run` (apply safe fixes where appropriate)
  - Grep/search for recently added methods to verify older similar methods are not now dead

- **UI consistency for creation wizards** (mandatory):
  - All "Create X" flows (character creator, group chat creator, world creator, etc.) must use the **same top-bar step indicator pattern** and linear step progression as `create_character_page.dart`.
  - Do not invent new side menus, tab bars, or free-jumping section lists for creation wizards. Use the horizontal step dots + labels + connecting lines in the AppBar, `AnimatedSwitcher` driven by a simple `_currentStep` int, and `_buildNavButtons` at the bottom of each step.
  - This prevents the painful inconsistency the user has repeatedly called out.

- **Compilation gate after any structural change or major refactor** (non-negotiable):
  - After any deletion of methods, large refactors, changes to `home_page.dart`, `main.dart`, service initialization, widget trees with many braces, or anything that touches build-time structure, you **must** run a full `flutter analyze` (and ideally `flutter build macos` or `flutter run -d macos` on the host) **before** claiming the task is complete.
  - "It looks good" or "the logic is correct" is not sufficient. If the app does not compile cleanly for the user on `flutter run`, the work is not done.
  - You are responsible for leaving the tree in a runnable state. Repeated "build failed with 20 errors, please fix" follow-ups are unacceptable. Run the build yourself as part of verification.

- **All widgets, dialogs, menus, toggles, cards, and surfaces must honor the AppColors system** (non-negotiable):
  - Use `AppColors` from `lib/ui/theme/app_colors.dart` exclusively for colors.
  - Prefer the helper methods: `AppColors.backgroundOf(context)`, `cardOf(context)`, `surfaceOf(context)`, `surfaceContainerOf(context)`, `textPrimary/Secondary/Tertiary(context)`, `iconPrimary/Secondary(context)`, `borderOf(context)`.
  - Use `AppColors.resolve(context, darkColor, lightColor)` for any custom accent or state colors.
  - Hard-coded `Color(0xFF...)` values or raw `Colors.whiteXX` / `Colors.blackXX` are forbidden in new or refactored UI (except for a small number of semantic accent constants that already have light variants defined in AppColors).
  - This rule applies especially to creation wizards, settings dialogs, menus, and any new widget.

- **Destructive git operations on files are forbidden without explicit approval** (data loss risk):
  - You **must never** run `git checkout -- <file>`, `git restore <file>`, `git checkout HEAD -- <file>`, `git checkout <commit> -- <file>`, or any similar command that discards uncommitted local changes to a file.
  - Work is frequently done to files (by the human or other agents) without immediate commits. These commands will **silently and permanently destroy** that uncommitted work.
  - Such operations are only allowed if the human has **explicitly authorized the exact command in the current conversation** (e.g., "yes, run `git checkout -- lib/ui/pages/home_page.dart` right now").
  - Safer alternatives you must prefer: `git diff`, `git diff -- <file>`, saving a patch with `git diff > /tmp/backup.patch`, asking the user for help, using `git stash push -m "temp" -- <file>` only when the user has confirmed it is safe, or simply working around the problem without reverting the file.
  - If you ever believe a file is in a bad state and the only recovery seems to be a destructive checkout, **stop** and ask the user instead of acting. Data loss from an AI agent is unacceptable.

**Hygiene Summary Requirement**: At the end of any response involving non-trivial changes, include a short "Hygiene Summary" covering:
- New private methods added (list them)
- Methods deleted (list them)
- Whether `flutter analyze` is clean
- Any duplication or dead code you chose not to remove and why

## Code Style & Conventions

### Code File Size Limits & Single Responsibility Principle

To prevent the creation of massive "God files" (historically, some `.dart` files exceeded 9,000 lines of code), the following strict constraints must be followed:
- **Do One Thing and Do It Well**: Adhere to the Single Responsibility Principle. Every class, widget, or service must have exactly one primary purpose. Extract complex sub-domains (e.g., Needs simulation, Chaos Mode, specific calculations, or complex widgets) into distinct, focused classes or files rather than piling them into existing god files.
- **Strict File Size Cap**: Every Dart source code file (excluding auto-generated code like `.g.dart` or third-party packages) **must be kept under 500 lines of code (LOC)**.
- **Action on Existing Files**: If modifying an existing file that exceeds 500 LOC (such as `chat_service.dart`), you should not grow it further. Focus on extracting cohesive chunks of logic into new, specialized classes under 500 lines, ensuring any new logic and its adjacent functions do one thing and do it well.

### Reuse Existing Code
- **Prefer existing variables and scaffolds** — do not add new complexity when not necessary
- **Utilize existing functions whenever possible** — reuse patterns that already work
- **Avoid over-engineering** — simpler solutions are better when they achieve the same goal
- **Leverage shared state** (e.g., `StorageService`) as the single source of truth
- **Consolidate before extending**: When modifying complex areas (especially Realism Engine, Needs simulation, or group chat logic), first attempt to generalize or extend existing methods rather than creating new ones. Creating parallel helpers for similar functionality is not acceptable.

### Verification
- **ALWAYS run `flutter analyze` after making code changes** — the project is now at literal 0 warnings on the active rule set. New code must not introduce any warnings (CI will catch them on changed files in PRs). Never claim changes are "verified" without running it. Variables declared inside `try` blocks are not accessible outside — declare them before the `try` with default values instead.
- **Cross-platform verification is mandatory**. Front Porch AI is a Windows + macOS + Linux desktop app. Every non-trivial change must be checked (or have an explicit plan) to ensure it does not regress on any of the three platforms. This is especially true for file paths, process spawning, Python sidecars, and anything touching `dart:io` or native binaries.
- **Realism & Needs parity is mandatory** (see the dedicated section below). Any change to the Realism Engine or Needs simulation must keep 1:1 and group chat behavior consistent unless explicitly approved otherwise.
- **Because the user cannot review code**, you must treat every change as if it will be accepted without scrutiny. This means you are responsible for leaving the codebase strictly cleaner (or at minimum no worse) than you found it.

### Task Completion Rules
- **No skeleton or partial implementations are allowed.** Never create stub files, placeholder methods containing only TODO comments, incomplete classes, or "skeleton" functionality with the intention of finishing it in a later turn.
- **All tasks must be completed in full during the turn they are started.** If a request (or sub-task) cannot be fully implemented, tested via `flutter analyze` (0 errors on changed files), grepped for dead code, **the app actually compiles and launches** (`flutter run -d macos` or equivalent succeeds with no red exceptions at startup), and manually verified as working within a single interaction, do not begin writing the code. Ask the user to clarify scope or break the work into smaller, independently completable pieces instead.
- This rule takes precedence over "getting something started." Partial progress that leaves the codebase in a broken or misleading state is not acceptable.
- Only mark a task complete after it is fully functional and all verification steps (analyze + grep + manual review) have passed.

**Mandatory Cleanup Requirements (especially when the user cannot review code):**
- You **must** delete any code that is no longer reachable or needed as part of completing the task.
- You **must** consolidate duplicate or near-duplicate logic instead of leaving parallel implementations.
- You **must** remove any new private methods that became dead or obsolete during the work.
- "It works" is not sufficient. The codebase must be measurably cleaner (or at least not worse) than when you started the task.

### Realism & Needs System Parity
- The Realism Engine (Bond/Trust/Emotion/Arousal/Fixation) and especially the **Needs/Sims simulation** must maintain full functional parity between single-character (1:1) chats and group chats at all times.
- Any fix, refactor, behavioral change, new feature, or tuning to realism or needs logic **must** be implemented so that both modes receive equivalent treatment, unless the change is explicitly discussed with the user and approved as group-only or 1:1-only.
- Core simulation logic (decay rules, step thresholds, catastrophe text, erotic buffers, etc.) is intentionally shared. When editing these areas, you are responsible for ensuring group per-character behavior does not regress or diverge unintentionally.
- Storage and per-turn orchestration already use branching (`_groupRealism` vs scalar fields, group vs 1:1 paths in `_tickNeedsDecay` and `_getNeedsInjection`). Changes to orchestration are allowed to differ, but the *observable simulation behavior* for a character should feel consistent whether they are in a 1:1 chat or a group.
- When in doubt, default to keeping the two modes in parity. Breaking parity without discussion is considered a regression.

**Anti-Accumulation Rules for Realism/Needs (Critical):**
- Because this area has historically been the largest source of dead code and duplicated helpers, any work touching realism, needs, bond, trust, emotion, fixation, group state, or time progression **requires** an explicit dead code audit of the affected methods in `chat_service.dart`.
- You must actively look for and delete older helper methods (`_getGroup*`, `_loadEvolved*`, `_apply*Decay`, narrative injection variants, etc.) that are made obsolete by new logic.
- Creating new private methods with "Group", "Needs", "Realism", or "Decay" in the name triggers an automatic requirement to review and justify why similar existing methods could not be reused or deleted.

### Cross-Platform Compatibility (Critical)
- **Never hardcode Unix paths** (`/tmp`, `/Users/`, `~/`, etc.). Always use `Directory.systemTemp`, `getApplicationDocumentsDirectory()`, `StorageService.rootPath`, or `path_provider` + `package:path/path.dart` with `p.join()`.
- **Python sidecars** (`kokoro_tts.py`, `whisper_stt.py`, `piper_entry.py`, etc.):
  - Spawning must handle `python` vs `python3` (and ideally `py` launcher on Windows).
  - Use `;` vs `:` for `PYTHONPATH` / `PATH`.
  - Handle `HOME` (Unix) vs `USERPROFILE` (Windows).
  - Prefer PyInstaller one-dir bundles (`.exe` on Windows, executable on Unix) when available; fall back to raw `python + .py` only in dev.
- **Process management**: Use `Process.start(..., includeParentEnvironment: true)` and be prepared for `process.kill()` behavior differences (Unix SIGTERM vs Windows TerminateProcess).
- **Before marking any task "done"**, the responsible agent must either:
  1. Run the affected feature on at least two platforms, or
  2. Explicitly document the platform-specific limitation + mitigation.
- See also the **Task Completion Rules** section above — no skeletons or partial implementations are ever acceptable.

### Dart conventions
- Follow `flutter_lints` rules (see `analysis_options.yaml`)
- camelCase for variables/methods, PascalCase for classes
- Prefix private members with `_`
- Prefer `final` over `var`
- One class per file (except small related classes)
- snake_case for file names
- Use barrel files (`models/models.dart`, `services/services.dart`, etc.) for new or refactored code to reduce import boilerplate (see "Barrel files and long-term import hygiene" section below)

### Import order
1. Dart SDK (`dart:*`)
2. Packages (`package:*`)
3. Local imports (`../`, `./`)

### Barrel files and long-term import hygiene (policy)
The project uses barrel files to reduce hundreds of repetitive intra-package imports:

- `package:front_porch_ai/models/models.dart`
- `package:front_porch_ai/utils/utils.dart`
- `package:front_porch_ai/services/services.dart` (curated — only the high-frequency public surface)
- `package:front_porch_ai/ui/widgets/widgets.dart`
- `package:front_porch_ai/ui/chat_components/chat_components.dart` (barrel for the componentized chat UI layer)

**Preferred style for new code and refactors** is to import the barrel(s) instead of many individual files.

Direct imports of single files remain legal forever and are the correct choice for internal-only or one-off modules (e.g., grpc generated code, kokoro worker pools, a single niche dialog).

**Long-term migration policy (opportunistic, no heroic PRs):**
- There is **no** dedicated "import cleanup" effort or "import month".
- When you open any file for a real reason (feature, bug, refactor), convert its imports to use barrels as part of the same change. This is low-friction because the file is already being touched.
- Small dedicated hygiene PRs (5–8 files max) are allowed at most once per month when convenient, but only when the mechanical verification surface is tiny.
- Mass automated find/replace across dozens of files is forbidden.
- Files that are rarely edited may stay on direct imports indefinitely — this is acceptable.

Because the human cannot review Dart code, all barrel-related changes rely on mechanical verification (`flutter analyze` clean, `dart fix`, import line counts, build) plus the project's existing Hygiene Summary requirement. Use the `/check` skill or a verification sub-agent for anything larger than a few files.

When you add a new service or model that will be used from 3+ locations and is not purely internal, add the export to the appropriate barrel in the same PR.

### Riverpod patterns (for new code)
- Use `AsyncNotifier` for async operations
- `ref.watch` for reactive dependencies, `ref.read` for one-time actions
- Proper error handling with `AsyncValue`

### Python sidecar protocol
- Read JSON from stdin → process → write JSON to stdout → errors to stderr with non-zero exit
- Always validate input JSON; catch all exceptions; exit non-zero on failure
- Never write errors to stdout (breaks JSON parsing)

### Error handling
- Never silently swallow errors; always log or surface to user
- Test error conditions explicitly
- Mock external dependencies in unit tests

## Testing Expectations

- Aim for **80%+ coverage** on new code
- Test error conditions and edge cases
- Mock external dependencies
- Test async operations properly

### Reviewing Sub-Agent / AI-Generated Work

When using sub-agents (via `spawn_subagent`) or other AI tooling to produce code changes:

- **Always perform a proper manual code review** of the actual changes before accepting the work.
- Do **not** rely solely on the sub-agent’s self-report or the fact that `flutter analyze` passes.
- Read the modified code, evaluate logic, edge cases, consistency with existing architecture and patterns, and potential regressions or side effects.
- Only mark tasks complete after personal verification of the implementation.
- Sub-agents must **never** produce skeleton code, stub files, or partial implementations. All work returned by a sub-agent must be fully complete and verified per the Task Completion Rules section.

## Commit Messages

Use the conventional commit prefix on the first line (`type(scope): short summary`), but **do not stop there**.

Commit messages must be written for a human who will read the git log months or years later. They should clearly explain:

- What the actual problem was
- Why it mattered (impact on users or developers)
- How it was fixed and why that approach was chosen
- Any important context, gotchas, or trade-offs

**Bad (too terse, unhelpful to humans):**
```
fix(lorebook): correct keyword matching regex to use proper word boundaries
```

**Good (clear and relatable):**
```
fix(lorebook): keyword triggers were completely dead even for single-word keys

The regex in _matchKeyword was written as RegExp(r'\b${key}\b') inside
a Dart raw string. Because raw strings don't interpolate ${}, it was
literally searching for the text "\bkey\b" (with literal backslashes)
instead of using word boundaries.

This meant no keyword-based lorebook entry would ever activate
(isTriggered stayed false), which is why the green dot in the sidebar
never lit up and nothing ever appeared in the Context Viewer — even
when the user typed the exact trigger word like "blorbo" or "ping".

Fixed by using explicit string concatenation instead of ${} inside
a raw string so the regex is actually built correctly.
```

Write like you're explaining the change to a teammate who wasn't in the room when it was made.

## Changelog Tracking

After making any code changes, append an entry to `.claude/changelog.md` with:
- Date (UTC)
- Files changed
- Brief reason for the change
- Commit hash (if committed)

This enables regression tracing — if a bug appears, the changelog shows exactly what changed and why.

## User-Facing Changelog for the Update Dialog (AI Agent Responsibility)

The in-app "Update Available" dialog now renders a non-technical "What's New" section (sourced from the GitHub release body, which the `UpdateService` already fetches). Users who never visit GitHub or Discord rely on this text to discover new features.

**As the AI agent, you are responsible for keeping this text current** (exactly like appending to `.claude/changelog.md`):

- When you complete user-visible work on the active branch (Rawhide, a beta branch, etc.), also update the friendly, non-technical summary.
- Target: short benefit-oriented bullets with emojis (e.g. "🎭 Character Expressions now support sidebar mode — try it in any 1:1 chat").
- Preferred source (strict rule):
  - One file per active branch, named **exactly** the same as the branch (case-sensitive): `docs/<BranchName>.md`
    - On `Rawhide` → edit `docs/Rawhide.md`
    - On the current beta branch (e.g. `0.9.8-Beta`) → edit `docs/0.9.8-Beta.md`
    - On `main` → edit `docs/main.md`
  - This exact naming is required because AI agents hallucinate filenames.
  - Or (alternative): prepare the exact markdown block and post it directly to the GitHub release via tools, or hand the human the precise text to paste.
- Never use raw commit messages, `.claude/changelog.md` contents, or technical PR lists — those are internal.
- `docs/release-notes.md` remains the long-form historical document; the per-branch `docs/<Branch>.md` files are the narrow, dialog-optimized source.
- When you cut or prepare a tagged release, ensure the friendly text for that version is present in the chosen source so it appears immediately in the dialog for users on older builds.

This responsibility is now part of the normal "task complete" checklist for any change that adds or improves end-user features.

## Community

- Discord: https://discord.gg/e4tET6rpdv

## Git Contributions

- You may optionally credit Grok as a co-author for AI-assisted changes using this trailer:
  ```
  Co-authored-by: Grok <grok@x.ai>
  ```
- Never amend or rewrite commits from other authors
- This file (CLAUDE.md) is intended to be committed to the repository so that contributors and their AI agents can follow the project's coding and contribution guidelines.
