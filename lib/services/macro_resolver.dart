// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Context passed to every macro resolver function.
class MacroContext {
  final String? userName;
  final String? characterName;
  final int? summaryMaxWords;

  const MacroContext({
    this.userName,
    this.characterName,
    this.summaryMaxWords,
  });
}

/// Internal registry entry.
class _MacroEntry {
  final String name;
  final String Function(List<String> args, MacroContext ctx) fn;
  const _MacroEntry({required this.name, required this.fn});
}

/// Central macro engine. Has a name → resolver registry.
/// Replace all known `{{...}}` patterns in text via [resolve].
/// Unknown macros pass through unchanged.
class MacroResolver {
  final Map<String, _MacroEntry> _registry = {};
  bool _defaultsRegistered = false;

  MacroResolver() {
    _ensureDefaults();
  }

  void _ensureDefaults() {
    if (_defaultsRegistered) return;
    _defaultsRegistered = true;
    register('user', (args, ctx) => ctx.userName ?? '');
    register('char', (args, ctx) => ctx.characterName ?? '');
    register('words', (args, ctx) => ctx.summaryMaxWords?.toString() ?? '');
  }

  void register(
    String name,
    String Function(List<String> args, MacroContext ctx) fn,
  ) {
    _registry[name.toLowerCase()] = _MacroEntry(name: name, fn: fn);
  }

  /// Replaces all known `{{...}}` macros and legacy `<user>`/`<char>` syntax.
  /// Unknown macros pass through unchanged.
  /// Returns empty string for null/empty input.
  String resolve(String text, MacroContext context) {
    if (text.isEmpty) return text;

    var result = text;

    // Legacy angle-bracket syntax (case-insensitive)
    final charName = context.characterName ?? '';
    final userName = context.userName ?? '';
    result = result.replaceAll(
      RegExp(r'<char>', caseSensitive: false),
      charName,
    );
    result = result.replaceAll(
      RegExp(r'<user>', caseSensitive: false),
      userName,
    );

    // {{macro}} syntax via regex — walk all matches
    result = result.replaceAllMapped(
      RegExp(r'\{\{(\w+)(?:::(.+?))?\}\}'),
      (m) {
        final name = m.group(1)!.toLowerCase();
        final argsStr = m.group(2);
        final args = argsStr != null ? argsStr.split('::') : <String>[];
        final entry = _registry[name];
        if (entry != null) return entry.fn(args, context);
        return m.group(0)!; // unknown macro → pass through
      },
    );

    return result;
  }
}
