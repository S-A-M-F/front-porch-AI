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
13. [Performance Considerations](#performance-considerations)
14. [Troubleshooting](#troubleshooting)

---

## Overview

<!-- TODO: Explain the Realism Engine in plain English:
- What problem it solves (flat, stateless conversations)
- How it works (LLM evaluates relationship state after each turn)
- What users experience (characters remember feelings, relationships evolve)
- That it's optional and can be toggled per-chat
-->

Placeholder: The Realism Engine makes conversations feel alive by giving characters memory of their relationship with you.

---

## Enabling & Disabling

<!-- TODO: Where to find the toggle:
- Global default in Settings
- Per-character default in character editor
- Per-chat override in chat settings
-->

Placeholder: How to turn the Realism Engine on or off.

---

## Bond Tracking

<!-- TODO: Explain the bond system:
- Short-term bond (volatile, changes quickly)
- Long-term bond (stable, evolves slowly)
- Range: -300 to +300
- What positive/negative bond means for character behavior
- How bond affects generated responses
-->

Placeholder: Characters develop feelings toward you based on your interactions.

---

## Trust System

<!-- TODO: Trust level mechanics:
- Range: -100 to +100
- How trust differs from bond
- What builds/erodes trust
- How trust affects character openness
-->

Placeholder: Trust represents how safe a character feels with you.

---

## Emotion States

<!-- TODO: Emotion tracking:
- What emotions are tracked
- Emotion inertia (emotions carry between turns)
- How emotions affect dialogue
- The expression classifier (ONNX/LLM-based)
-->

Placeholder: Characters have mood states that influence how they speak and react.

---

## Arousal System

<!-- TODO: Arousal tracking:
- Range: ±100
- Tier names (what labels are used)
- How it factors into character behavior
- Connection to NSFW cooldown
-->

Placeholder: Tracks character excitement/arousal levels for mature content.

---

## Passage of Time

<!-- TODO: Deterministic time progression:
- Advances every 6 turns
- Time of day tracking
- Day count
- How this affects character dialogue
- Spatial awareness when disabled
-->

Placeholder: In-universe time progresses as you chat, affecting character responses.

---

## Chaos Mode (Chance Time)

<!-- TODO: Random event system:
- What "Chance Time" events are
- How they're generated
- Frequency controls
- Examples of chaos events
-->

Placeholder: Unpredictable events that shake up conversations and add drama.

---

## Character Evolution

<!-- TODO: Trait development over time:
- How character traits can evolve
- What triggers evolution
- Evolution interval setting
- Whether changes are permanent
-->

Placeholder: Characters can grow and change based on their experiences with you.

---

## Fixation Engine

<!-- TODO: Emotional obsessions:
- What fixations are
- How they form
- Lifespan configuration
- How they affect dialogue
-->

Placeholder: Characters can develop obsessions — lingering thoughts about past events.

---

## NSFW Cooldown

<!-- TODO: Content pacing mechanism:
- What it does
- How it works
- Configuration
-->

Placeholder: Controls the pacing of mature content in conversations.

---

## One-Shot Eval Mode

<!-- TODO: Performance optimization:
- What it does (fuses relationship + scene eval into one LLM call)
- When to use it
- Trade-offs
-->

Placeholder: Reduces eval calls for faster processing.

---

## Performance Considerations

<!-- TODO: Impact on generation speed:
- Additional LLM calls per turn
- Token overhead
- When to disable for performance
- Known issues with GBNF grammars on KoboldCPP
-->

Placeholder: The Realism Engine adds extra processing per turn — here's how to manage it.

---

## Troubleshooting

<!-- TODO: Common Realism Engine issues:
- Empty eval responses (GBNF grammar issue)
- Eval timeout errors
- Bond not changing
- Time not advancing
- How to reset realism state
-->

Placeholder: Diagnosing and fixing Realism Engine problems.

