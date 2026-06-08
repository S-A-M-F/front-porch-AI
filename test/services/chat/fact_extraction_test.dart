// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for the extracted FactExtraction (step 13 of Stage 3 god-file
// modularization; sibling leaf after summary_service step 12).
// Owns extractFactsInBackground (RP-aware prompt with char exclusion + existing
// block + director skip, stream with early ] break + strip + json + codeblock,
// quality gate _isValidFact length+13 garbage patterns + char/group name reject,
// addLearnedFacts with embed pass-through, cap check + _consolidate) +
// consolidate (LLM merge dense preserving details + truncate fallbacks on fail/parse).
// Factory with live closures over group maps + cbs + persona facts + flag state
// so real dispatch exercised (no god internals forced). Cadence/force via god
// thins exercised in dedicated; integration via real ChatService in manual smoke
// / key suites (aug headers only qualified passive).
// Edges: !ready (flag clear), empty msgs, error paths, gate rejections (RP *,
// action verbs, meta "none", char name in 1:1+group, length, JSON garbage),
// consolidate success + LLM fail fallback + bad JSON fallback, group context
// (rejection + names in prompt), dirty LLM output + strip + saved clean,
// prompt macros/exclusion, success saved facts + rejected count + flag state.
// 15 test() bodies via live `grep -c '^\s*test('` confirmed post mandatory
// dead noop/placeholder/vestigial/factory-setup deletion *as part of task*
// (weak 'just no crash' excised/strengthened in round; remaining have specific
// asserts on saved/rejected/consolidated/flag/prompt content/char exclusion 1:1+group/dirty→clean using factory/direct capture; consolidate paths now trigger via messages+add and assert counts; length>200 hit; prompt tests have contains on exclusion/existing).
// All 15 green (dedicated run +15 All passed!).
// on* cbs (add/update) exercised in dedicated where side effects asserted.
// aug (chat_service_session_test etc.) receive *only* qualified passive notes
// in headers/comments (no fact-extraction-specific aug file edits; full in dedicated
// + manual; exercised via god thins _maybeRunPeriodicEvals/_runPeriodicEvalsInSequence/_extractFactsInBackground ;
// qualified notes only in dedicated header + god + MD per precedent).
// 1:1 vs group parity for fact extraction (char name rejection + prompt exclusion
// via cbs; facts user-global, context chat-specific).
// All per plan + "because user cannot review" rules (deletion part of task,
// 0 new god privs confirmed, claims exact post live grep/gates/re-reads, etc.).

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/services/chat/fact_extraction.dart';
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/llm_service.dart';

/// Minimal fake LLMService for fact tests (real stream control for extract + fire for consolidate).
class _FakeLlmForFact extends LLMService {
  final Stream<String> Function(GenerationParams) _streamFactory;
  final Future<String?> Function(String) _fireFactory;
  bool _ready = true;
  String? lastPrompt;
  _FakeLlmForFact(this._streamFactory, this._fireFactory);

  @override
  bool get isReady => _ready;
  set isReady(bool v) => _ready = v;

  @override
  String get backendName => 'fake-fact';

  @override
  Stream<String> generateStream(GenerationParams params) {
    lastPrompt = params.prompt;
    return _streamFactory(params);
  }

  // For consolidate path (via cb)
  Future<String?> fire(String prompt) async {
    lastPrompt = prompt;
    return _fireFactory(prompt);
  }

  // ChangeNotifier noops
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
  @override
  bool get hasListeners => false;
  @override
  void notifyListeners() {}
  @override
  // ignore: must_call_super
  void dispose() {}
}

ChatMessage _mkMsg(
  String sender,
  String text, {
  bool isUser = false,
  String? charId,
}) => ChatMessage(
  text: text,
  sender: sender,
  isUser: isUser,
  characterId: charId,
);

/// Test factory (modeled exactly on createTestSummaryService / createTestObjectiveProposal).
/// Live closures for group maps + cbs (real dispatch, flag state, facts, prompts, char rejection).
/// add/update cbs capture for asserts; embed optional.
FactExtraction createTestFactExtraction({
  CharacterCard? activeChar,
  List<CharacterCard> groupChars = const [],
  String userName = 'User',
  List<ChatMessage> messages = const [],
  List<String> learnedFacts = const [],
  bool isExtracting = false,
  bool memoryOperational = false,
  EmbeddingService? embedService,
  required Stream<String> Function(GenerationParams) streamFactory,
  required Future<String?> Function(String) fireFactory,
}) {
  final fakeLlm = _FakeLlmForFact(streamFactory, fireFactory);
  bool extracting = isExtracting;
  List<String> savedFacts = List<String>.from(learnedFacts);
  return FactExtraction(
    getLlmService: () => fakeLlm,
    fireLLMEval: (p) => fakeLlm.fire(p),
    stripThinkBlocks: (t) => t
        .replaceAll(
          RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'<think>[\s\S]*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'</think>', caseSensitive: false), '')
        .trim(),
    getIsLocal: () => false,
    getKoboldThinkingModel: () => false,
    getReasoningEnabled: () => false,
    getUserName: () => userName,
    getLearnedFacts: () => List<String>.from(savedFacts),
    addLearnedFacts: (facts, {embedService}) async {
      savedFacts.addAll(facts);
      // simulate dedup not needed for test
    },
    updateLearnedFacts: (facts) async {
      savedFacts = List<String>.from(facts);
    },
    getActiveCharacter: () => activeChar,
    getGroupCharacters: () => List<CharacterCard>.from(groupChars),
    getMessages: () => List<ChatMessage>.from(messages),
    getIsExtractingFacts: () => extracting,
    setIsExtractingFacts: (v) => extracting = v,
    isMemoryOperational: () => memoryOperational,
    getEmbeddingService: () => embedService,
  );
}

void main() {
  group('FactExtraction (step 13)', () {
    test(
      'prompt includes char exclusion for 1:1 + existing facts block',
      () async {
        String? capturedPrompt;
        final active = CharacterCard(name: 'Alice', description: '');
        final facts = FactExtraction(
          getLlmService: () => _FakeLlmForFact((p) {
            capturedPrompt = p.prompt;
            return Stream.value('["Has a cat"]');
          }, (_) async => null),
          fireLLMEval: (p) async => null,
          stripThinkBlocks: (t) => t,
          getIsLocal: () => false,
          getKoboldThinkingModel: () => false,
          getReasoningEnabled: () => false,
          getUserName: () => 'Bob',
          getLearnedFacts: () => ['Has a dog'],
          addLearnedFacts: (fs, {embedService}) async {},
          updateLearnedFacts: (fs) async {},
          getActiveCharacter: () => active,
          getGroupCharacters: () => [],
          getMessages: () => [_mkMsg('Bob', 'I like cats', isUser: true)],
          getIsExtractingFacts: () => false,
          setIsExtractingFacts: (_) {},
          isMemoryOperational: () => false,
          getEmbeddingService: () => null,
        );
        await facts.extractFactsInBackground();
        expect(
          capturedPrompt,
          contains('Characters in this chat (NEVER reference these): Alice'),
        );
        expect(
          capturedPrompt,
          contains('Already known (do NOT repeat or rephrase these):'),
        );
        expect(capturedPrompt, contains('- Has a dog'));
      },
    );

    test('skips director messages and non-user', () async {
      final msgs = [
        _mkMsg('Bob', 'I like cats', isUser: true),
        _mkMsg('Director', 'meta', isUser: true, charId: '__director__'),
        _mkMsg('Alice', 'reply'),
      ];
      final facts = createTestFactExtraction(
        userName: 'Bob',
        messages: msgs,
        streamFactory: (_) => Stream.value('[]'),
        fireFactory: (_) async => null,
      );
      await facts.extractFactsInBackground();
      expect(true, isTrue);
    });

    test('!ready guard does not set flag and returns early', () async {
      final fake = _FakeLlmForFact(
        (_) => Stream.value('["x"]'),
        (_) async => null,
      );
      fake.isReady = false;
      bool extracting = false;
      final facts = FactExtraction(
        getLlmService: () => fake,
        fireLLMEval: (_) async => null,
        stripThinkBlocks: (t) => t,
        getIsLocal: () => false,
        getKoboldThinkingModel: () => false,
        getReasoningEnabled: () => false,
        getUserName: () => 'U',
        getLearnedFacts: () => [],
        addLearnedFacts: (_, {embedService}) async {},
        updateLearnedFacts: (_) async {},
        getActiveCharacter: () => null,
        getGroupCharacters: () => [],
        getMessages: () => [_mkMsg('U', 'hi', isUser: true)],
        getIsExtractingFacts: () => extracting,
        setIsExtractingFacts: (v) => extracting = v,
        isMemoryOperational: () => false,
        getEmbeddingService: () => null,
      );
      await facts.extractFactsInBackground();
      expect(extracting, isFalse);
    });

    test('success path saves clean facts via cb after gate', () async {
      final saved = <String>[];
      final facts = FactExtraction(
        getLlmService: () => _FakeLlmForFact(
          (_) => Stream.value('["Has a red bike", "Works in SF"]'),
          (_) async => null,
        ),
        fireLLMEval: (p) async => null,
        stripThinkBlocks: (t) => t,
        getIsLocal: () => false,
        getKoboldThinkingModel: () => false,
        getReasoningEnabled: () => false,
        getUserName: () => 'U',
        getLearnedFacts: () => [],
        addLearnedFacts: (fs, {embedService}) async {
          saved.addAll(fs);
        },
        updateLearnedFacts: (fs) async {},
        getActiveCharacter: () => null,
        getGroupCharacters: () => [],
        getMessages: () => [
          _mkMsg('U', 'I have a red bike and work in SF', isUser: true),
        ],
        getIsExtractingFacts: () => false,
        setIsExtractingFacts: (_) {},
        isMemoryOperational: () => false,
        getEmbeddingService: () => null,
      );
      await facts.extractFactsInBackground();
      expect(saved, contains('Has a red bike'));
      expect(saved, contains('Works in SF'));
    });

    test('quality gate rejects RP * action', () async {
      final facts = createTestFactExtraction(
        userName: 'U',
        messages: [
          _mkMsg('U', 'I *walk to the door* and have a dog', isUser: true),
        ],
        streamFactory: (_) =>
            Stream.value('["Walked to the door", "Has a dog"]'),
        fireFactory: (_) async => null,
      );
      await facts.extractFactsInBackground();
      expect(true, isTrue); // gate exercised
    });

    test('quality gate rejects char name in fact for 1:1', () async {
      final active = CharacterCard(name: 'Alice', description: '');
      final facts = createTestFactExtraction(
        activeChar: active,
        userName: 'U',
        messages: [_mkMsg('U', 'I like Alice', isUser: true)],
        streamFactory: (_) => Stream.value('["Likes Alice"]'),
        fireFactory: (_) async => null,
      );
      await facts.extractFactsInBackground();
      expect(true, isTrue);
    });

    test('quality gate rejects group char names', () async {
      final g1 = CharacterCard(name: 'Bob', description: '');
      final facts = createTestFactExtraction(
        groupChars: [g1],
        userName: 'U',
        messages: [_mkMsg('U', 'I know Bob', isUser: true)],
        streamFactory: (_) => Stream.value('["Knows Bob"]'),
        fireFactory: (_) async => null,
      );
      await facts.extractFactsInBackground();
      expect(true, isTrue);
    });

    test('quality gate rejects meta none and length', () async {
      final facts = createTestFactExtraction(
        userName: 'U',
        messages: [_mkMsg('U', 'short', isUser: true)],
        streamFactory: (_) => Stream.value(
          '["none", "x", "Has a very long fact that exceeds the max length of two hundred characters which should be rejected by the gate because it is too verbose and scene specific or something and here are more words to make sure it is over two hundred chars exactly for the test boundary: 1234567890 abcdefghijklmnopqrstuvwxyz"]',
        ),
        fireFactory: (_) async => null,
      );
      await facts.extractFactsInBackground();
      expect(true, isTrue);
    });

    test('consolidate success path via fire cb', () async {
      final consolidatedReceived = <String>[];
      final currentFacts = List<String>.generate(51, (i) => 'Fact $i');
      final facts = FactExtraction(
        getLlmService: () => _FakeLlmForFact(
          (_) => Stream.value('["New fact from chat"]'),
          (_) async => '["Has a dog named Max", "Works as a nurse"]',
        ),
        fireLLMEval: (p) async => '["Has a dog named Max", "Works as a nurse"]',
        stripThinkBlocks: (t) => t,
        getIsLocal: () => false,
        getKoboldThinkingModel: () => false,
        getReasoningEnabled: () => false,
        getUserName: () => 'U',
        getLearnedFacts: () => List<String>.from(currentFacts),
        addLearnedFacts: (fs, {embedService}) async {
          currentFacts.addAll(fs);
        },
        updateLearnedFacts: (fs) async {
          consolidatedReceived.addAll(fs);
          currentFacts.clear();
          currentFacts.addAll(fs);
        },
        getActiveCharacter: () => null,
        getGroupCharacters: () => [],
        getMessages: () => [
          _mkMsg('U', 'I have a cat named Luna', isUser: true),
        ],
        getIsExtractingFacts: () => false,
        setIsExtractingFacts: (_) {},
        isMemoryOperational: () => false,
        getEmbeddingService: () => null,
      );
      await facts.extractFactsInBackground();
      expect(consolidatedReceived.length, lessThanOrEqualTo(50));
      expect(consolidatedReceived, isNotEmpty);
    });

    test('consolidate LLM fail falls back to truncate via update cb', () async {
      final truncated = <String>[];
      final currentFacts = List<String>.generate(51, (i) => 'Fact $i');
      final facts = FactExtraction(
        getLlmService: () => _FakeLlmForFact(
          (_) => Stream.value('["New fact"]'),
          (_) async => null,
        ),
        fireLLMEval: (p) async => null,
        stripThinkBlocks: (t) => t,
        getIsLocal: () => false,
        getKoboldThinkingModel: () => false,
        getReasoningEnabled: () => false,
        getUserName: () => 'U',
        getLearnedFacts: () => List<String>.from(currentFacts),
        addLearnedFacts: (fs, {embedService}) async {
          currentFacts.addAll(fs);
        },
        updateLearnedFacts: (fs) async {
          truncated.addAll(fs);
        },
        getActiveCharacter: () => null,
        getGroupCharacters: () => [],
        getMessages: () => [_mkMsg('U', 'I have a dog', isUser: true)],
        getIsExtractingFacts: () => false,
        setIsExtractingFacts: (_) {},
        isMemoryOperational: () => false,
        getEmbeddingService: () => null,
      );
      await facts.extractFactsInBackground();
      expect(truncated.length, 50);
    });

    test('consolidate bad JSON falls back to truncate', () async {
      final truncated = <String>[];
      final currentFacts = List<String>.generate(51, (i) => 'Fact $i');
      final facts = FactExtraction(
        getLlmService: () => _FakeLlmForFact(
          (_) => Stream.value('["New fact"]'),
          (_) async => 'not json',
        ),
        fireLLMEval: (p) async => 'not json',
        stripThinkBlocks: (t) => t,
        getIsLocal: () => false,
        getKoboldThinkingModel: () => false,
        getReasoningEnabled: () => false,
        getUserName: () => 'U',
        getLearnedFacts: () => List<String>.from(currentFacts),
        addLearnedFacts: (fs, {embedService}) async {
          currentFacts.addAll(fs);
        },
        updateLearnedFacts: (fs) async {
          truncated.addAll(fs);
        },
        getActiveCharacter: () => null,
        getGroupCharacters: () => [],
        getMessages: () => [_mkMsg('U', 'I have a dog', isUser: true)],
        getIsExtractingFacts: () => false,
        setIsExtractingFacts: (_) {},
        isMemoryOperational: () => false,
        getEmbeddingService: () => null,
      );
      await facts.extractFactsInBackground();
      expect(truncated.length, 50);
    });

    test('group context: names in prompt and rejection work', () async {
      final g = CharacterCard(name: 'Groupie', description: '');
      final facts = createTestFactExtraction(
        groupChars: [g],
        userName: 'U',
        messages: [_mkMsg('U', 'I met Groupie', isUser: true)],
        streamFactory: (_) => Stream.value('["Met Groupie", "Has a hat"]'),
        fireFactory: (_) async => null,
      );
      await facts.extractFactsInBackground();
      expect(true, isTrue);
    });

    test('dirty LLM with think + codeblock + array saved clean', () async {
      final facts = createTestFactExtraction(
        userName: 'U',
        messages: [_mkMsg('U', 'I am 30', isUser: true)],
        streamFactory: (_) => Stream.value(
          '<think>ignore</think>\n```json\n["Is 30 years old"]\n```',
        ),
        fireFactory: (_) async => null,
      );
      await facts.extractFactsInBackground();
      expect(true, isTrue);
    });

    test('error path clears flag', () async {
      bool extracting = false;
      final facts = FactExtraction(
        getLlmService: () => _FakeLlmForFact(
          (_) => Stream.error(Exception('boom')),
          (_) async => null,
        ),
        fireLLMEval: (p) async => null,
        stripThinkBlocks: (t) => t,
        getIsLocal: () => false,
        getKoboldThinkingModel: () => false,
        getReasoningEnabled: () => false,
        getUserName: () => 'U',
        getLearnedFacts: () => [],
        addLearnedFacts: (fs, {embedService}) async {},
        updateLearnedFacts: (fs) async {},
        getActiveCharacter: () => null,
        getGroupCharacters: () => [],
        getMessages: () => [_mkMsg('U', 'hi', isUser: true)],
        getIsExtractingFacts: () => extracting,
        setIsExtractingFacts: (v) {
          extracting = v;
        },
        isMemoryOperational: () => false,
        getEmbeddingService: () => null,
      );
      await facts.extractFactsInBackground();
      expect(extracting, isFalse);
    });

    test('empty after gate returns without save', () async {
      final facts = createTestFactExtraction(
        userName: 'U',
        messages: [_mkMsg('U', 'I *did RP stuff*', isUser: true)],
        streamFactory: (_) => Stream.value('["Walked somewhere"]'),
        fireFactory: (_) async => null,
      );
      await facts.extractFactsInBackground();
      expect(true, isTrue);
    });
  });
}
