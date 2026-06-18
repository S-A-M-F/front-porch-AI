import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/macro_resolver.dart';

void main() {
  group('MacroResolver', () {
    late MacroResolver resolver;
    late MacroContext ctx;

    setUp(() {
      resolver = MacroResolver();
      ctx = const MacroContext(userName: 'Alex', characterName: 'Luna');
    });

    test('resolves {{char}}', () {
      expect(resolver.resolve('{{char}} is here', ctx), 'Luna is here');
    });

    test('resolves {{user}}', () {
      expect(resolver.resolve('{{user}} says hi', ctx), 'Alex says hi');
    });

    test('resolves <char> legacy syntax', () {
      expect(resolver.resolve('<char> is here', ctx), 'Luna is here');
    });

    test('resolves <user> legacy syntax', () {
      expect(resolver.resolve('<user> says hi', ctx), 'Alex says hi');
    });

    test('case insensitive', () {
      expect(
        resolver.resolve('{{CHAR}} {{User}} {{char}} {{user}}', ctx),
        'Luna Alex Luna Alex',
      );
    });

    test('resolves {{words}}', () {
      final wCtx = const MacroContext(
        userName: 'A',
        characterName: 'B',
        summaryMaxWords: 50,
      );
      expect(resolver.resolve('Use {{words}} words', wCtx), 'Use 50 words');
    });

    test('{{words}} with no max returns empty', () {
      expect(resolver.resolve('{{words}}', ctx), '');
    });

    test('unknown macros pass through', () {
      expect(
        resolver.resolve('{{unknown}} here', ctx),
        '{{unknown}} here',
      );
    });

    test('mixed known and unknown', () {
      expect(
        resolver.resolve('{{char}} {{unknown}} {{user}}', ctx),
        'Luna {{unknown}} Alex',
      );
    });

    test('multiple occurrences', () {
      expect(
        resolver.resolve('{{char}} and {{char}}', ctx),
        'Luna and Luna',
      );
    });

    test('empty input returns empty', () {
      expect(resolver.resolve('', ctx), '');
    });

    test('no macros returns same string', () {
      expect(resolver.resolve('plain text', ctx), 'plain text');
    });

    test('custom registration', () {
      resolver.register('greet', (args, ctx) => 'Hello ${ctx.userName}!');
      expect(resolver.resolve('{{greet}}', ctx), 'Hello Alex!');
    });

    test('macro with ::args', () {
      resolver.register('repeat', (args, ctx) => args.join(','));
      expect(
        resolver.resolve('{{repeat::a::b::c}}', ctx),
        'a,b,c',
      );
    });
  });
}
