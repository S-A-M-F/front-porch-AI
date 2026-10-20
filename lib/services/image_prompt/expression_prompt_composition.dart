// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'expression_intensity.dart';
import 'expression_prompts.dart';
import 'expression_prompt_rules.dart';

String composeExpressionPrompt({
  required String emotion,
  required String basePrompt,
  required bool editMode,
  ExpressionIntensity intensity = ExpressionIntensity.current,
  required ExpressionPromptRules rules,
}) => rules.apply(
  originalExpressionPrompt(
    emotion: emotion,
    basePrompt: basePrompt,
    editMode: editMode,
    intensity: intensity,
  ),
);
