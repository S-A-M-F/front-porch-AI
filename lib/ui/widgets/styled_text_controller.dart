import 'dart:async';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SpellCheckResults, SuggestionSpan;

import 'package:front_porch_ai/services/desktop_spell_check_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/app_text_field.dart';

class StyledTextPreset {
  final RegExp pattern;
  final TextStyle Function(BuildContext context, String match, TextStyle? base) styler;

  const StyledTextPreset(this.pattern, this.styler);

  static final prose = StyledTextPreset(
    RegExp(r'("[^"]*")|(\*[^*]*\*)|({{[^}]*}})'),
    (ctx, match, base) {
      if (match.startsWith('"')) {
        return (base ?? const TextStyle()).copyWith(
          color: AppColors.resolve(ctx, Colors.amberAccent, const Color(0xFFB45309)),
          fontWeight: FontWeight.w500,
        );
      }
      if (match.startsWith('*')) {
        return (base ?? const TextStyle()).copyWith(
          color: AppColors.resolve(ctx, const Color(0xFF90CAF9), const Color(0xFF1565C0)),
        );
      }
      return (base ?? const TextStyle()).copyWith(
        color: AppColors.resolve(ctx, Colors.tealAccent, const Color(0xFF0D9488)),
      );
    },
  );

  static final macros = StyledTextPreset(
    RegExp(r'({{[^}]*}})'),
    (ctx, match, base) {
      return (base ?? const TextStyle()).copyWith(
        color: AppColors.resolve(ctx, Colors.tealAccent, const Color(0xFF0D9488)),
      );
    },
  );
}

class StyledTextController extends TextEditingController
    implements SpellCheckResultsProvider {
  static final _spellService = DesktopSpellCheckService();

  final StyledTextPreset preset;

  StyledTextController({super.text, StyledTextPreset? preset})
      : preset = preset ?? StyledTextPreset.prose {
    addListener(_onTextChanged);
  }

  // ── Spell check cache ──
  String? _lastCheckedText;
  final List<TextRange> _misspelledRanges = [];
  final Map<int, List<String>> _suggestions = {};
  Timer? _spellDebounce;
  bool _spellCheckInFlight = false;
  bool _ignoreTextChange = false;

  void applySpellResults(String checkedText, List<SuggestionSpan> spans) {
    _lastCheckedText = checkedText;
    _misspelledRanges
      ..clear()
      ..addAll(spans.map((s) => s.range));
    _misspelledRanges.sort((a, b) => a.start.compareTo(b.start));
    _suggestions
      ..clear()
      ..addEntries(spans.map((s) => MapEntry(s.range.start, s.suggestions)));
  }

  void clearSpellResults() {
    _lastCheckedText = null;
    _misspelledRanges.clear();
    _suggestions.clear();
  }

  @override
  SpellCheckResults? get spellCheckResults {
    if (_misspelledRanges.isEmpty || _lastCheckedText != text) return null;
    return SpellCheckResults(
      _lastCheckedText!,
      _misspelledRanges.map((r) {
        return SuggestionSpan(r, _suggestions[r.start] ?? <String>[]);
      }).toList(),
    );
  }

  // ── Spell check orchestration ──

  void _onTextChanged() {
    if (_ignoreTextChange) return;
    _spellDebounce?.cancel();
    _spellDebounce = Timer(const Duration(milliseconds: 300), _trySpellCheck);
  }

  void _trySpellCheck() {
    if (!_spellCheckInFlight) {
      _runSpellCheck();
    }
  }

  Future<void> _runSpellCheck() async {
    if (_spellCheckInFlight) return;
    _spellCheckInFlight = true;
    final text = this.text;
    _ignoreTextChange = true;
    try {
      if (text.trim().isEmpty) {
        clearSpellResults();
        notifyListeners();
        return;
      }
      final locale = PlatformDispatcher.instance.locale;
      final results =
          await _spellService.fetchSpellCheckSuggestions(locale, text);
      if (text != this.text) return;
      if (results != null && results.isNotEmpty) {
        applySpellResults(text, results);
      } else {
        clearSpellResults();
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Spell check error: $e');
      clearSpellResults();
      notifyListeners();
    } finally {
      _ignoreTextChange = false;
      _spellCheckInFlight = false;
      if (text != this.text) {
        _spellDebounce?.cancel();
        _spellDebounce = Timer(
          const Duration(milliseconds: 300),
          _trySpellCheck,
        );
      }
    }
  }

  // ── Styled text span building ──

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final text = this.text;
    final matches = preset.pattern.allMatches(text);
    final useSpellCheck =
        _lastCheckedText == text && _misspelledRanges.isNotEmpty;

    final segments = <({String text, TextStyle? style, int offset})>[];
    int lastEnd = 0;

    void addSegment(String segText, TextStyle? segStyle, int segOffset) {
      segments.add((text: segText, style: segStyle, offset: segOffset));
    }

    if (matches.isEmpty) {
      addSegment(text, style, 0);
    } else {
      for (final match in matches) {
        if (match.start > lastEnd) {
          addSegment(text.substring(lastEnd, match.start), style, lastEnd);
        }
        final matchText = match.group(0)!;
        addSegment(
          matchText,
          preset.styler(context, matchText, style),
          match.start,
        );
        lastEnd = match.end;
      }
      if (lastEnd < text.length) {
        addSegment(text.substring(lastEnd), style, lastEnd);
      }
    }

    if (!useSpellCheck) {
      return TextSpan(
        children: segments
            .map((s) => TextSpan(text: s.text, style: s.style))
            .toList(),
        style: style,
      );
    }

    const misspelledTextStyle = TextStyle(
      decoration: TextDecoration.underline,
      decorationColor: Colors.redAccent,
      decorationStyle: TextDecorationStyle.wavy,
    );

    final children = <TextSpan>[];
    for (final seg in segments) {
      final spanStart = seg.offset;
      final spanEnd = seg.offset + seg.text.length;

      final intersecting = <({int start, int end})>[];
      for (final range in _misspelledRanges) {
        final isectStart = range.start > spanStart ? range.start : spanStart;
        final isectEnd = range.end < spanEnd ? range.end : spanEnd;
        if (isectStart < isectEnd) {
          intersecting.add((start: isectStart, end: isectEnd));
        }
      }

      if (intersecting.isEmpty) {
        children.add(TextSpan(text: seg.text, style: seg.style));
        continue;
      }

      int splitAt = 0;
      for (final isect in intersecting) {
        final localStart =
            (isect.start - seg.offset).clamp(0, seg.text.length);
        if (localStart > splitAt) {
          children.add(
            TextSpan(
              text: seg.text.substring(splitAt, localStart),
              style: seg.style,
            ),
          );
        }
        final localEnd = (isect.end - seg.offset).clamp(0, seg.text.length);
        children.add(
          TextSpan(
            text: seg.text.substring(localStart, localEnd),
            style: seg.style?.merge(misspelledTextStyle) ?? misspelledTextStyle,
          ),
        );
        splitAt = localEnd;
      }
      if (splitAt < seg.text.length) {
        children.add(
          TextSpan(text: seg.text.substring(splitAt), style: seg.style),
        );
      }
    }

    return TextSpan(children: children, style: style);
  }

  @override
  void dispose() {
    _spellDebounce?.cancel();
    super.dispose();
  }
}
