# Realism Engine

The Realism Engine is Front Porch AI's system for tracking character relationships, emotions, and story progression across conversations.

---

## Table of Contents

1. [Overview](#overview)
2. [Enabling & Disabling](#enabling--disabling)
3. [Bond Tracking](#bond-tracking)
4. [Trust System](#trust-system)
5. [Emotion States](#emotion-states)
6. [Arousal System](#arousal-system)
7. [Passage of Time](#passage-of-time)
8. [Chaos Mode (Chance Time)](#chaos-mode-chance-time)
9. [Character Evolution](#character-evolution)
10. [Fixation Engine](#fixation-engine)
11. [NSFW Cooldown](#nsfw-cooldown)
12. [One-Shot Eval Mode](#one-shot-eval-mode)
13. [Sims/Needs Simulation](#simsneeds-simulation)
14. [Performance Considerations](#performance-considerations)
15. [Troubleshooting](#troubleshooting)

---

## Overview

The Realism Engine is Front Porch AI's signature feature for making AI characters feel like living, evolving people rather than scripted responders. Without it, conversations are stateless: every message is evaluated in isolation, relationships never deepen or fracture, emotions reset instantly, and the passage of time is ignored. Characters can say "I love you" one turn and treat you like a stranger the next.

**How it works (technical overview):**

After the AI generates a response (or immediately after a greeting), the Realism Engine runs a series of lightweight LLM "evaluation" calls (distinct from the main chat generation). These evals analyze the recent conversation history and update a rich internal state model stored per-chat session in the SQLite database (`sessions` table in `lib/database/database.dart`).

The core evaluation logic lives in `lib/services/chat_service.dart` (methods such as `_evaluateRelationshipCall`, `_evaluateEmotionalStateCall`, `_evaluatePhysicalStateCall`, `_evaluateNarrativeCall`, `_evaluateOneShotCall`, `_checkClimaxInResponse`, and `_applyMoodDecay`). A companion `lib/services/expression_classifier.dart` (via `LLMExpressionClassifier` and `ONNXExpressionClassifier`) helps map the nuanced emotions produced by the eval LLM into the 30 standard expression labels used for sprite/expression image matching.

Key tracked dimensions (all persisted and injected back into future prompts):

- **Bond** (short-term tension `-300`…`+300` and long-term bond `-300`…`+300`)
- **Trust** (`-100`…`+100`)
- **Emotion** (nuanced word + mild/moderate/strong intensity)
- **Arousal** (`-100`…`+100`) + NSFW refractory cooldown
- **Time of day** + day count (deterministic, advances every 6 turns unless the LLM vetoes)
- **Fixations** (intrusive persistent thoughts, 3-turn lifespan)
- **Spatial stance** (current physical posture/location)
- **Chaos pressure** (for Chance Time events)
- **Primary objectives** (quest-like goals)

These values are turned into rich OOC prompt injections (`_getRelationshipInjection`, `_getEmotionInjection`, `_getBehavioralMechanicsInjection`, `_getTimeInjection`, `_getTrustBehaviorInjection`, `_getNsfwCooldownInjection`) so the *next* generation respects the character's current emotional reality. The main character personality always takes precedence — realism only colors how that personality expresses itself.

**What you experience:**

- Characters remember how they *feel* about you. A single act of kindness can warm them for dozens of turns; a betrayal can poison the relationship for a long time.
- Emotions have **inertia** — they linger after intense moments instead of snapping back to neutral.
- The world has a sense of time and place. Lighting, atmosphere, and the character's physical position evolve naturally.
- Relationships feel earned. Short-term mood fluctuates quickly; long-term bond grows (or erodes) slowly from sustained patterns.
- Mature scenes have realistic pacing thanks to the arousal + cooldown system.
- Unpredictable drama via Chaos Mode ("Chance Time").

**It's completely optional.** The master toggle defaults to **off**. You can enable it globally, per-character (as a default for new chats), or manage it on a per-chat basis. When disabled, none of the extra LLM eval calls happen and chats behave like a traditional character AI.

---

## Enabling & Disabling

The Realism Engine can be controlled at three levels:

### 1. Global Default (Settings)

Go to **Settings → Realism Mode** (or search for "Realism" in the settings page).

- **Enable Realism Mode** (teal switch) — master toggle. When on, new chats inherit the sub-toggles below.
- **NSFW Cooldown** — tracks physical arousal and enforces a refractory period after intimate climaxes (highly recommended for mature RP).
- **Automatic Passage of Time** — lets in-universe time advance (dawn → morning → afternoon → evening → night) as you chat. Also enables spatial awareness even if the master time clock is off.

These defaults are stored in `StorageService` (`lib/services/storage_service.dart`) and applied to every new session unless overridden by a character card.

### 2. Per-Character Default (Character Editor / Creator)

When creating or editing a character (Manual Creator, AI Creator, or Edit Character page):

- Step 4 is the **Realism Engine** panel (powered by the shared `RealismFormSection` widget in `lib/ui/widgets/realism_form_section.dart`).
- Toggle "Enable Realism Engine" for this character.
- Set **initial state** for a new conversation:
  - Time of day and day count
  - Short-term bond and long-term bond (`-300` to `+300`)
  - Trust level (`-100` to `+100`)
  - Starting emotion + intensity
  - Whether NSFW Cooldown and/or Chaos Mode start enabled
  - An optional initial "Current Task" (Primary Objective)

These values are saved inside the character's `extensions.front_porch.realism_engine` JSON (see `FrontPorchExtensions` in `lib/models/character_card.dart`). They only seed **brand-new** conversations — existing chats keep their own persisted session state.

### 3. Per-Chat / In-Session Controls

- Once a chat is running, the current realism state lives in the `sessions` row in the database and survives app restarts and swipes/regenerations.
- The master realism flag for the active session can be flipped at runtime via `ChatService.setRealismEnabled()` (exposed in UI through the global setting or chat-specific menus).
- **One-Shot Eval (Experimental)** toggle appears in the chat settings drawer (and is also available in Settings). It fuses multiple realism evals into a single LLM call for much faster processing at the cost of slightly lower accuracy on small models.
- Chaos Mode and other sub-features can be toggled per-session via `setChaosModeEnabled`, `setNsfwCooldownEnabled`, and `setPassageOfTimeEnabled`.

**Tip:** Turning realism *on* mid-chat triggers a retroactive baseline eval (`_runRetroactiveBaselineEval`) against visible history so the engine catches up instantly.

---

## Bond Tracking

Bond is the heart of the relationship system and comes in two layers that evolve on very different timescales.

### Short-Term Bond (Tension)

- **Range:** `-300` (vitriolic hatred) to `+300` (utter devotion)
- **Tier names** (21 tiers, calculated in `_calculateTier`): Devoted / Enamored / Intimate / Close / Amiable / Friendly / Warm / Receptive / Neutral … all the way down to Vitriolic / Contempt / Disdain / Hostile / Adversarial / Broken Trust.
- Changes rapidly from the relationship eval (`_evaluateRelationshipCall` or the fused one-shot). The LLM is instructed to give small deltas (`±1`–`±5`) for normal interaction and only large deltas (`±10`–`±50`) for truly meaningful moments.
- **Inertia & decay:** Every 10 turns the short-term score drifts 1 point toward zero (`_applyMoodDecay`). This prevents relationships from being permanently stuck at extremes.
- **Effect on generation:** The `_getRelationshipInjection()` block tells the model exactly how open, warm, sarcastic, cold, or hostile the character currently feels. The character's core personality is never overridden — a naturally tsundere character at +200 bond will still be tsundere, just warmer and more vulnerable than usual.

### Long-Term Bond

- Same numeric range (`-300`…`+300`) and tier names (Soulmate / Life Partner / Deeply Attached … Fractured / Deep Resentment … Vitriolic).
- Grows (or shrinks) much more slowly via `_evalLongTermGrowth`, which is called periodically. Sustained high short-term tiers (≥7) cause +2 or +3 long-term points every few turns; sustained negative tiers erode it.
- Once earned, long-term bond is extremely sticky. A character with high long-term bond will retain underlying affection even during a short-term fight.
- Used in prompt guidance to describe "unbreakable commitment" or "deep-seated resentment that even positive short-term mood can't fully erase."

Both scores are shown in the message metadata chips (pink heart for bond deltas) when they change, and the current tier names appear in the relationship OOC note injected into every prompt.

---

## Trust System

Trust (`-100`…`+100`) is deliberately distinct from bond:

- **Bond** = "How does this character *feel* about me emotionally right now?"
- **Trust** = "How safe and reliable does this character judge me to be?"

Trust deltas come from the same relationship eval but are much more conservative (the LLM prompt heavily penalizes large swings except for extraordinary acts). Only the *user's* behavior moves trust — the character's own actions never do.

**Tier names** (via `trustTierName`):
- Positive: Blind Trust, Implicit Trust, Deeply Trusting, Confident Trust, Trusting, Leaning Positive, Cautious, Neutral…
- Negative: Guarded, Skeptical, Wary, Suspicious, Distrustful, Paranoid, Broken Trust, etc.

**Behavioral impact** (`_getTrustBehaviorInjection`):
- ≤ `-50`: Deeply distrustful/paranoid — questions every motive, evasive, assumes the worst.
- `-20` to `-5`: Skeptical/Guarded/Cautious — surface-level talk, tests intentions.
- `0`: Truly neutral (personality wins).
- `+30`–`+50`: Deep trust — mask is down, shares real feelings, vulnerability that is authentic to *this* character's personality.
- `+60`+: Rare "you are the only person I would ever tell this to" level.

**Trust Repair Window:** Any single-turn trust drop of `-20` or worse arms a special `_pendingTrustRepair` flag. On the *very next* user message the engine runs a dedicated trust-repair eval (`_runTrustRepairEval`) that scores how convincingly the user addressed the breach (0–60 recovery points). The character then reacts accordingly — a heartfelt, personality-appropriate apology can recover a lot; a glib "sorry" usually gets rejected.

Trust state is saved per session and restored on swipes/regens.

---

## Emotion States

Every turn (when realism is active) the engine runs an emotion evaluation (`_evaluateEmotionalStateCall` or fused in one-shot) that produces:

- A **nuanced emotion word** (never generic "happy" — the prompt demands "wistful", "flustered", "prickly", "smoldering", "guarded", "starstruck", etc., filtered through the character's personality)
- An **intensity** (`mild` / `moderate` / `strong`)

**Emotion inertia** is explicitly encouraged in the prompt: minor exchanges cause only small drift; after fights, confessions, or intimate moments the emotion is allowed (and instructed) to linger for several turns.

The current emotion is injected via `_getEmotionInjection()` so the model colors tone, body language, and word choice appropriately.

**Expression images / sprites:** When the Expression feature is also enabled, the Realism Engine's nuanced emotion is mapped to one of the 30 standard go-emotions labels (`lib/utils/emotion_labels.dart`) using `EmotionLabels.nuancedToStandard`. If the word isn't in the map, `LLMExpressionClassifier` (in `expression_classifier.dart`) triggers a quick reclassification call to pick the closest standard label. This drives the correct animated portrait.

Emotions are persisted in the session row (`characterEmotion`, `emotionIntensity`) and survive across messages, swipes, and app restarts.

---

## Arousal System

When **NSFW Cooldown** is enabled (a Realism sub-toggle), the engine tracks a separate physical arousal dimension (`-100`…`+100`).

- Arousal deltas are requested in the relationship/emotion/one-shot evals (with bold guidance: intimate moments should produce `+10` to `+25`).
- The value is **not** "progress toward orgasm" — it is current *desire and physical response*. The prompt explicitly tells the model: "High arousal = intensely turned on, NOT that they are about to climax."

**Arousal tier names** (via `arousalTierName`, 21 tiers from -10 to +10):
Completely Unaroused, Physically Neutral, Mildly Flustered … Heavily Aroused, Overwhelmed with Desire, Peak of Physical Arousal.

These descriptions (phrased for the specific tier) are injected into the prompt via `_getNsfwCooldownInjection()` so the model knows exactly how the character's body is reacting and how they would (or would not) escalate.

**Refractory Cooldown (the "NSFW Cooldown" feature):**

After the AI finishes a response, `_checkClimaxInResponse` runs a post-generation LLM call that scans the text for an organic climax. If one is detected:

1. The LLM is asked how many turns of refractory period this particular character would realistically need (personality-aware, 1–8 turns).
2. Arousal is slammed to `-3`.
3. `_cooldownTurnsRemaining` and `_cooldownTurnsTotal` are set.
4. Every subsequent turn the counter decrements (`_applyMoodDecay`).

While the counter > 0, the prompt injection describes the current recovery *phase* in vivid, non-mechanical language (oversensitive, blissfully wrecked, needing non-sexual closeness, etc.). The character will naturally reject or deflect further sexual escalation until recovered.

Climax state is stored in message metadata so swipes/regenerations can correctly restore or revert the cooldown.

When NSFW Cooldown is disabled, arousal tracking is still available for flavor but no refractory is enforced.

---

## Passage of Time

When **Automatic Passage of Time** is enabled:

- A simple deterministic clock runs: every AI turn increments `_turnsSinceLastTimeAdvance`.
- After **6 turns** (configurable constant `_turnsPerTimePeriod = 6`), the engine considers advancing the time of day.
- The LLM gets a "hold_time" + "new_day" + "posture" eval in `_evaluatePhysicalStateCall`. It can only **veto** the advance if the scene is visibly mid-action (fighting, actively doing something important). It cannot skip periods.
- At night → dawn it increments the day counter.
- Explicit "we slept / woke up / new day started" lines in the conversation can force a day rollover.
- The current time + narrative weekday (computed from session start day-of-week + elapsed days) is injected via `_getTimeInjection()` so the model describes appropriate lighting, atmosphere, fatigue, etc.

**When Passage of Time is disabled** but realism is still on, the physical-state eval still runs on a lighter cadence to keep **spatial awareness** (`_spatialStance`) updated — the character remembers "I'm sitting on the windowsill" or "we're standing in the rain" and the model is told to keep actions grounded.

Time state (`timeOfDay`, `dayCount`, `passageOfTimeEnabled`) is persisted per session.

---

## Chaos Mode (Chance Time)

Chaos Mode (also called "Chance Time") is an optional drama engine that injects unpredictable narrative events.

**How it works:**

- Every user turn, `checkAndTickChaosPressure()` runs (now works in regular group chats; disabled in Director Mode).
- Pressure starts at 0 and grows by **5** each turn (capped at 100).
- Effective trigger chance = `5% + current pressure`.
- When it fires, `sendMessage` pauses, a `Completer` is created, and the UI shows the Chance Time wheel overlay (`_chanceTimePendingTrigger`).
- The wheel calls `spinWheelEvents()` which samples 8 events from two pools:
  - `_chanceTimeEventPool` (~120 wholesome/fortune/mishap/drama events)
  - `_chanceTimeNsfwPool` (only if the 🌶️ "Include NSFW events" toggle is on)
- User spins, lands on one, and calls `applyChanceTimeResult(event, charName)`.
- The chosen event is stored as `_pendingChaosInjection` and injected at the very end of the next prompt (`_getChanceTimeInjection`) with strong instructions: the character **must** react to it in their first paragraph.
- The injection is cleared after use but the "delivered" flag ensures it survives one regen/swipe cycle.

Pressure resets to 0 after an event fires. You can also manually trigger the wheel from the UI when the mode is active.

Events are written so they feel like natural story beats ("{{char}} just received an extremely personal delivery in front of other people", "A stranger just paid for {{char}}'s meal…", etc.). The model is forbidden from mentioning "Chance Time" or game mechanics.

Chaos state (`chaosModeEnabled`, `chaosNsfwEnabled`, `chaosPressure`) is saved per session.

---

## Character Evolution

Character Evolution is a *periodic* companion system (not per-turn) that lets characters grow and change over long conversations. It is controlled separately in Settings ("Character Evolution") but is frequently used together with the Realism Engine.

- Every N user messages (default 10, same interval as auto-persona fact extraction) the engine runs `_runPeriodicEvalsInSequence`.
- Step 2: `_triggerCharacterEvolution` sends a background LLM call that proposes personality and/or scenario updates based on everything that has happened.
- The evolved text is stored per-character (or per-character-in-group) in the session and merged into future system prompts.
- Evolution count is tracked and shown in the character summary.
- Changes are **permanent for that chat** (they live in the `evolvedPersonality` / `evolvedScenario` columns and the group maps).

You can enable/disable it independently of Realism. When both are on, the evolving personality interacts beautifully with the emotional state tracking.

---

## Fixation Engine

The Fixation Engine gives characters *lingering obsessions* — thoughts that won't leave them alone.

- During the narrative / one-shot eval (`_evaluateNarrativeCall` or `_evaluateOneShotCall`), the LLM can propose a `"fixation_topic"` — something emotionally charged that the character keeps returning to (a hope, worry, memory, ambition, regret…).
- If the topic is new and non-"none", it becomes `_activeFixation` and `_fixationLifespan` is set to **3**.
- Every subsequent turn the lifespan decrements. When it hits 0 the fixation is cleared.
- While active, `_getBehavioralMechanicsInjection` adds a gentle OOC note: the character has this intrusive thought; it may color their mood or surface if the conversation naturally touches the topic. It never overrides their current focus.

Fixations make characters feel like they have an inner life that continues between scenes. They are especially powerful when combined with long-running story arcs or Chaos events.

---

## NSFW Cooldown

Covered in detail in the Arousal System section above. In short:

- When enabled, arousal is tracked and a personality-aware refractory period (1–8 turns) is enforced after the LLM detects a natural climax in the AI's response.
- During cooldown the prompt tells the model exactly how physically spent and oversensitive the character is, preventing unrealistic immediate re-escalation.
- The system is deliberately "show, don't tell" — the model never sees the words "cooldown" or "turns" in dialogue.

This is one of the most praised features for mature roleplay because it gives sex scenes realistic emotional and physical aftermath instead of endless escalation.

---

## One-Shot Eval Mode

By default the Realism Engine performs up to four separate LLM evaluation calls after each turn (relationship, emotional state, physical/time, narrative). On slower local backends (especially KoboldCPP) this can add noticeable latency.

**One-Shot Eval** (Settings → Realism or the toggle in the chat drawer) is an experimental optimization:

- When enabled, `ChatService` calls `_evaluateOneShotCall` instead.
- A single, carefully crafted prompt asks the model to return *all* the fields at once: relationship_delta, trust_delta, emotion, intensity, arousal_delta, posture, proposed_objective, fixation_topic, and reason.
- This cuts the number of pre-generation blocking inferences roughly in half.

**Trade-offs:**
- Slightly lower accuracy on very small models (< 8B) that struggle with long combined instructions.
- Still produces excellent results on 12B+ models.
- GBNF grammars are intentionally disabled for all realism evals (including one-shot) because many KoboldCPP setups return empty strings when a grammar cannot be satisfied — the engine falls back to regex parsing of the raw text, which is robust.

Most users leave it off for maximum fidelity and only enable it when they need maximum speed.

---

## Optional Realism Verification (Director/Verifier)

An optional per-character "director thread" that validates the JSON deltas and activities coming out of the Realism Engine and Needs simulation.

- **Toggle + tuning:** Right-click character → Edit → Details tab (or in the full character creator / edit page under Optional Features). "Realism Verification (Director/Verifier)" toggle (off by default for zero cost). When on, two sliders appear in the Details Optional Features block:
  - Max reprocess passes (1–5).
  - Verifier strictness (1–5; higher = stricter rules + "reject unless explicitly supported" tone in any reprocess prompt; 3 = Balanced).
- **What it receives:** The complete latent decision context the engine had at fire time — the exact prompt, every injected realism/needs/relationship/emotion/time/chaos/objective block, the pre-turn full scalars (bond/trust/arousal/emotion/fixation/spatial + complete needs vector), recent messages, the active speaker's CharacterCard (name + personality/scenario + current frontPorch values), group context if any, the specific eval kind + success criteria, and the raw model output.
- **Behavior:** Rule-based checks first (range using the authoritative kMin*/kMax* clamps — corrections are allowed to swing the full per-eval limit, e.g. relationship ±15). Logical/narrative consistency using the latent (no large hunger without eating in scene, arousal sign consistent with cooldown/text, inertia respect, time plausibility, activity+delta contradictions, etc.). Strictness modulates thresholds and reprocess prompt tone.
- **On pass:** Zero-overhead passthrough; generation continues.
- **On fail:** Explicit human-readable reason + a corrected delta bundle (within full clamps). If passes remain, the latent + critique + suggested correction is re-fed to the eval LLM for self-correction (reprocess). Max attempts bounded by the slider.
- **Visuals (non-negotiable):** While verifying/reprocessing, the existing Realism processing overlay (realism_processing_overlay + eval_pills + generation bar) shows header "🕵️ Verifying Realism output (pass X/Y)" with identical layout, colors, animation, and positioning — only the label changes. After the turn, the AI message bubble's realism indicator row (same area as needs chips / bond/trust/emotion pills) shows a small status chip: "✓ Director accepted" or "🕵️ Director corrected (N reprocesses)". Data comes from ChatMessage metadata['realism_verification'].
- **Cost:** Off = zero extra calls. On with max=1 + lenient = at most the normal evals + one fast rule pass (reprocess only on clear fail). Higher max/strict on weak models = visible extra passes in overlay + chip.
- **Parity:** 1:1 vs group, oneShot vs normal, Realism vs Needs all preserved exactly (dispatch via the same cbs + god impersonation dance; verifier always sees the correct speaker's card + pre-decay snapshot).
- **Recommendation:** Enable on strong models when you want higher fidelity "living character" deltas and are willing to pay the occasional extra eval. Defaults safe for old cards (off, 1 pass, balanced).

The implementation follows the same plain-leaf extraction pattern as the prior 14 realism/ chat domain services (realism_verification.dart <500 LOC, granular cbs, late final in god, thins at every call site, dedicated test with factory + 15+ bodies post dead deletion, aug tests only qualified passive notes, 0 new god void _ privates, keep-reset blocks expanded at all sites + both startNew with " + realism_verification (stateless or prompt-only; no reset calls needed)", AppColors for all UI, full gates + manual 1:1+group smoke).

---

## Diagnosis from the Director (real 1:1 log): Making Needs Simulation Usable and Correct — A Simpler Path

**The problem the Director exposed (human-readable case study from actual terminal logs, 1:1 chat):**

A complex physical scene with unambiguous acts: intense intercourse including internal creampie + the character actively urinating during the act. Pre-turn hints: low energy (~7), moderate bladder (~38). Needs Simulation + Realism + the new Director/Verifier were all enabled.

- The post-gen consolidated needs impact (via the thin `_runPostGenNeedsChecks` → evaluator) produced JSON the verifier repeatedly rejected across the full configured max passes (5).
- Repeated log: `[Realism:Verifier] Reprocess pass X/5 ... reason=model JSON claims sexual_climax but provides zero deltas (common weak output); applying expected post-climax effects`
- Final applied after all corrections + `applySceneImpact` / `applyNeedsDeltas`: small contradictory deltas such as bladder +2 (while actively urinating), hygiene only -2 (despite creampie + fluids + urine described), energy -2, hunger -1, social/fun small positives, comfort 0; `startAfterglow: false` yet "Post-climax crash set".
- User: "I disagree that these actions should give the delta's that were emmited however." and "I think the director/verifier is exposing a glaring issue with the needs sim. besides the fact the code is a tangled mess of if/then."

**Why so many if/then gates accumulated (plain English):**

The LLM is unreliable at the *structured* part even when the narrative it wrote is clear. Defenses layered on:

1. Prompt already has many rules ("ONLY unambiguous *act*", "pure romantic/sexual without explicit eat... energy/hunger neutral or small negative", "Hygiene negative *only* on explicit mess or high-int + exposed stance").
2. After model JSON: parse for flags (sexual_climax, ate, bathed...), look for `*_delta`, fall back to fixed "Proposal A" lookup table (if sexual_climax then fun +16 / social +9 / hygiene -18 / energy 0 / hunger -2 / start afterglow 4 / crash 3 scaled... and similar rows for non-climax sex / ate / slept / bathed).
3. Then 6+ ordered modifier passes: force energy/hunger zero/neg for pure sex/romance (no "replenish from intimacy"), zero hygiene unless explicit mess words *or* high int + exposed (bed/floor not shower), halve hygiene gains for "enjoys low hygiene", scale most deltas by intensity (not hunger/energy), arousal buffer damp, time-of-day light effects.
4. The result + explicit buffer flags handed to sim core (apply deltas, start afterglow/suppression/crash counters, fulfillments, later decay with afterglow halving / post-crash boosting / catas at 0 / enjoys inversion / cross-need boosts).
5. Separate logic picks chip "reason" strings ("Afterglow buffer", "Post-orgasm exhaustion", "Scene action", "Natural decay").
6. On top: the Director (full latent bundle + 5 reprocess + explicit correction suggestions) now also judges "is this impact reasonable for the text?" and supplies fixes or re-prompts.

Even with all that defense-in-depth, the numbers reaching chips/sidebar/injections were not what a human reading the model's own narrative would call correct or usable. The gates were fighting the story after the fact.

**Direct answer to "should we remove the gates and let the model 'take the wheel' or ...??"**

Largely yes for the *quantitative deltas and buffer recommendations*, under Director supervision + a small number of hard invariants (0-100 clamps, the mechanical decay/buffer/catas state machine in the sim core, the per-char "enjoys low hygiene" user preference, and a few "physically/narratively impossible" rules that stay visible in the Director reason).

The checks move primarily into one place (the Director with the rich bundle the user originally asked for) instead of being distributed across prompt + table + six Dart modifier fns + parse ifs + apply ifs + chip reason ifs whose interactions are hard to hold in your head on an unusual scene like the logged one. The reprocess loop is already the self-correction mechanism. The visible "🕵️ Director corrected (N)" chip (already wired for needs_impact via the shared metadata) now becomes a reliable signal that the numbers you see came from the Director's judgment of the actual scene text rather than an invisible chain of gates that partially cancelled.

**Concrete non-coder-actionable path (the control surface):**

- Same "Optional Features" block you already use for the three verifier controls (toggle + Max reprocess passes 1-5 + Strictness 1-5 / Strict-Balanced-Lenient).
- New (or re-used via strictness) per-char toggle/setting: "Director authority on needs deltas" (off by default — current conservative gated behavior unchanged for everyone who doesn't opt in; safe default for weak local models).
- When Director/Verifier is on *and* the new authority control is on for that speaker: the thin path in the evaluator trusts the (verified or reprocessed) model's `*_delta` keys + explicit `is_climax` / `recommend_afterglow` / `recommend_crash_turns` / `buffer_reason` / etc from the effective/corrected text, with higher precedence. The activityEffects table is demoted to advisory/fallback (only when verified output gives literally nothing usable after max passes). The 6 modifier methods become advisory or no-op under authority mode. Legacy full table + modifiers + intensity scaling path is kept *exactly* when the flag is off (or verifier off).
- Prompt lightly strengthened (still "ONLY unambiguous act", pure-romance guidance, hygiene-only-on-explicit-mess) but now also asks for net signed effects after the scene + explicit buffer recommendations, with language "the Director will correct you if you violate scene support."
- Needs sim lightly updated so chip reasons can prefer a Director/model supplied reason when present (better "why" text on the Fun +7 / Bladder 0 rows).
- All god orchestration, pre/post snapshots, group impersonation dance for per-speaker (correct scalars + correct _activeCharacter for prompt name/personality), _saveScalarsIntoGroupRealism, chip attachment from preTurn, regen/swipe/history restore, onClimax cb, "enjoys low hygiene", 1:1 vs group observable deltas, oneShot vs normal parity — *unchanged*. The authority mode only changes *which numbers* come out of the evaluator before those mechanisms apply/persist/restore/display them.
- When authority is off (or Director off): 100% identical behavior to before the change. No user is forced onto the thinner path.

**What this feels like day-to-day (the human non-coder benefit):**

- More "🕵️ Director corrected (N reprocesses)" chips with grounded reasons on complex scenes ("Director supplied post-climax hygiene and buffer corrections after model gave near-zero deltas despite clear creampie + fluids in scene").
- Chips and sidebar numbers more often match what a human reading the model's own narrative would expect (big hygiene hit + bladder relief + afterglow + crash + energy cost on low pre for the logged-style scene, instead of bladder +2 while peeing and hygiene -2 for a fluids-heavy act).
- Fewer surprising tiny or wrong-sign movements.
- Conservative gated behavior remains the safe, zero-surprise default when you leave Director off or the new authority toggle off.
- The same per-char Optional Features surface you already know; old cards default false (unchanged experience).

**Parity & safety guarantees (stated plainly):**

- 1:1 vs group per-speaker observable behavior (bond/trust/emotion/arousal/fixation deltas, needs deltas/buffers/fulfill/crash, chips, sidebar, injection) remains equivalent at all times. The god impersonation dance + load/save scalars + pre/post snapshots already handle this; authority just changes the proposed numbers upstream.
- Regen/swipe/history/"preTurn restore then re-apply" continue to produce coherent deltas (the preTurnNeeds vector and realism_state['needs'] snapshot paths are untouched).
- "Enjoys low hygiene" still affects final numbers and injection text exactly as today (when the legacy path is active; when authority is on the Director sees the pref via the card and can account for it in corrections).
- The decay, catastrophe, afterglow tick-down, and injection step/damp logic in the sim core are mechanics, not interpretation gates — they stay (and can become cleaner once upstream numbers are more trustworthy).
- All the existing "keep reset blocks in sync" + "incomplete zeroing of secondary config on group/0-session/new-chat now complete" sites (~15+ places + both startNew branches) were expanded to list the new flag as "card config like the 3 verifier fields; live frontPorch read under impersonation; no extra mutable god scalar or reset call needed".
- 0 new god private void _ methods (only thins + late final + comment hygiene; live grep stayed exactly at baseline 15 after every edit + final).
- Dedicated test (extended needs_impact_evaluator_test with factory using live cbs over group maps + authority + verifier) covers legacy unchanged, authority+verifier trusts corrected deltas/buffers and skips table/modifiers, group per-speaker, "none"/error/after-max-passes fallback, 1:1 vs group parity, chip reason preference, impersonation. 15-25+ test() bodies post mandatory dead/vestigial deletion as part of task. aug/integration tests received *only* the exact qualified passive note phrasing in headers (no leaf-specific logic edits).
- Full mechanical gates (analyze 0 new warnings on changed surfaces, format, dart fix, live greps for flag/void_/test counts vs on-disk, re-reads of abs paths with "0 open", build smoke) + manual interactive 1:1 + group smoke with authority on for complex physical scenes (creampie+fluids+urination style or equivalent multi-effect) + Director overlay + correction chips + chips/sidebar reflecting Director-supplied numbers.
- Barrel policy: no export (internal like most realism optionals; "unless used from 3+ locations").
- Cross-platform: no path/fs changes; StorageService / providers patterns followed where relevant (none needed here).
- File size: focused changes + virulent thinning of dead/vestigial/obsolete/duplicate (old god _check* comment attributions cleaned, obsolete "step N" phrasing, unused test helpers/comments, dupe logic comments) kept net growth small.

The Director is now the recommended lever for improving Needs fidelity on strong models. The verification path was already wired for needs_impact (corrected status/reasons already flow to the bubble chip via the shared kMetaKey); this change gives that wiring real authority instead of having its corrections fought or diluted downstream.

A companion 1x–5x "Needs delta strength" control (same Details → Optional Features block) lets the user tell both the first-pass needs eval prompt and the Director the desired magnitude up front. The model and any Director corrections emit at that scale (final deltas = raw × strength). Default 1x = identical to before. This is the "small lever" for users who want weak (-3) or dramatic (-15 at 5x) swings on the same scene without more invisible Dart gates.

Users who want maximum "model + Director take the wheel" (with visible feedback) flip the control on; everyone else (and weak-model users) sees zero change.

---

## Sims/Needs Simulation

**(Experimental / Bleeding Edge)**

The Sims/Needs Simulation is an optional extension to the Realism Engine that introduces a parallel life-simulation layer. When enabled, the character tracks seven needs on a 0–100 scale. These decay each turn (with morning/night modifiers) and subtly (or urgently) influence dialogue and behavior through an OOC prompt injection when they drop low. An LLM post-response verification step detects actual in-scene fulfillment and restores the affected needs.

It runs alongside — but is independent of — the classic realism systems (bond, trust, emotion, arousal, time, fixations). The master Realism toggle must be on; the needs layer is an additional per-session opt-in.

### The Seven Needs

- **Hunger** — Character grows hungry; stomach may growl and they may suggest eating (drains faster in the morning window).
- **Bladder** — Needs to use the restroom (produces a special tension note when NSFW cooldown is active and arousal is high).
- **Energy** — Becomes tired or genuinely exhausted (drains faster at night).
- **Social** — Craves genuine connection or companionship.
- **Fun** — Grows restless and bored; wants stimulation or an activity.
- **Hygiene** — Feels grimy or unkempt; wants to freshen up.
- **Comfort** — Physically uncomfortable; may want to move, shift, or change position.

Urgent threshold: ≤ 35. Critical: ≤ 20. Only the most pressing need(s) generate an injection; the LLM is told the character should voice or act on critical needs immediately.

### Integration

- **Per-session flag**: Stored as `needsSimEnabled` in the `sessions` table (plus a JSON `needsVector`). New chats inherit the value from the character card's `front_porch_extensions.realism_engine.needs_sim_enabled` (see `FrontPorchExtensions` in `character_card.dart`).
- **Runtime control**: `ChatService.needsSimEnabled` / `setNeedsSimEnabled(bool)`. Enabling mid-chat initializes the default vector; disabling clears it cleanly.
- **Decay & fulfillment**: `_tickNeedsDecay()` is called every turn before realism evals. After the AI responds, `_verifyNeedFulfillmentCall()` sends a tiny LLM eval against the recent exchange and restores values for any need the model confirms was *completed* in the scene (e.g. +70 bladder, +50 hunger, +40 energy). The verification runs post-response (fire-and-forget) so it never adds latency to the visible "Realism Engine processing" phase.
- **Erotic buffers (v2 interplay)**: Three coordinated transient buffers make long erotic scenes feel realistic and sexy:
  - **Afterglow** (4 turns): 55% reduced decay on hunger/energy/social after good sex.
  - **Lust haze / arousal suppression** (6 turns): Other needs read much milder (or are omitted) in the OOC prompt while arousal is high; light dampening of internal state multipliers.
  - **Delayed post-climax crash** (2–5 turns, intensity-scaled): Elevated energy/fun/social decay that only activates *after* both protective windows expire — the classic "we just fucked for hours and now I'm dead" feeling.
- **Snapshots for history navigation**: The live vector is captured inside every message's `realism_state['needs']['vector']` (see `_captureRealismState`). Restore logic in `_restoreRealismStateFromMessage`, `_syncRealismStateForSwipe`, regen, and fork paths replays the correct historical values — but only while the session flag remains true (old snapshots cannot re-enable a toggled-off sim).
- **Prompt injection**: `_getNeedsInjection()` adds a concise OOC directive when any need is urgent. The character never sees numeric values or the word "needs simulation."
- **Group chat support**: Needs Simulation works in regular participatory group chats (each character maintains their own needs vector). It is deliberately disabled in Director/Observer Mode. The current speaker's needs are used for injection and updated after their turn.

### UI

When the simulation is active, need levels appear as visual bars in the chat header, making it easy to see at a glance which needs are dropping and how close they are to urgent/critical. The per-character default toggle lives in the Realism Engine panel of the character editor/creator (Step 4); per-chat control is available via the usual session realism settings.

### Warnings

- **Bleeding edge**: This is a recent clean-port addition on the 0.9.8 realism architecture. Decay rates, restore amounts, thresholds, and the fulfillment prompt are still being tuned. Test on throwaway chats first.
- **Separate data directory strongly recommended**: Need state is persisted directly in your normal sessions. Use a dedicated data/profile folder (via Settings or command-line) while experimenting so you do not risk your primary long-running RPs or character libraries.
- The feature is gated behind *both* the Realism Engine master toggle *and* the specific needs-sim toggle.

---

## Performance Considerations

The Realism Engine is deliberately lightweight compared to the main chat generation, but it does add work:

- **Extra LLM calls**: Normally 2–4 short eval inferences per user turn (plus an occasional post-generation climax check). Each eval prompt is kept short (last 3–6 messages only) and the model is told to output *only* a tiny JSON object.
- **Token overhead**: The various OOC injection blocks (`relationship`, `emotion`, `time`, `trust`, `arousal`, `fixation`, `spatial`, and occasionally `needs`) typically add a few hundred tokens at most. They are included in the context budget calculation so they never push your history out of the window.
- **Local backend impact**: KoboldCPP is single-threaded, so realism evals are run sequentially (with cancellation support). On a fast GPU this is usually < 1–2 seconds per eval. On CPU or very slow setups the "Reading the room…" overlay can stay up for several seconds.
- **One-Shot Eval**: Halves the number of calls. Recommended when you value responsiveness over perfect granularity.
- **Disabling for speed**: Turn the master Realism toggle off in Settings (or per-chat) when you just want fast, lightweight chatting. No evals run at all.
- **Known KoboldCPP gotcha**: GBNF-constrained JSON output was tried extensively but frequently produced empty responses on many models. All realism evals now use unconstrained generation + robust regex extraction, which has proven far more reliable across the ecosystem.

The engine is heavily optimized: evals only run when realism is enabled, only for 1:1 chats (group chats skip most of it), and cancellation is supported at every stage so you can interrupt a slow eval and regenerate.

---

## Troubleshooting

### "Realism evaluation interrupted" or empty responses

- The most common cause on KoboldCPP is the (now-disabled) GBNF grammar. The current code intentionally omits the grammar parameter for all realism calls.
- If you still see frequent empty evals, try a different model or slightly increase the eval max tokens (rarely needed).
- Use the **Cancel** button that appears in the processing overlay — it cleanly aborts the current eval stream.

### Bond / Trust / Emotion not changing

- Make sure the master Realism toggle is actually on for that chat.
- Very small or heavily quantized models sometimes ignore the eval instructions. Larger or better-instruction-tuned models produce more reliable deltas.
- Normal conversation is *supposed* to produce mostly 0 or tiny deltas. Only meaningful moments should move the needle.

### Time not advancing

- Check that "Automatic Passage of Time" is enabled both globally and for the session.
- The LLM can legitimately hold time if the scene is mid-action (the eval explicitly asks for `"hold_time": true` in that case).
- After ~6 turns the advance attempt will be retried.

### Fixation or arousal state feels stuck

- Fixations naturally expire after 3 turns.
- Arousal/cooldown state is restored correctly on swipes because it is stored in message metadata. If something looks wrong, regenerate or swipe the last message.

### How to completely reset realism state for a chat

1. Start a new chat with the same character (the initial state from the card will be used).
2. Or manually edit the session row in the database (advanced users).
3. Regenerating the greeting or using "New Chat from this point" will usually give you a clean slate while preserving history.

### Performance is terrible / evals take forever

- Enable **One-Shot Eval**.
- Use a faster backend (OpenRouter / OpenAI / Groq / local with good GPU).
- Disable realism entirely for that chat.
- Make sure you are not running multiple heavy local processes at once (KoboldCPP + embed server + TTS, etc.).

### Realism state disappeared after an app update or migration

The engine has gone through several schema versions (REv2, REv3). The code contains explicit migration paths (`_migrateShortTermScore`, legacy session loading, etc.). If you see obviously wrong numbers, start a fresh chat with the character — the V2.5 card extensions will give you a clean modern baseline.

---

### Group Chats (Regular Mode)

As of the 2026 group-chat overhaul, the full Realism Engine + Needs Simulation now works in **regular (participatory) group chats** — each character maintains independent emotion, bond/trust, fixation, arousal, needs vector, etc.

- **Director / Observer / Auto-play Mode is deliberately excluded.** When Director Mode is on, all realism and needs mutation + injection is paused for that session (the per-character state is preserved and resumes when you toggle Director off). This matches the conceptual difference: Director is narrative control / storyboarding; regular group mode is lived-in simulation.
- Enable the master Realism toggle + the Needs Simulation sub-toggle on any group chat exactly like you would a 1:1 chat. The per-character state travels with the session via an invisible checkpoint message (no database schema changes).
- The current speaker's state is what appears in the prompt and what the post-turn evals update. This keeps token and compute cost linear with group size.
- Character evolution (personality/scenario growth) continues to work in *both* regular group chats and Director Mode (the last character who spoke is the one that gets the evolution check).

**Known limitations (current cut)**
- No cross-character relationship modeling yet (Alice's trust in Bob is not tracked).
- When you add or remove a character from a realism-enabled group, the new character starts with a fresh baseline.

---

**The Realism Engine is what makes Front Porch AI special.** It turns "talking to an AI" into "living with a character who has a real relationship with you that grows, breaks, heals, and changes over time." Take the time to leave it on for a few long sessions — the difference is night and day.

---

