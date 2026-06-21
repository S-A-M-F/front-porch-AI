// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of '../character_gen_service.dart';

extension GenEditors on CharacterGenService {
  /// Editor pass: complete a truncated greeting.
  Future<String?> editorCompletionPass(
    String greeting, {
    void Function(String)? onProgress,
  }) async {
    if (greeting.trim().isEmpty) return null;
    if (!_isGreetingTruncated(greeting)) return null; // Not truncated

    final prompt =
        '''OUTPUT FORMAT: Respond with ONLY the complete greeting text. Your entire response must be the greeting and nothing else. Do NOT include analysis, reasoning, or commentary.

TASK: This greeting was cut off mid-sentence. Complete it naturally. Write the ENTIRE greeting from the beginning (copy the existing text) and add just enough to finish the final thought properly. Do NOT add significant new content — just complete the sentence/paragraph that was cut off.

FORMATTING:
- *Asterisks* ONLY for physical actions
- "Quotation marks" for spoken dialogue
- Plain text for narration and description
- Maintain the same voice, tense, and style

TRUNCATED GREETING:
$greeting''';

    final result = await _callLLM(
      prompt,
      maxLen: 4096,
      minLen: 128,
      onProgress: onProgress,
    );
    if (result != null && result.trim().isNotEmpty) {
      final cleaned = _cleanEditorOutput(result);
      // Only accept if it's at least as long as original (completion, not replacement)
      if (cleaned.length >= greeting.length * 0.9) {
        return cleaned;
      }
    }
    return null;
  }
  // ═════════════════════════════════════════════════════════════
  //  Editor Passes
  // ═════════════════════════════════════════════════════════════

  /// Anti-puppet check: find and fix lines that describe {{user}}.
  Future<String?> editorAntiPuppetCheck(
    String greeting, {
    void Function(String)? onProgress,
  }) async {
    if (greeting.trim().isEmpty) return null;

    final prompt =
        '''OUTPUT FORMAT: Respond with ONLY the corrected greeting text. Start immediately with the first word of the greeting (usually *). Do NOT include analysis, reasoning, line-by-line breakdown, numbered lists, explanations of changes, or any other commentary. Your entire response must be the greeting and nothing else.

TASK: Fix "puppeting" in this greeting. Puppeting = describing {{user}}'s actions, thoughts, feelings, appearance, body, or dialogue.

FIXES TO APPLY:
- "you feel nervous" → rephrase as {{char}}'s observation or delete
- "your heart races" → delete
- "your hair / your eyes / your jaw" → delete physical descriptions of {{user}}
- "your movements fluid" → delete or rephrase as {{char}}'s impression
- "you sit down" → let {{char}} gesture to a seat instead
- If NO puppeting exists, return the greeting UNCHANGED

FORMATTING — PRESERVE EXACTLY:
- *Asterisks* ONLY for physical actions (things the character does)
- "Quotation marks" for spoken dialogue
- Plain text for narration, description, and inner thoughts — no special formatting
- Keep same length, tone, style. Rephrase from {{char}}'s perspective.

$greeting''';

    final result = await _callLLM(
      prompt,
      maxLen: 4096,
      minLen: 128,
      onProgress: onProgress,
    );
    if (result != null && result.trim().isNotEmpty) {
      final cleaned = _cleanEditorOutput(result);
      if (cleaned.length > greeting.length * 0.4) {
        return cleaned;
      }
    }
    return null;
  }

  /// Consistency check: verify greeting matches character profile.
  Future<String?> editorConsistencyCheck(
    String greeting,
    String description,
    String personality,
    String scenario, {
    void Function(String)? onProgress,
  }) async {
    if (greeting.trim().isEmpty) return null;

    final prompt =
        '''OUTPUT FORMAT: Respond with ONLY the corrected greeting text. Start immediately with the first word of the greeting (usually *). Do NOT include analysis, reasoning, or any commentary. Your entire response must be the greeting and nothing else.

TASK: Check this greeting for consistency with the character profile. Fix contradictions in personality, appearance, setting, or tone. If consistent, return UNCHANGED.

FORMATTING — PRESERVE EXACTLY:
- *Asterisks* ONLY for physical actions (things the character does)
- "Quotation marks" for spoken dialogue
- Plain text for narration, description, and inner thoughts — no special formatting

CHARACTER: $description | $personality | $scenario

$greeting''';

    final result = await _callLLM(
      prompt,
      maxLen: 4096,
      minLen: 128,
      onProgress: onProgress,
    );
    if (result != null && result.trim().isNotEmpty) {
      final cleaned = _cleanEditorOutput(result);
      if (cleaned.length > greeting.length * 0.4) {
        return cleaned;
      }
    }
    return null;
  }

  /// Quality polish: improve prose quality and immersiveness.
  Future<String?> editorQualityPolish(
    String greeting, {
    void Function(String)? onProgress,
  }) async {
    if (greeting.trim().isEmpty) return null;

    final prompt =
        '''OUTPUT FORMAT: Respond with ONLY the polished greeting text. Start immediately with the first word of the greeting (usually *). Do NOT include analysis, reasoning, or any commentary. Your entire response must be the greeting and nothing else.

TASK: Polish this greeting's prose. Improve vivid descriptions, sensory details, sentence rhythm, immersiveness. Keep same meaning, length, voice, and {{user}}/{{char}} placeholders. NEVER add puppeting of {{user}}.

FORMATTING — ENFORCE STRICTLY:
- *Asterisks* ONLY for physical actions (things the character does)
- "Quotation marks" for spoken dialogue
- Plain text for narration, description, and inner thoughts — no special formatting
- If narration is incorrectly wrapped in *asterisks*, unwrap it to plain text

$greeting''';

    final result = await _callLLM(
      prompt,
      maxLen: 4096,
      minLen: 128,
      onProgress: onProgress,
    );
    if (result != null && result.trim().isNotEmpty) {
      final cleaned = _cleanEditorOutput(result);
      if (cleaned.length > greeting.length * 0.4) {
        return cleaned;
      }
    }
    return null;
  }
}
