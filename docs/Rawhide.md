# Rawhide — What's New (Nightlies)

These notes feed the in-app "Update Available" dialog for Rawhide / cutting-edge builds.

## Recent improvements

- ⚡ **Faster KoboldCpp responses** — KoboldCpp has a built-in FIFO task scheduler that can batch multiple requests. The previous code used sequential `await` chains for realism evals and `waitForIdle()` before each eval, defeating KoboldCpp's built-in batching. Changed all 4 realism eval calls (relationship, emotional state, physical state, narrative) from sequential `await` to concurrent `Future.wait()`, and removed the `waitForIdle()` call before each eval. This improves chat response times by allowing KoboldCpp to batch multiple eval requests.

- 📺 **Token throttle defaults to OFF** — The "Smooth Output Buffer" (token throttle) now defaults to OFF for all users — new and existing. Existing stored preference is deleted on startup so users get the full speed. Tokens display at raw GPU speed instead of artificially slowed down. Users can re-enable via UI if they prefer the smoother display.

- 🧠 **Needs simulation fixes** — Three fixes for the Needs system:
  - **Needs reset on message delete** — Deleting a character message now properly restores the needs state from the previous message, not just the last message. Previously deleting a non-last character message would leave needs at their current (post-turn) values instead of rolling back.
  - **Hygiene no longer raises during sex** — Orgasm/sexual activity now properly lowers hygiene instead of potentially raising it. The daily activity check could incorrectly detect "bathing" during sex scenes and add +25 hygiene, overriding the -6 from climax. Fixed by gating the daily activity check behind cooldown and increasing the climax hygiene penalty.
  - **Needs chips show on regenerated messages** — Needs change chips now display when regenerating messages, not just on new messages. The needs_deltas were computed before `_generateResponse` ran, meaning the post-generation checks hadn't modified the needs vector yet. Moved the computation to after generation so chips show the actual delta.

