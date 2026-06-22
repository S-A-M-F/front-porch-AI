# Golden tests

This directory holds **golden (snapshot) tests** — the regression net that locks
down deterministic behavior so it can't drift silently. There are two kinds:

| Kind | What it captures | Stored as | Runs on |
|------|------------------|-----------|---------|
| **Text / JSON goldens** | Deterministic string/structured output of pure logic (prompt normalization, needs curves, parse results, serialization) | `_goldens/<area>/<name>.golden` and `.golden.json` | every platform, every run |
| **Widget goldens** | Rendered pixels of UI widgets, light + dark | `widget/_goldens/<area>/<name>.<light\|dark>.png` | Linux / CI only (tagged `golden`, gated `@TestOn('linux')`) |

## Why this exists

The first golden anchors a real, user-reported regression (commit `8a0844f`):
AI-generated characters baked their literal **name** into card fields instead of
the portable `{{char}}` macro, and think-only model output silently produced a
blank first message. Golden tests make that class of bug — and any future drift
in the deterministic logic and UI that drive character behavior — fail loudly in
review instead of shipping.

## Running

```bash
# Everything except pixel goldens (fast; the default dev loop):
flutter test --exclude-tags golden

# Just the text/JSON goldens:
flutter test test/golden --exclude-tags golden

# Pixel/widget goldens (Linux / CI only):
flutter test --tags golden
```

## Updating goldens (after an *intentional* change)

A golden diff is a behavior change. **Never blind-update** — regenerate, then
review the `git diff` and justify it in the PR.

```bash
# Text / JSON goldens (writes/overwrites *.golden / *.golden.json):
UPDATE_GOLDENS=1 flutter test test/golden

# Widget PNGs — run on Linux (matches CI's renderer):
flutter test --tags golden --update-goldens
```

## How it's kept deterministic

- **Text/JSON** — `golden_harness.dart` normalizes line endings + trailing
  whitespace and canonicalizes JSON (recursively sorted keys), so formatting
  churn never produces a false diff.
- **Widgets** — `flutter_test_config.dart` disables `google_fonts` runtime
  fetching and loads the committed Roboto font (`fonts/`), and
  `support/golden_app.dart` pumps every widget at a fixed surface size in both
  themes. Pixel goldens are authored on Linux only; `@TestOn('linux')` skips
  them elsewhere because anti-aliasing differs by platform.

## Layout

```
test/golden/
  golden_harness.dart        # text/JSON snapshot helper (expectGolden / expectGoldenJson)
  support/golden_app.dart    # widget harness (pumpGolden / expectThemedGoldens)
  fonts/                     # committed Roboto for deterministic widget text
  _goldens/                  # committed text/JSON snapshots, by area
  chargen|needs|emotion|card|realism/  *_golden_test.dart   # logic goldens
  widget/                    # widget golden tests + widget/_goldens/*.png
  widget/COVERAGE.md         # full-app UI coverage ledger (what's done / pending)
```
