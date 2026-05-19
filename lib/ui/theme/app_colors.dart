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
