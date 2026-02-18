import 'dart:io';
import 'package:flutter/material.dart';


/// Generates consistent, distinct colors for personas based on their ID.
/// Used for personas without avatars to provide visual distinction.
class PersonaColors {
  // Palette of distinct, vibrant colors
  static const List<Color> _palette = [
    Color(0xFF3B82F6), // Blue
    Color(0xFF8B5CF6), // Purple
    Color(0xFFEC4899), // Pink
    Color(0xFFEF4444), // Red
    Color(0xFFF59E0B), // Amber
    Color(0xFF10B981), // Green
    Color(0xFF06B6D4), // Cyan
    Color(0xFF6366F1), // Indigo
    Color(0xFFF97316), // Orange
    Color(0xFF84CC16), // Lime
    Color(0xFF14B8A6), // Teal
    Color(0xFFA855F7), // Violet
  ];

  /// Get a consistent color for a given persona ID
  static Color getColorForPersona(String personaId) {
    // Use hash of ID to deterministically select a color
    final hash = personaId.hashCode.abs();
    return _palette[hash % _palette.length];
  }

  /// Get a CircleAvatar for a persona with color-coding when no avatar exists
  static Widget buildPersonaAvatar({
    required String? avatarPath,
    required String personaId,
    required double radius,
    IconData icon = Icons.person,
    double? iconSize,
  }) {
    if (avatarPath != null) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: FileImage(File(avatarPath)),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: getColorForPersona(personaId),
      child: Icon(
        icon,
        size: iconSize ?? radius * 1.125,
        color: Colors.white,
      ),
    );
  }
}
