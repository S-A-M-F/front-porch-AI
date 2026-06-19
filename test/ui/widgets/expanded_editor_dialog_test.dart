import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/widgets/widgets.dart';

Widget _buildApp({
  required String title,
  required TextEditingController controller,
  String hintText = '',
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showExpandedEditorDialog(
            context: context,
            title: title,
            controller: controller,
            hintText: hintText,
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  );
}

void main() {
  group('showExpandedEditorDialog', () {
    testWidgets('opens dialog with correct title', (tester) async {
      await tester.pumpWidget(_buildApp(
        title: 'Edit Description',
        controller: TextEditingController(),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Description'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);
    });

    testWidgets('pre-fills text from TextEditingController', (tester) async {
      final controller = TextEditingController(text: 'initial text');
      await tester.pumpWidget(_buildApp(
        title: 'Editor',
        controller: controller,
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('initial text'), findsOneWidget);
    });

    testWidgets('pre-fills text from StyledTextController', (tester) async {
      final controller = StyledTextController(
        text: 'styled content',
        preset: StyledTextPreset.macros,
      );
      await tester.pumpWidget(_buildApp(
        title: 'Editor',
        controller: controller,
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('styled content'), findsOneWidget);
    });

    testWidgets('Cancel discards changes', (tester) async {
      final controller = TextEditingController(text: 'original');
      await tester.pumpWidget(_buildApp(
        title: 'Editor',
        controller: controller,
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(AppTextField), 'modified text');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(controller.text, 'original');
    });

    testWidgets('Apply copies text back to original controller',
        (tester) async {
      final controller = TextEditingController(text: 'original');
      await tester.pumpWidget(_buildApp(
        title: 'Editor',
        controller: controller,
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(AppTextField), 'updated text');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(controller.text, 'updated text');
    });

    testWidgets('Apply works with StyledTextController', (tester) async {
      final controller = StyledTextController(
        text: 'before',
        preset: StyledTextPreset.macros,
      );
      await tester.pumpWidget(_buildApp(
        title: 'Editor',
        controller: controller,
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(AppTextField), 'after');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(controller.text, 'after');
    });

    testWidgets('shows hint text when provided', (tester) async {
      await tester.pumpWidget(_buildApp(
        title: 'Editor',
        controller: TextEditingController(),
        hintText: 'Enter your text here...',
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your text here...'), findsOneWidget);
    });
  });
}
