import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/pages/chat_page.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

Widget _buildApp() {
  return const MaterialApp(home: Scaffold(body: SizedBox.shrink()));
}

BuildContext _pumpContext(WidgetTester tester) {
  return tester.element(find.byType(SizedBox));
}

void main() {
  group('SuggestionSpan API compatibility', () {
    test('SuggestionSpan.range is accessible', () {
      final span = SuggestionSpan(TextRange(start: 0, end: 5), ['hello']);
      expect(span.range.start, 0);
      expect(span.range.end, 5);
    });

    test('SuggestionSpan.suggestions is accessible', () {
      final span = SuggestionSpan(TextRange(start: 0, end: 5), [
        'hello',
        'world',
      ]);
      expect(span.suggestions, hasLength(2));
    });
  });

  group('SpellCheckResults API compatibility', () {
    test('SpellCheckResults.spellCheckedText is accessible', () {
      final results = SpellCheckResults('hello world', [
        SuggestionSpan(TextRange(start: 0, end: 5), ['hello']),
      ]);
      expect(results.spellCheckedText, 'hello world');
    });

    test('SpellCheckResults.suggestionSpans is accessible', () {
      final results = SpellCheckResults('hello world', [
        SuggestionSpan(TextRange(start: 0, end: 5), ['hello']),
      ]);
      expect(results.suggestionSpans, hasLength(1));
    });
  });

  group('StyledTextController.spellCheckResults getter', () {
    test('returns SpellCheckResults when cache is populated', () {
      final ctrl = StyledTextController()..text = 'hello world';
      ctrl.applySpellResults('hello world', [
        SuggestionSpan(TextRange(start: 6, end: 11), ['world']),
      ]);
      final results = ctrl.spellCheckResults;
      expect(results?.spellCheckedText, 'hello world');
      expect(results?.suggestionSpans, hasLength(1));
      expect(results?.suggestionSpans[0].suggestions, ['world']);
    });

    test('returns null when cache is empty', () {
      final ctrl = StyledTextController()..text = 'hello world';
      expect(ctrl.spellCheckResults, isNull);
    });

    test('returns null when text changed since last check', () {
      final ctrl = StyledTextController()..text = 'hello';
      ctrl.applySpellResults('hello', [
        SuggestionSpan(TextRange(start: 0, end: 5), ['hello']),
      ]);
      ctrl.text = 'changed';
      expect(ctrl.spellCheckResults, isNull);
    });

    test('clears after clearSpellResults', () {
      final ctrl = StyledTextController()..text = 'hello';
      ctrl.applySpellResults('hello', [
        SuggestionSpan(TextRange(start: 0, end: 5), ['hello']),
      ]);
      ctrl.clearSpellResults();
      expect(ctrl.spellCheckResults, isNull);
    });
  });

  group('StyledTextController.buildTextSpan override', () {
    testWidgets('accepts the standard parameters', (tester) async {
      await tester.pumpWidget(_buildApp());
      final ctrl = StyledTextController();
      final span = ctrl.buildTextSpan(
        context: _pumpContext(tester),
        style: null,
        withComposing: false,
      );
      expect(span, isA<TextSpan>());
    });

    testWidgets('produces colored spans for dialogue markers', (tester) async {
      await tester.pumpWidget(_buildApp());
      final ctrl = StyledTextController()..text = 'She said "hello" nicely';
      final span = ctrl.buildTextSpan(
        context: _pumpContext(tester),
        style: const TextStyle(color: Colors.white),
        withComposing: false,
      );
      expect(span.children, isNotNull);
    });

    testWidgets('applies wavy underline for misspelled ranges', (tester) async {
      await tester.pumpWidget(_buildApp());
      final ctrl = StyledTextController()..text = '"hello" world';
      ctrl.applySpellResults('"hello" world', [
        SuggestionSpan(TextRange(start: 8, end: 13), ['world']),
      ]);
      final span = ctrl.buildTextSpan(
        context: _pumpContext(tester),
        style: const TextStyle(color: Colors.white),
        withComposing: false,
      );
      expect(span.children, hasLength(greaterThan(1)));
    });
  });

  group('SpellCheckResultsProvider interface', () {
    test('StyledTextController implements SpellCheckResultsProvider', () {
      expect(StyledTextController(), isA<SpellCheckResultsProvider>());
    });
  });
}
