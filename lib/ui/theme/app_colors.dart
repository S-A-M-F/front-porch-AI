// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  /// Surface background for dialogs, containers, and panels.
  static const Color surface = Color(0xFF1F2937);

  /// Deep background for scaffolds and page-level backgrounds.
  static const Color background = Color(0xFF0F172A);

  /// Card/container background for cards, dropdowns, and elevated surfaces.
  static const Color card = Color(0xFF1E293B);

  // ---------------------------------------------------------------------------
  // Chat appearance defaults
  // ---------------------------------------------------------------------------

  /// Default color for the user's message bubbles.
  static const Color userBubble = Color(0xFF3B82F6);

  /// Default color for the user's message text.
  static const Color userText = Colors.white;

  /// Default color for the AI's message bubbles.
  static const Color aiBubble = Color(0xFF374151);

  /// Default color for the AI's message text.
  static const Color aiText = Colors.white;

  /// Default color for quoted/dialogue text ("...").
  static const Color dialogue = Colors.amberAccent;

  /// Default color for action/emote text (*...*).
  static const Color action = Color(0xFF90CAF9);

  // ---------------------------------------------------------------------------
  // Light-mode backgrounds
  // ---------------------------------------------------------------------------

  /// Light-mode scaffold background.
  static const Color lightBackground = Color(0xFFF3F4F6);

  /// Light-mode card/container background.
  static const Color lightCard = Colors.white;

  /// Light-mode surface background for dialogs and panels.
  static const Color lightSurface = Color(0xFFE5E7EB);

  // ---------------------------------------------------------------------------
  // Chat appearance defaults — light mode
  // ---------------------------------------------------------------------------

  /// Default user bubble color in light mode.
  static const Color userBubbleLight = Color(0xFF3B82F6);

  /// Default user text color in light mode.
  static const Color userTextLight = Colors.white;

  /// Default AI bubble color in light mode.
  static const Color aiBubbleLight = Color(0xFFE5E7EB);

  /// Default AI text color in light mode.
  static const Color aiTextLight = Colors.black87;

  /// Default dialogue color in light mode.
  static const Color dialogueLight = Color(0xFFB45309);

  /// Default action color in light mode.
  static const Color actionLight = Color(0xFF1565C0);

  // ---------------------------------------------------------------------------
  // Brightness-aware text/background helpers
  // ---------------------------------------------------------------------------

  /// True when the current brightness is light.
  static bool isLight(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light;

  /// Primary text color for the current brightness.
  static Color textPrimary(BuildContext context) =>
      isLight(context) ? Colors.black87 : Colors.white;

  /// Secondary text color for the current brightness.
  static Color textSecondary(BuildContext context) =>
      isLight(context) ? Colors.black54 : Colors.white70;

  /// Tertiary text color for the current brightness.
  static Color textTertiary(BuildContext context) =>
      isLight(context) ? Colors.black45 : Colors.white38;

  /// Resolves a dark/light color pair based on current brightness.
  static Color resolve(BuildContext context, Color dark, Color light) =>
      isLight(context) ? light : dark;

  /// Background for the current brightness.
  static Color backgroundOf(BuildContext context) =>
      resolve(context, background, lightBackground);

  /// Card color for the current brightness.
  static Color cardOf(BuildContext context) =>
      resolve(context, card, lightCard);

  /// Surface color for the current brightness.
  static Color surfaceOf(BuildContext context) =>
      resolve(context, surface, lightSurface);

  // ---------------------------------------------------------------------------
  // Preset palette for color pickers
  // ---------------------------------------------------------------------------

  /// Palette shown in color picker dialogs (no duplicates).
  static const List<Color> presetColors = [
    Color(0xFF3B82F6), // Blue
    Color(0xFF10B981), // Emerald
    Color(0xFFF59E0B), // Amber
    Color(0xFFEF4444), // Red
    Color(0xFF8B5CF6), // Purple
    Color(0xFFEC4899), // Pink
    Color(0xFF14B8A6), // Teal
    Color(0xFFF97316), // Orange
    Color(0xFF6366F1), // Indigo
    Color(0xFF06B6D4), // Cyan
    Color(0xFF84CC16), // Lime
  ];
}
