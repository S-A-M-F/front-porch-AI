// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The creator's loop, the shape Porch Stories' StoryAgent.run has and the
// maintainer asked for here: generate, gate in code, review with a second
// call, feed the objection back, bounded tries, and keep the best valid
// answer so a harsh reviewer never dead-ends the run. Plain Dart.

import 'package:flutter/foundation.dart';

/// What a reviewer said. [parsed] false means the review could not be
/// read, which accepts the output rather than failing it.
class WorldVerdict {
  const WorldVerdict({
    required this.pass,
    this.problems = const [],
    this.parsed = true,
  });

  static const skipped = WorldVerdict(pass: true, parsed: false);

  final bool pass;
  final List<String> problems;
  final bool parsed;
}

/// One line of the run log: what a stage's try produced.
class WorldLoopNote {
  const WorldLoopNote({
    required this.stage,
    required this.attempt,
    required this.verdict,
    required this.note,
  });

  final String stage;
  final int attempt;

  /// PASS, FAIL (the reviewer objected), INVALID (the gate did) or NONE
  /// (no answer).
  final String verdict;
  final String note;

  @override
  String toString() => '$stage try $attempt: $verdict — $note';
}

class WorldLoopResult<T> {
  const WorldLoopResult({
    required this.best,
    required this.notes,
    required this.tries,
    required this.passed,
    required this.bestAttempt,
  });

  /// The answer to use: the one that passed, else the valid one with the
  /// fewest gate problems (the earlier of equals), else null.
  final T? best;
  final List<WorldLoopNote> notes;
  final int tries;
  final bool passed;

  /// Which try [best] came from; 1 means the first answer stood.
  final int bestAttempt;
}

/// Runs [generate] up to [tries] times. [gate] is the Dart check whose
/// problems go back as feedback; [review] is the model's second look, asked
/// only of an answer the gate passed; its problems go back the same way.
Future<WorldLoopResult<T>> runWorldLoop<T>({
  required String stage,
  required int tries,
  required Future<T?> Function(int attempt, T? previous, List<String> feedback)
  generate,
  required List<String> Function(T output) gate,
  Future<WorldVerdict> Function(T output)? review,
  void Function(String status)? status,
  bool Function()? stop,
}) async {
  final notes = <WorldLoopNote>[];
  T? previous;
  var feedback = const <String>[];
  T? best;
  var bestProblems = 1 << 30;
  var bestAttempt = 0;
  final rounds = tries < 1 ? 1 : tries;
  for (var attempt = 1; attempt <= rounds; attempt++) {
    if (stop?.call() ?? false) break;
    status?.call(
      attempt == 1 ? stage : '$stage (revising — try $attempt of $rounds)',
    );
    final output = await generate(attempt, previous, feedback);
    if (output == null) {
      notes.add(
        WorldLoopNote(
          stage: stage,
          attempt: attempt,
          verdict: 'NONE',
          note: 'no answer',
        ),
      );
      continue;
    }
    final problems = gate(output);
    if (problems.isNotEmpty) {
      notes.add(
        WorldLoopNote(
          stage: stage,
          attempt: attempt,
          verdict: 'INVALID',
          note: problems.join('; '),
        ),
      );
      // Strictly fewer: an equally bad revise does not replace the original.
      if (problems.length < bestProblems) {
        best = output;
        bestProblems = problems.length;
        bestAttempt = attempt;
      }
      previous = output;
      feedback = problems;
      continue;
    }
    best = output;
    bestProblems = 0;
    bestAttempt = attempt;
    if (review == null) {
      notes.add(
        WorldLoopNote(
          stage: stage,
          attempt: attempt,
          verdict: 'PASS',
          note: 'gate passed',
        ),
      );
      return WorldLoopResult(
        best: best,
        notes: notes,
        tries: attempt,
        passed: true,
        bestAttempt: attempt,
      );
    }
    status?.call('$stage — checking the result…');
    final verdict = await review(output);
    if (!verdict.parsed) {
      notes.add(
        WorldLoopNote(
          stage: stage,
          attempt: attempt,
          verdict: 'PASS',
          note: 'the review could not be read, so the result was accepted',
        ),
      );
      return WorldLoopResult(
        best: best,
        notes: notes,
        tries: attempt,
        passed: true,
        bestAttempt: attempt,
      );
    }
    if (verdict.pass) {
      notes.add(
        WorldLoopNote(
          stage: stage,
          attempt: attempt,
          verdict: 'PASS',
          note: 'review passed',
        ),
      );
      return WorldLoopResult(
        best: best,
        notes: notes,
        tries: attempt,
        passed: true,
        bestAttempt: attempt,
      );
    }
    notes.add(
      WorldLoopNote(
        stage: stage,
        attempt: attempt,
        verdict: 'FAIL',
        note: verdict.problems.join('; '),
      ),
    );
    previous = output;
    feedback = verdict.problems;
  }
  for (final n in notes) {
    debugPrint('[World] $n');
  }
  return WorldLoopResult(
    best: best,
    notes: notes,
    tries: rounds,
    passed: false,
    bestAttempt: bestAttempt,
  );
}
