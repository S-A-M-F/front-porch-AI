// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/image_prompt/image_gen_context.dart';
import 'package:front_porch_ai/services/llm_service.dart';

/// Single source of truth for turning (mode + style + raw context) into a high-quality,
/// style-faithful image generation prompt.
///
/// ## Design
/// - Plain class (no ChangeNotifier, easily testable with or without a real LLMService).
/// - Stateless / prompt-only for the core build path (no owned scalars that need reset).
/// - All "spirit of the mode" contracts live here with explicit documentation.
/// - Style application is centralized and *enforced* (no more fragile post-hoc substring checks).
/// - LLM path (when available) uses stronger instructions + few-shot examples.
/// - Robust fallbacks that are already better than the old static buildPrompt for every mode.
///
/// ## Mode Contracts (the "spirit")
/// - **characterPortrait**: Purely visual appearance + current expression/pose/clothing. Never
///   personality, backstory, or scenario text. "Detailed close-up, expressive face, high quality
///   rendering" + style. Current expression (if supplied) is injected as a strong visual cue.
/// - **chatBackground**: Environment / setting / atmosphere / lighting ONLY. Explicit and repeated
///   "NO PEOPLE, NO CHARACTERS, NO FIGURES, NO HUMANS" language in both prompt and negative (Stage 4 complete:
///   auto-seeded in ImageStudio.initState for chatBackground per this contract; user per-gen editor wins;
///   positive enforcement remains here in builder; see image_studio.dart:175 and chatBackground static/LLM paths).
///   Wide panoramic or establishing landscape composition. Scenario and worldInfo are used as
///   environmental seeds, never character seeds.
/// - **visualizeScene**: Current visual composition of the ongoing scene — who is present, what
///   they are doing/holding/wearing, spatial relationships, mood, lighting (timeOfDay + hints).
///   Recent messages (controlled by studio slider N, default 5, max ~10) are treated as *narrative source to distill*,
///   not raw text to dump. The N messages (pre-generated) are stripped of all `<think>` (simple _stripThinkBlocks via _clean).
///   (The prior "Message Illustration" / fromLastMessage mode was removed entirely — see user request + CLAUDE.md
///   overlapping-feature rule — because Visualize Scene's N slider now provides equivalent or better functionality
///   with full controls, no popup, and consistent UX. N=1 on Visualize covers the "last message" distillation case.)
///   On Craft: user box text (if any) + persona + char visual info (no personality) + the stripped N + style sent to LLM
///   to produce the final visual prompt put back into the editable box. No boilerplate/pregenerated ever in initial box.
/// - **customPrompt** / **userAvatar**: Straight-through with style enforcement. userAvatar
///   receives personaText as the appearance source (no personality leakage).
///
/// ## Style Enforcement
/// The builder always produces a final prompt that contains the canonical style suffix for the
/// chosen paradigm. A live preview of the exact suffix is available for the UI (see
/// getStyleSuffix + getStylePreviewNote). Substring hacks are gone.
///
/// ## LLM vs Fallback
/// When an LLMService is supplied and ready, generateSmartPrompt is used (richer instruction +
/// examples). On any failure (stream error, bad parse, empty output) we fall back to a strong
/// static builder that is already an improvement over the pre-refactor logic. The static path
/// is also used for customPrompt (no LLM needed).
///
/// This class is intentionally decoupled from ImageGenService storage and UI. The service
/// (Stage 2) will build an ImageGenContext from the flat parameters it receives today and
/// delegate here. Callers that want the best prompt can construct a context directly in tests
/// or future surfaces.
///
/// See the dedicated test file for many concrete examples of the expected distillation behavior.
class ImagePromptBuilder {
  final LLMService? _llmService;

  // Canonical style suffixes (moved here as the source of truth in Stage 1/2 transition).
  // Natural language versions work across FLUX, SD3, SDXL, and older models.
  static const Map<String, String> styleModifiers = {
    'photorealistic':
        'Photorealistic with cinematic lighting, sharp focus, and highly detailed textures.',
    'anime':
        'Anime-style illustration with clean linework, expressive eyes, vibrant colors, and cel shading.',
    'fantasy_art':
        'Epic fantasy digital art with dramatic lighting, rich environmental detail, and a painterly quality.',
    'oil_painting':
        'Classical oil painting with visible brushstrokes, rich color depth, and fine art composition.',
    'digital_art':
        'Polished digital art with vibrant colors, clean lines, and professional illustration quality.',
    'watercolor':
        'Soft watercolor illustration with flowing color washes, delicate edges, and gentle translucent tones.',
  };

  // Legacy comma/tag versions (for the 'tags' paradigm, primarily SD 1.5 / Illustrious family).
  static const Map<String, String> legacyStyleModifiers = {
    'photorealistic':
        'photorealistic, cinematic lighting, sharp focus, highly detailed, 8k',
    'anime':
        'anime style, masterpiece, best quality, highly detailed, cel shading',
    'fantasy_art':
        'fantasy art, epic, dramatic lighting, highly detailed, painterly',
    'oil_painting': 'oil painting, traditional media, brushstrokes, fine art',
    'digital_art': 'digital art, polished, vibrant, illustration, high quality',
    'watercolor':
        'watercolor, translucent, soft washes, pastel, traditional media',
  };

  static const int _maxPromptLength = 1000;

  ImagePromptBuilder({LLMService? llmService}) : _llmService = llmService;

  /// Main entry. Builds (and style-enforces) a prompt for the given mode using the supplied context.
  /// The context already carries the chosen style and paradigm.
  Future<String> buildPrompt(ImageGenContext ctx) async {
    if (ctx.mode == ImageGenMode.customPrompt) {
      final suffix = _getStyleSuffix(ctx.style, ctx.paradigm);
      final glue = ctx.paradigm == 'tags' ? ', ' : '. ';
      final raw =
          '${ctx.lastMessage ?? ''}$glue$suffix'; // lastMessage field reused for custom text
      return ImageGenContext.truncate(raw, _maxPromptLength);
    }

    // LLM path (if available and not custom)
    final llm = _llmService;
    if (llm != null && llm.isReady) {
      try {
        final smart = await _generateSmartWith(llm, ctx);
        if (smart.isNotEmpty) {
          return _ensureStyleAndCap(smart, ctx.style, ctx.paradigm);
        }
      } catch (e) {
        debugPrint(
          'ImagePromptBuilder: LLM smart prompt failed ($e) — falling back to static',
        );
      }
    }

    // Strong static fallback (already better than pre-refactor for every mode)
    final fallback = _buildStatic(ctx);
    return _ensureStyleAndCap(fallback, ctx.style, ctx.paradigm);
  }

  /// Returns the exact style suffix that will be appended for (style, paradigm).
  /// UI can use this for live "what will be added" previews.
  String getStyleSuffix(String style, String paradigm) =>
      _getStyleSuffix(style, paradigm);

  /// Synchronous static (no-LLM) prompt for callers that need the old buildPrompt signature.
  /// This is the improved fallback logic only — use [buildPrompt] for the full (LLM+static) experience.
  String buildStaticPrompt(ImageGenContext ctx) {
    final raw = _buildStatic(ctx);
    return _ensureStyleAndCap(raw, ctx.style, ctx.paradigm);
  }

  /// Short human note describing how the style will be applied (for tooltips / help).
  String getStylePreviewNote(String style, String paradigm) {
    final suffix = _getStyleSuffix(style, paradigm);
    return paradigm == 'tags'
        ? 'Tags mode: will be appended as comma-separated visual tags.'
        : 'Natural language: "$suffix"';
  }

  // ─────────────────────────────────────────────────────────────────────
  // Internal implementation
  // ─────────────────────────────────────────────────────────────────────

  String _getStyleSuffix(String style, String paradigm) {
    final map = paradigm == 'tags' ? legacyStyleModifiers : styleModifiers;
    return map[style] ?? '';
  }

  /// Canonical dialogue strip (used by static fallbacks for visualizeScene
  /// *and* the LLM post-process in _generateSmartWith). Deduped to avoid fragility drift.
  /// Removes quoted spoken content so it never appears as literal text in the image prompt.
  /// Static path is intentionally best-effort (keeps some narrative for robustness without LLM);
  /// LLM path (via generateSmartPrompt) provides stronger visual-only distillation. (fromLastMessage
  /// "Message Illustration" mode was removed as redundant with the Visualize N slider.)
  String _stripQuotedDialogue(String text) {
    return text
        .replaceAll(RegExp(r'["\u201c][^"\u201d]+["\u201d]'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  /// Strips completed `<think>...</think>` and unclosed trailing `<think>` blocks from narrative sources.
  /// Prevents artifacts from thinking models or interrupted realism evaluations from leaking into
  /// image generation prompts. Applied to lastMessage/recent/scenario/world before visual distillation.
  /// For visualize slider: the N messages passed are *already generated* so this simple strip (plus _clean) is sufficient
  /// per user spec — no complex re-generation, just filter the snapshot list to N then strip each.
  String _stripThinkBlocks(String text) {
    if (text.isEmpty) return text;
    // Completed blocks (case-insensitive, supports multiline)
    text = text.replaceAll(
      RegExp(r'<\/?think>.*?<\/think>', dotAll: true, caseSensitive: false),
      '',
    );
    // Unclosed: everything from the last <think> to end
    final idx = text.toLowerCase().lastIndexOf('<think>');
    if (idx != -1) {
      text = text.substring(0, idx);
    }
    // Stray/leftover tags (e.g. lone </think> tail from partial previous chunk, malformed, or unopened close).
    // Covers the user-reported case of literal '</think>' fragments leaking into visual sources (simple per user spec).
    text = text.replaceAll(
      RegExp(r'<\/?think[^>]*>', caseSensitive: false),
      '',
    );
    text = text.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    return text;
  }

  /// Cleans narrative text (last message, recent, scenario, world) for use in visual image prompts.
  /// Combines quote strip + think strip + removal of known non-visual meta (interrupted evals, card import junk).
  /// Keeps the result as source material for distillation rather than raw dump.
  String _cleanNarrativeForVisual(String text) {
    text = _stripQuotedDialogue(text);
    text = _stripThinkBlocks(text);
    text = text.replaceAll(
      RegExp(
        r'Realism evaluation interrupted.*?(?:\n|$)',
        caseSensitive: false,
      ),
      '',
    );
    text = text.replaceAll(
      RegExp(
        r'Auto-imported from character card:.*?(?:\n|$)',
        caseSensitive: false,
      ),
      '',
    );
    text = text.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    return text;
  }

  String _ensureStyleAndCap(String base, String style, String paradigm) {
    String cleaned = base.trim();
    if (paradigm == 'tags') {
      // Tags mode must never have sentence periods.
      cleaned = cleaned.replaceAll('.', ',').replaceAll(RegExp(r',,+'), ',');
    }
    final suffix = _getStyleSuffix(style, paradigm);
    if (suffix.isEmpty) {
      return ImageGenContext.truncate(cleaned, _maxPromptLength);
    }
    final lower = cleaned.toLowerCase();
    final glue = paradigm == 'tags' ? ', ' : '. ';
    // Very tolerant check — if the first ~8 chars of the suffix are present we assume it's there.
    final head = suffix.substring(0, suffix.length.clamp(0, 8)).toLowerCase();
    if (lower.contains(head)) {
      return ImageGenContext.truncate(cleaned, _maxPromptLength);
    }
    // Guard: if no visual base content, avoid leading glue producing ". Photoreal..." boilerplate.
    if (cleaned.isEmpty) {
      return ImageGenContext.truncate(suffix, _maxPromptLength);
    }
    final joined = '$cleaned$glue$suffix';
    return ImageGenContext.truncate(joined, _maxPromptLength);
  }

  Future<String> _generateSmartWith(LLMService llm, ImageGenContext ctx) async {
    final suffix = _getStyleSuffix(ctx.style, ctx.paradigm);
    final isTags = ctx.paradigm == 'tags';

    final formatInstruction = isTags
        ? 'Write a flat, comma-separated list of visual danbooru-style tags describing ONLY the visible scene, characters, clothing, pose, lighting, and environment. NO prose sentences. NO character names. NO dialogue. Example: masterpiece, best quality, 1girl, long silver hair, determined expression, swinging sword, rain-soaked courtyard, moonlight, dynamic action, wet cloak'
        : 'Write ONE vivid paragraph in natural descriptive English. Focus exclusively on what can be seen: appearance, clothing, pose, expression, action, environment, lighting, mood, composition. NO character names. NO spoken dialogue or thoughts. Be specific and cinematic.';

    String modeInstruction;
    switch (ctx.mode) {
      case ImageGenMode.characterPortrait:
        modeInstruction =
            'TASK: Create a tight character portrait prompt. Use ONLY the supplied appearance description '
            'and current expression/pose. Emphasize face, eyes, hair, clothing details, expression, and '
            'a pleasing close-up composition. Do not invent a full-body scene or environment unless it is '
            'minimal and clearly implied by the appearance text.';
      case ImageGenMode.chatBackground:
        modeInstruction =
            'TASK: Describe a wide panoramic environment / setting ONLY. '
            'CRITICAL: NO PEOPLE, NO CHARACTERS, NO FIGURES, NO HUMANS, NO SILHOUETTES. '
            'Focus on architecture, landscape, weather, lighting, atmosphere, and mood. '
            'The result must be usable as a chat background (empty of figures).';
      case ImageGenMode.visualizeScene:
        modeInstruction =
            'TASK: Describe the CURRENT VISUAL SCENE as a cinematic illustration. '
            'The "Recent messages (last N, <think> stripped for visual distillation)" block below contains the *most recent turns* the user selected with the slider. '
            'These describe what the characters are *actually doing right now* (poses, actions this moment, clothing, spatial relations, mood, lighting). '
            'Base the visual prompt primarily on that recent action and the supplied character appearance; older scenario text is only background if mentioned. '
            'Who is present, what they are physically doing, wearing, holding, their spatial relationship '
            'to each other and the environment, the lighting (time of day + weather), and overall mood. '
            'Distill from the recent narrative; do not copy dialogue.';
      case ImageGenMode.userAvatar:
        modeInstruction =
            'TASK: Portrait of the user character. Use the supplied persona appearance text and any '
            'expression/pose hints. Close-up, expressive, high-quality rendering.';
      default:
        modeInstruction = 'Describe the scene as a vivid, visual image prompt.';
    }

    // Build a compact, visual-only context block (the builder's responsibility to filter).
    // For pure portrait modes we deliberately omit narrative/chat/scene context (lastMessage,
    // recentMessages, scenario, worldInfo) so the LLM sees mostly the supplied appearance text.
    // This matches the static path behavior for portraits and the strict "use ONLY the supplied
    // appearance description" + "do not invent full-body scene" instructions. Narrative context
    // remains available for visualizeScene (the fromLastMessage / Message Illustration mode was removed
    // as redundant once Visualize gained the N-slider for recent messages).
    // Time/lighting hints are still provided for portraits as they help with face lighting.
    final parts = <String>[];
    if (ctx.characterName != null && ctx.characterName!.isNotEmpty) {
      parts.add('Primary character: ${ctx.characterName}');
    }
    final app = ctx.effectiveCharacterAppearance;
    if (app.isNotEmpty) {
      parts.add('Appearance: ${ctx.resolveMacros(app)}');
    }

    final isPurePortrait =
        ctx.mode == ImageGenMode.characterPortrait ||
        ctx.mode == ImageGenMode.userAvatar;

    // User spec (no boilerplate/pregen in box; Craft assembles): always surface User persona (name + text) + character visual info
    // (via effectiveAppearance which never includes personality/backstory). The userInstruction (typed box content before Craft)
    // is sent so LLM "parses [it] into the image gen prompt". Style always appended by _ensure at end.
    if (ctx.personaName != null && ctx.personaName!.isNotEmpty) {
      parts.add('User: ${ctx.personaName}');
      if (ctx.personaText != null && ctx.personaText!.isNotEmpty) {
        parts.add('User persona: ${ctx.resolveMacros(ctx.personaText)}');
      }
    }
    // (character appearance block already added unconditionally above via 'Appearance:')

    if (!isPurePortrait &&
        ctx.scenario != null &&
        ctx.scenario!.isNotEmpty &&
        ctx.mode != ImageGenMode.visualizeScene) {
      final cleaned = _cleanNarrativeForVisual(ctx.resolveMacros(ctx.scenario));
      if (cleaned.isNotEmpty) {
        parts.add('Environment/setting cues: $cleaned');
      }
    }
    if (!isPurePortrait &&
        ctx.worldInfo != null &&
        ctx.worldInfo!.isNotEmpty &&
        ctx.mode != ImageGenMode.visualizeScene) {
      final cleaned = _cleanNarrativeForVisual(
        ctx.resolveMacros(ctx.worldInfo),
      );
      if (cleaned.isNotEmpty) {
        parts.add('World/atmosphere: $cleaned');
      }
    }
    if (ctx.timeOfDay != null && ctx.timeOfDay!.isNotEmpty) {
      parts.add('Time / lighting: ${ctx.timeOfDay}');
    }
    if (ctx.lightingHint != null && ctx.lightingHint!.isNotEmpty) {
      parts.add('Lighting hint: ${ctx.lightingHint}');
    }
    if (ctx.isGroupNonObserver &&
        ctx.currentSpeakerId != null &&
        ctx.currentSpeakerId!.isNotEmpty &&
        ctx.mode == ImageGenMode.visualizeScene) {
      parts.add('Group scene focus / active speaker: ${ctx.currentSpeakerId}');
    }
    if (!isPurePortrait &&
        ctx.lastMessage != null &&
        ctx.lastMessage!.isNotEmpty &&
        ctx.mode != ImageGenMode.visualizeScene) {
      final cleaned = _cleanNarrativeForVisual(
        ctx.resolveMacros(ctx.lastMessage!),
      );
      if (cleaned.isNotEmpty) {
        parts.add('Narrative to illustrate (last message): $cleaned');
      }
    }
    if (!isPurePortrait &&
        ctx.recentMessages != null &&
        ctx.recentMessages!.isNotEmpty) {
      // User spec for Visualize: slider controls exactly how many messages (from the launch-provided recent list)
      // are sent in the prompt to the LLM. Messages are pre-generated, so stripping <think> is simple (use _clean which
      // does _stripThinkBlocks + quote/meta). Take last N (most recent in the list). For other modes use full provided.
      // 1:1 vs group: the list passed already reflects correct recent for the session; dispatch via cbs/impersonation in launcher.
      List<String> vizSource = ctx.recentMessages!;
      if (ctx.mode == ImageGenMode.visualizeScene &&
          ctx.visualizeNumMessages != null &&
          ctx.visualizeNumMessages! > 0) {
        final n = ctx.visualizeNumMessages!;
        if (vizSource.length > n) {
          vizSource = vizSource.sublist(vizSource.length - n);
        }
      }
      final joined = vizSource
          .map((m) => _cleanNarrativeForVisual(ctx.resolveMacros(m)))
          .where((m) => m.isNotEmpty)
          .join('\n');
      if (joined.isNotEmpty) {
        final prefix = (ctx.mode == ImageGenMode.visualizeScene)
            ? 'Recent messages (last ${vizSource.length}, <think> stripped for visual distillation):\n'
            : 'Recent narrative context (distill visuals only):\n';
        parts.add('$prefix$joined');
      }
    }
    // User instruction (typed before Craft) always included when present — LLM instructed to incorporate/parse it.
    if (ctx.userInstruction != null && ctx.userInstruction!.trim().isNotEmpty) {
      parts.add(
        'Additional instructions / guidance from user: ${ctx.resolveMacros(ctx.userInstruction)}',
      );
    }

    final rawContext = ImageGenContext.truncate(parts.join('\n'), 1800);

    final llmPrompt =
        'You are an expert visual prompt engineer for high-quality image models (FLUX, SD3, SDXL, Illustrious, etc.).\n'
        'Your job is to produce a single, concise, highly effective image prompt.\n\n'
        '$formatInstruction\n\n'
        '$modeInstruction\n\n'
        'STRICT RULES:\n'
        '- Keep the final prompt under ~90 words (natural) or ~60 tags.\n'
        '- NEVER include character names in the output prompt.\n'
        '- NEVER include spoken dialogue, quotes, or internal thoughts as text.\n'
        '- For backgrounds: repeat the "no people" rule in the prompt itself.\n'
        '- End the prompt with the art style description.${suffix.isNotEmpty ? " Art style: $suffix" : ""}\n\n'
        'Context (visual material only):\n$rawContext\n\n'
        'Output ONLY the image prompt text. No JSON, no explanations, no markdown, no extra lines.';

    String accumulated = '';
    await for (final token in llm.generateStream(
      GenerationParams(
        prompt: llmPrompt,
        maxLength: 600,
        temperature: 0.25,
        repeatPenalty: 1.0,
        reasoningEnabled: false,
        reasoningMaxTokens: 0,
        stopSequences: ['\n\n', '<END>', '</END>', '```'],
      ),
    )) {
      accumulated += token;
    }

    String prompt = accumulated.trim();

    // Robust extraction: strip code fences, take first meaningful block, remove leading labels.
    prompt = prompt
        .replaceAll(RegExp(r'^```[a-z]*\s*'), '')
        .replaceAll(RegExp(r'```$'), '')
        .replaceAll(
          RegExp(r'^(prompt|image prompt|output)[:\s]+', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'\n+'), ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();

    // Extra belt-and-suspenders cleaning for any leaked think/meta from the model output or bad context.
    // Complements the input cleaning with _cleanNarrativeForVisual on narrative sources.
    prompt = _stripThinkBlocks(prompt);
    prompt = prompt.replaceAll(
      RegExp(
        r'Realism evaluation interrupted.*?(?:\n|$)',
        caseSensitive: false,
      ),
      '',
    );

    if (prompt.isEmpty) {
      throw Exception('LLM returned empty prompt');
    }

    // If the model ignored the "no names" rule, the caller can still edit in the studio.
    // We do a best-effort name strip here for the common case.
    if (ctx.characterName != null && ctx.characterName!.isNotEmpty) {
      final name = RegExp.escape(ctx.characterName!);
      prompt = prompt.replaceAll(
        RegExp('\\b$name\\b', caseSensitive: false),
        'the character',
      );
    }

    // Best-effort removal of literal spoken dialogue (the spirit of the removed fromLastMessage / Message Illustration mode,
    // now handled via visualizeScene + N slider for recent turns).
    // Uses the canonical deduped helper (also used by static fallbacks).
    prompt = _stripQuotedDialogue(prompt);

    return prompt;
  }

  String _buildStatic(ImageGenContext ctx) {
    String resolved(String? t) => ctx.resolveMacros(t);
    final parts = <String>[];

    switch (ctx.mode) {
      // fromLastMessage / Message Illustration case fully removed (user request: redundant with Visualize Scene N slider).
      // The distillation + "no raw dialogue" + appearance grounding for "last/recent message" visual is now
      // handled by visualizeScene (N slider + recent block as primary narrative source) in both static and LLM paths.

      case ImageGenMode.characterPortrait:
        if (ctx.characterName != null && ctx.characterName!.isNotEmpty) {
          parts.add('Character portrait of ${ctx.characterName}.');
        }
        final app = ctx.effectiveCharacterAppearance;
        if (app.isNotEmpty) {
          parts.add(ImageGenContext.truncate(resolved(app), 380));
        }
        parts.add(
          'Detailed close-up portrait, expressive face, high quality rendering, sharp focus on features and clothing.',
        );

      case ImageGenMode.chatBackground:
        if (ctx.scenario != null && ctx.scenario!.isNotEmpty) {
          parts.add(
            'Environment: ${ImageGenContext.truncate(resolved(ctx.scenario), 280)}',
          );
        }
        if (ctx.worldInfo != null && ctx.worldInfo!.isNotEmpty) {
          parts.add(
            'Setting and atmosphere: ${ImageGenContext.truncate(resolved(ctx.worldInfo), 280)}',
          );
        }
        if (ctx.timeOfDay != null && ctx.timeOfDay!.isNotEmpty) {
          parts.add('Lighting: ${ctx.timeOfDay}');
        }
        if (ctx.lightingHint != null && ctx.lightingHint!.isNotEmpty) {
          parts.add('Lighting detail: ${ctx.lightingHint}');
        }
        parts.add(
          'Wide panoramic landscape or establishing environmental view, atmospheric lighting, '
          'highly detailed background, NO PEOPLE, NO CHARACTERS, NO FIGURES, NO HUMANS, NO SILHOUETTES, '
          'empty of any living subjects, suitable as a chat background or scene wallpaper.',
        );

      case ImageGenMode.visualizeScene:
        // User spec: no boilerplate/pregen ever in the editable box on open (studio now starts empty/minimal hint).
        // Craft (LLM or static fallback) assembles using slider N + user box text (as instr) + persona + char visual (no pers)
        // + style. For static viz path (no LLM), respect visualizeNumMessages to limit recent (parity with LLM path).
        // The recent N messages (the *latest* turns describing what is actually going on right now) are the primary
        // "current scene narrative". Scenario/world are omitted in static viz (they were the source of old "first message"
        // / setup text leading the prompt). "Key character appearance" is grounding after the recent action.
        if (ctx.characterDescription != null &&
            ctx.characterDescription!.isNotEmpty) {
          parts.add(
            'Key character appearance: ${ImageGenContext.truncate(resolved(ctx.characterDescription), 200)}',
          );
        }
        if (ctx.currentExpression != null &&
            ctx.currentExpression!.isNotEmpty) {
          parts.add(
            'Current expression / pose: ${resolved(ctx.currentExpression)}',
          );
        }
        if (ctx.personaName != null && ctx.personaName!.isNotEmpty) {
          parts.add('User: ${ctx.personaName}');
          if (ctx.personaText != null && ctx.personaText!.isNotEmpty) {
            parts.add(
              'User persona: ${ImageGenContext.truncate(resolved(ctx.personaText), 120)}',
            );
          }
        }
        if (ctx.userInstruction != null &&
            ctx.userInstruction!.trim().isNotEmpty) {
          parts.add(
            'User guidance: ${ImageGenContext.truncate(resolved(ctx.userInstruction), 120)}',
          );
        }
        // Recent N (tail = most recent turns the slider selected) is the primary current scene content.
        if (ctx.recentMessages != null && ctx.recentMessages!.isNotEmpty) {
          List<String> vizSrc = ctx.recentMessages!;
          if (ctx.visualizeNumMessages != null &&
              ctx.visualizeNumMessages! > 0) {
            final n = ctx.visualizeNumMessages!;
            if (vizSrc.length > n) {
              vizSrc = vizSrc.sublist(vizSrc.length - n);
            }
          }
          final recent = vizSrc
              .map(
                (m) => ImageGenContext.truncate(
                  _cleanNarrativeForVisual(resolved(m)),
                  120,
                ),
              )
              .where((m) => m.isNotEmpty)
              .join(' ');
          if (recent.isNotEmpty) {
            parts.add(
              'Recent visual events (N=${vizSrc.length}, stripped): ${ImageGenContext.truncate(recent, 220)}',
            );
          }
        }
        if (ctx.lastMessage != null && ctx.lastMessage!.isNotEmpty) {
          final vis = _cleanNarrativeForVisual(resolved(ctx.lastMessage!));
          if (vis.isNotEmpty) {
            parts.add(
              'Current visual composition (distilled): ${ImageGenContext.truncate(vis, 220)}, '
              'showing characters\' poses, expressions, clothing, and spatial relationships.',
            );
          }
        }
        if (ctx.timeOfDay != null && ctx.timeOfDay!.isNotEmpty) {
          parts.add('Time / lighting: ${ctx.timeOfDay}');
        }
        if (ctx.lightingHint != null && ctx.lightingHint!.isNotEmpty) {
          parts.add('Lighting detail: ${ctx.lightingHint}');
        }
        if (ctx.isGroupNonObserver &&
            ctx.currentSpeakerId != null &&
            ctx.currentSpeakerId!.isNotEmpty) {
          parts.add('Focus on ${resolved(ctx.currentSpeakerId)}.');
        }
        parts.add(
          'Cinematic wide or medium establishing shot of the scene, clear composition showing characters '
          'present and what they are physically doing, atmospheric lighting.',
        );

      case ImageGenMode.userAvatar:
        if (ctx.personaName != null && ctx.personaName!.isNotEmpty) {
          parts.add('Portrait of ${ctx.personaName}.');
        }
        if (ctx.personaText != null && ctx.personaText!.isNotEmpty) {
          parts.add(ImageGenContext.truncate(resolved(ctx.personaText), 380));
        }
        if (ctx.currentExpression != null &&
            ctx.currentExpression!.isNotEmpty) {
          parts.add(resolved(ctx.currentExpression));
        }
        parts.add(
          'Detailed close-up portrait, expressive face, high quality rendering.',
        );

      case ImageGenMode.customPrompt:
        // Already handled at the top of buildPrompt.
        final raw = ctx.lastMessage ?? '';
        if (raw.trim().isEmpty) {
          return 'detailed visual scene with strong composition and lighting';
        }
        return raw;
    }

    String prompt = parts.where((p) => p.isNotEmpty).join(' ');

    // Name stripping for the main character in visualizeScene (the replacement for the removed
    // fromLastMessage / Message Illustration mode) so the static prompt respects the "NEVER include
    // character names" rule that the LLM craft path is given. Replaces the known characterName with
    // "the character". Other names in the scene are best-effort.
    if (ctx.mode == ImageGenMode.visualizeScene &&
        ctx.characterName != null &&
        ctx.characterName!.isNotEmpty) {
      final name = RegExp.escape(ctx.characterName!);
      prompt = prompt.replaceAll(
        RegExp('\\b$name\\b', caseSensitive: false),
        'the character',
      );
    }

    return prompt;
  }
}
