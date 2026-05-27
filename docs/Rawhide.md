# Rawhide — What's New (Nightlies)

These notes feed the in-app "Update Available" dialog for Rawhide / cutting-edge builds.

## Recent improvements

- 📚 **Baked-in Lorebooks now export correctly in character PNGs** — The "Lorebook" tab in the character editor (the keyword-triggered world info entries that travel with the card) is now properly included when you Export PNG from the grid or via the browser UI. Previously the web export path and an avatar-replacement code path silently dropped the `character_book` data, so imported cards in SillyTavern, Risu, Chub, etc. would be missing their embedded lore. Both desktop and web export paths now go through the canonical CharacterCard serializer and emit full ST-compatible lorebook entries (with keys, insertion_order, position, etc.). Round-trips are now reliable.

- 🧹 **Internal code hygiene improvements** — Began introducing barrel files (`models/models.dart`, `services/services.dart`, `utils/utils.dart`, `ui/widgets/widgets.dart`) to dramatically reduce the hundreds of repetitive import lines that had accumulated. New and refactored code now carries far less boilerplate. This is an ongoing, opportunistic cleanup (we convert files when we touch them for real work) rather than a single giant effort. No user-visible behavior changes; this makes future development faster and the codebase easier to maintain.

- ⚙️ **Auto-Configure for local models is now actually accurate** — The "Auto-Configure" button (in both the chat "Model" dialog and main Settings) finally produces GPU layer recommendations that make sense when you have a specific context size in mind. It now uses real model architecture data from the GGUF file (layer count, KV head dimensions) plus a proper binary search to find the highest number of layers that should safely fit your chosen context + KV quantization without OOMing. The old "ratio * 40" magic math and "100 MB per 1k context" guesswork are gone for the important path. Works dramatically better with the VRAM override for testing tight scenarios.

- 🔧 **Model Settings dialog cleanups** — The "Model" sheet (Model button in any chat) no longer shows a spurious API Key input when the 🍎 oMLX backend is active. The global "Request Reasoning" controls, the local "Thinking Model" switch, and the four hardware acceleration chips (Use Vulkan / ROCm / CuBLAS / Metal) have all been removed from this dialog. These advanced options remain available in the main app Settings and via .kcpps presets / Auto-Configure.

- 🧠 **Needs chips now survive app restart** — The Energy / Hunger / Hygiene / Bladder / etc. delta chips under the last AI message are now persisted the same way the classic Bond / Trust / Emotion chips have always been. Closing and reopening the app no longer wipes the needs row while leaving the realism chips intact.

- 🖋️ **Chat composer: live red spell underlines + stable custom coloring** — The message input now reliably shows both at the same time. Results are delivered live from a thin notifying wrapper around the desktop spell service (instead of only on context menu). The _StyledTextController applies the amber ("dialogue") / blue (*action*) colors plus the wavy underline decoration itself. Layout, height, resize handle, and keyboard behavior are unchanged. Right-click suggestions continue to work. Dead code from previous attempts cleaned up.

- 🧠 **Realism Engine speedup** — Removed duplicate code paths for KoboldCpp vs API backends. All realism evaluations (emotion, bond, trust, narrative) now run concurrently instead of sequentially, improving chat response times.


- 🍎 **oMLX backend support (macOS Apple Silicon)** — New backend option for local LLM inference via oMLX (https://github.com/jundot/omlx). Select oMLX in Settings → Backend, then use the model picker to choose from your loaded oMLX models. Also available as a per-chat model override in Chat Settings. Install oMLX via `brew install jundot/omlx/omlx` and run `omlx serve`.

- 🔧 **oMLX toggle in Chat Model Settings + compact buttons** — The "Model Settings" dialog (gear menu in any chat) now includes the 🍎 oMLX option on macOS, matching the main backend settings. Backend toggle buttons are also more compact (tighter padding and smaller text) to reclaim screen space.

- ⚡ **Faster KoboldCpp responses** — KoboldCpp has a built-in FIFO task scheduler that can batch multiple requests. The previous code used sequential `await` chains for realism evals and `waitForIdle()` before each eval, defeating KoboldCpp's built-in batching. Changed all 4 realism eval calls (relationship, emotional state, physical state, narrative) from sequential `await` to concurrent `Future.wait()`, and removed the `waitForIdle()` call before each eval. This improves chat response times by allowing KoboldCpp to batch multiple eval requests.

- 📺 **Token throttle defaults to OFF** — The "Smooth Output Buffer" (token throttle) now defaults to OFF for all users — new and existing. Existing stored preference is deleted on startup so users get the full speed. Tokens display at raw GPU speed instead of artificially slowed down. Users can re-enable via UI if they prefer the smoother display.

- 🧠 **Needs simulation fixes** — Three fixes for the Needs system:
  - **Needs reset on message delete** — Deleting a character message now properly restores the needs state from the previous message, not just the last message. Previously deleting a non-last character message would leave needs at their current (post-turn) values instead of rolling back.
  - **Hygiene no longer raises during sex** — Orgasm/sexual activity now properly lowers hygiene instead of potentially raising it. The daily activity check could incorrectly detect "bathing" during sex scenes and add +25 hygiene, overriding the -6 from climax. Fixed by gating the daily activity check behind cooldown and increasing the climax hygiene penalty.
  - **Needs chips show on regenerated messages** — Needs change chips now display when regenerating messages, not just on new messages. The needs_deltas were computed before `_generateResponse` ran, meaning the post-generation checks hadn't modified the needs vector yet. Moved the computation to after generation so chips show the actual delta.

- 🎯 **Objectives no longer bleed between chats** — Quest/objective goals were previously stored per-character, so objectives created in one chat would appear in another chat with the same character. Fixed by scoping objectives to the chat session (same mechanism used for messages). Each conversation now has its own independent set of objectives.

- 🎯 **Needs chips now render after regen** — Regenerating a message was stripping emotion_label from the metadata because the regen path never set it in `_pendingRealismMetadata` (the normal path does this after realism evals). Without emotion_label, the realism indicator early-return suppressed all chips. Fixed by adding the same `emotion_label` + `realism_state` synthesis into the regen path.

- 💬 **Needs tooltips now show per-need reasons** — The needs chip tooltip was showing "Intimate / sexual activity" for every need (even hunger) whenever afterglow or lust haze was active. Now each need gets its own reason: "Afterglow buffer" (hunger/energy/social), "Arousal suppression (lust haze)" (under lust haze), "Post-orgasm exhaustion" (post-climax crash), "Scene action" (positive delta), or "Natural decay" (default).

- 🧠 **Needs preserved during regeneration** — `_evaluateOneShotCall` was replacing `_pendingRealismMetadata` entirely with its own fields (bond_delta, trust_delta, etc.), wiping out `needs_pre_turn_vector` captured earlier in the same turn. This broke the delta computation on regenerated messages. Now the eval merges into the existing map instead of replacing it.

