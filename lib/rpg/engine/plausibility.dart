// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Plausibility Engine — Context-aware skill check evaluation.
//
// Uses a SEPARATE AI call to evaluate player actions before narration.
// Flow:
//   1. Player types action → PlausibilityEngine.evaluate() makes a lightweight
//      AI call asking "what check is needed given the FULL situation?"
//   2. AI considers: combat state, environment, HP, equipment, darkness, etc.
//   3. Engine rolls dice based on AI's evaluation
//   4. Roll result is injected into the narration prompt (separate call)
//
// This mirrors the reference repo's two-phase approach where plausibility
// is evaluated separately from narration.

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/rpg/engine/dice.dart';
import 'package:front_porch_ai/rpg/engine/game_engine.dart';
import 'package:front_porch_ai/rpg/models/character_sheet.dart';
import 'package:front_porch_ai/services/llm_service.dart';

/// The outcome of a plausibility check.
enum PlausibilityOutcome {
  success,
  failure,
  criticalSuccess,
  criticalFailure,
  noCheckNeeded,
}

/// Result of a pre-roll plausibility check.
class PlausibilityResult {
  final PlausibilityOutcome outcome;
  final Ability? ability;
  final int? roll;
  final int? modifier;
  final int? total;
  final int? dc;
  final String? actionDescription;
  final String? situationalReasoning;

  PlausibilityResult({
    required this.outcome,
    this.ability,
    this.roll,
    this.modifier,
    this.total,
    this.dc,
    this.actionDescription,
    this.situationalReasoning,
  });

  bool get isSuccess =>
      outcome == PlausibilityOutcome.success ||
      outcome == PlausibilityOutcome.criticalSuccess;

  bool get needsCheck => outcome != PlausibilityOutcome.noCheckNeeded;

  /// Build a context string to inject into the narration prompt.
  String toPromptContext() {
    if (!needsCheck) return '';

    final abilityName = ability?.name.toUpperCase() ?? '???';
    final outcomeStr = switch (outcome) {
      PlausibilityOutcome.criticalSuccess =>
        'CRITICAL SUCCESS (NAT 20)! Narrate a spectacular, extraordinary success.',
      PlausibilityOutcome.criticalFailure =>
        'CRITICAL FAILURE (NAT 1)! Narrate a catastrophic, embarrassing, or dangerous failure with consequences.',
      PlausibilityOutcome.success =>
        'SUCCESS. Narrate the player succeeding at this action.',
      PlausibilityOutcome.failure =>
        'FAILURE. Narrate the player failing at this action. Describe what goes wrong.',
      PlausibilityOutcome.noCheckNeeded => '',
    };

    final reasoning = situationalReasoning != null
        ? 'Situational context: $situationalReasoning\n'
        : '';

    return '[SKILL CHECK RESULT]\n'
        'Action: ${actionDescription ?? "unknown"}\n'
        '$reasoning'
        'Check: $abilityName check — rolled $roll + $modifier mod = $total vs DC $dc\n'
        'Outcome: $outcomeStr\n'
        'IMPORTANT: You MUST narrate this outcome. Do NOT contradict the roll result. '
        'If the check failed, the action MUST fail in your narration. '
        'If it succeeded, narrate success. The player can see the dice roll.\n'
        'Do NOT emit a <skill_check> event — it has already been resolved.\n';
  }

  /// Short display string for the chat UI.
  String toDisplayString() {
    if (!needsCheck) return '';
    final abilityName = ability?.name.toUpperCase() ?? '???';
    final emoji = switch (outcome) {
      PlausibilityOutcome.criticalSuccess => '🎯',
      PlausibilityOutcome.criticalFailure => '💥',
      PlausibilityOutcome.success => '✓',
      PlausibilityOutcome.failure => '✗',
      PlausibilityOutcome.noCheckNeeded => '',
    };
    final dc_ = dc ?? 0;
    return '🎲 $abilityName check: $roll + $modifier = $total vs DC $dc_ $emoji';
  }
}

/// The plausibility engine that evaluates player actions using a separate AI call.
class PlausibilityEngine {

  /// Build situational context from the full game state.
  static String _buildSituationalContext(GameState state) {
    final buf = StringBuffer();

    // Combat state
    if (state.combat != null) {
      buf.writeln('⚔️ CURRENTLY IN COMBAT with ${state.combat!.enemies.length} enemies.');
      buf.writeln('   Actions taken under pressure are HARDER (DC +3 to +5).');
    }

    // HP status
    if (state.player != null) {
      final hpPct = state.player!.currentHp / state.player!.maxHp;
      if (hpPct < 0.25) {
        buf.writeln('🩸 Player is CRITICALLY WOUNDED (${state.player!.currentHp}/${state.player!.maxHp} HP). Actions requiring physical exertion are harder.');
      } else if (hpPct < 0.5) {
        buf.writeln('🩸 Player is INJURED (${state.player!.currentHp}/${state.player!.maxHp} HP).');
      }
    }

    // Status effects
    if (state.playerEffects.isNotEmpty) {
      final effects = state.playerEffects.map((e) => e.displayName).join(', ');
      buf.writeln('Status effects: $effects');
    }

    // Location
    buf.writeln('Location: ${state.location}');

    // Equipment/inventory
    final weapons = state.inventory.where((i) => i.type == 'weapon').toList();
    final tools = state.inventory.where((i) => i.type == 'tool' || i.type == 'key').toList();
    if (weapons.isNotEmpty) buf.writeln('Equipped weapons: ${weapons.map((w) => w.name).join(', ')}');
    if (tools.isNotEmpty) buf.writeln('Available tools: ${tools.map((t) => t.name).join(', ')}');

    // Party
    if (state.party.isNotEmpty) {
      buf.writeln('Party: ${state.party.map((p) => '${p.name} (${p.role})').join(', ')}');
      buf.writeln('   Having allies can provide assistance (advantage or DC reduction).');
    }

    return buf.toString();
  }

  /// Make a separate AI call to evaluate the player's action in context.
  /// Returns a PlausibilityResult with the pre-rolled outcome.
  static Future<PlausibilityResult> evaluate({
    required String playerAction,
    required GameState state,
    required LLMService llmService,
  }) async {
    if (state.player == null) {
      return PlausibilityResult(outcome: PlausibilityOutcome.noCheckNeeded);
    }

    // Skip very short inputs, pure dialogue, or simple commands
    final lower = playerAction.toLowerCase().trim();
    if (lower.length < 5 || lower.startsWith('"') || lower.startsWith("'")) {
      return PlausibilityResult(outcome: PlausibilityOutcome.noCheckNeeded);
    }

    final situationalContext = _buildSituationalContext(state);
    final player = state.player!;

    // Build the evaluation prompt for the AI
    final evalPrompt = _buildEvaluationPrompt(
      playerAction: playerAction,
      playerName: player.name,
      playerClass: player.config.name,
      playerLevel: player.level,
      playerStats: 'STR ${player.abilities[Ability.str]} (${_modStr(player.strMod)}), '
          'DEX ${player.abilities[Ability.dex]} (${_modStr(player.dexMod)}), '
          'CON ${player.abilities[Ability.con]} (${_modStr(player.conMod)}), '
          'INT ${player.abilities[Ability.int_]} (${_modStr(player.intMod)}), '
          'WIS ${player.abilities[Ability.wis]} (${_modStr(player.wisMod)}), '
          'CHA ${player.abilities[Ability.cha]} (${_modStr(player.chaMod)})',
      proficiencyBonus: player.proficiencyBonus,
      situationalContext: situationalContext,
    );

    try {
      // Make a lightweight, short-response AI call
      final response = await _makeLightweightCall(llmService, evalPrompt);
      return _parseEvaluationResponse(response, player);
    } catch (e) {
      debugPrint('[Plausibility] AI eval failed, falling back to keyword check: $e');
      // Fallback to simple keyword-based detection
      return _keywordFallback(lower, player, state);
    }
  }

  /// Build the evaluation prompt sent to the AI.
  static String _buildEvaluationPrompt({
    required String playerAction,
    required String playerName,
    required String playerClass,
    required int playerLevel,
    required String playerStats,
    required int proficiencyBonus,
    required String situationalContext,
  }) {
    return 'You are a D&D rules engine. Evaluate this player action and determine if it requires a skill check.\n\n'
        'PLAYER: $playerName, Level $playerLevel $playerClass\n'
        'STATS: $playerStats (Proficiency: +$proficiencyBonus)\n\n'
        'CURRENT SITUATION:\n$situationalContext\n'
        'PLAYER ACTION: "$playerAction"\n\n'
        'RULES:\n'
        '- Simple actions (walking, talking, looking) do NOT need checks.\n'
        '- Actions with uncertain outcomes need ability checks.\n'
        '- CONSIDER THE FULL SITUATION when setting DC:\n'
        '  • In combat? Actions requiring focus are HARDER (+3 to +5 DC)\n'
        '  • Wounded? Physical actions are harder\n'
        '  • Has relevant tools/items? DC is lower (-2 to -5)\n'
        '  • Ally can help? DC is lower\n'
        '  • Dark/dangerous environment? Perception/stealth affected\n'
        '- DC scale: 5=trivial, 10=easy, 13=moderate, 15=hard, 18=very hard, 20=nearly impossible, 25=legendary\n\n'
        'Respond with EXACTLY one line in this format:\n'
        'CHECK: [ability] [dc] [reason]\n'
        'Or if no check is needed:\n'
        'NONE: [reason]\n\n'
        'Examples:\n'
        'CHECK: dex 15 Picking a lock while enemies patrol nearby\n'
        'CHECK: str 18 Breaking down a reinforced door during combat\n'
        'CHECK: cha 12 Persuading a friendly merchant for a discount\n'
        'NONE: Simply walking to the tavern\n'
        'NONE: Greeting the innkeeper';
  }

  /// Make a lightweight AI call with short max_tokens.
  static Future<String> _makeLightweightCall(LLMService llmService, String prompt) async {
    final params = GenerationParams(
      prompt: prompt,
      maxLength: 50,  // Very short — we only need one line
      temperature: 0.3,  // Low temp for consistency
      repeatPenalty: 1.0,
      minP: 0.1,
      topP: 0.9,
    );

    final buffer = StringBuffer();
    await for (final token in llmService.generateStream(params)) {
      buffer.write(token);
      // Stop early if we got a complete line
      if (buffer.toString().contains('\n') && buffer.length > 10) break;
    }

    final result = buffer.toString().trim();
    debugPrint('[Plausibility] AI evaluation: $result');
    return result;
  }

  /// Parse the AI's evaluation response into a PlausibilityResult.
  static PlausibilityResult _parseEvaluationResponse(String response, PlayerSheet player) {
    // Clean up response - take first meaningful line
    final lines = response
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      return PlausibilityResult(outcome: PlausibilityOutcome.noCheckNeeded);
    }

    final line = lines.first.toUpperCase();

    // Parse NONE response
    if (line.startsWith('NONE')) {
      return PlausibilityResult(outcome: PlausibilityOutcome.noCheckNeeded);
    }

    // Parse CHECK response: CHECK: [ability] [dc] [reason]
    if (line.startsWith('CHECK')) {
      final parts = lines.first.substring(lines.first.indexOf(':') + 1).trim().split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        final abilityStr = parts[0].toLowerCase();
        final dc = int.tryParse(parts[1]) ?? 13;
        final reason = parts.length > 2 ? parts.sublist(2).join(' ') : null;
        final ability = _parseAbility(abilityStr);

        return _rollCheck(
          player: player,
          ability: ability,
          dc: dc.clamp(5, 30),  // Sanity clamp
          actionDescription: reason ?? lines.first,
          situationalReasoning: reason,
        );
      }
    }

    // Fallback: no check
    return PlausibilityResult(outcome: PlausibilityOutcome.noCheckNeeded);
  }

  /// Roll the actual check.
  static PlausibilityResult _rollCheck({
    required PlayerSheet player,
    required Ability ability,
    required int dc,
    required String actionDescription,
    String? situationalReasoning,
  }) {
    final modifier = player.getModifier(ability) + player.proficiencyBonus;
    final diceResult = DiceRoller.d20();
    final roll = diceResult.individualRolls.first;
    final total = roll + modifier;

    PlausibilityOutcome outcome;
    if (roll == 20) {
      outcome = PlausibilityOutcome.criticalSuccess;
    } else if (roll == 1) {
      outcome = PlausibilityOutcome.criticalFailure;
    } else if (total >= dc) {
      outcome = PlausibilityOutcome.success;
    } else {
      outcome = PlausibilityOutcome.failure;
    }

    return PlausibilityResult(
      outcome: outcome,
      ability: ability,
      roll: roll,
      modifier: modifier,
      total: total,
      dc: dc,
      actionDescription: actionDescription,
      situationalReasoning: situationalReasoning,
    );
  }

  /// Keyword-based fallback when AI evaluation is unavailable.
  static PlausibilityResult _keywordFallback(String lower, PlayerSheet player, GameState state) {
    final inCombat = state.combat != null;
    final combatPenalty = inCombat ? 4 : 0;

    // HP-based penalty
    final hpPenalty = state.player != null
        ? (state.player!.currentHp / state.player!.maxHp < 0.25 ? 2 : 0)
        : 0;

    for (final pattern in _fallbackPatterns) {
      for (final keyword in pattern.keywords) {
        if (lower.contains(keyword)) {
          final adjustedDc = (pattern.baseDc + combatPenalty + hpPenalty).clamp(5, 30);
          return _rollCheck(
            player: player,
            ability: pattern.ability,
            dc: adjustedDc,
            actionDescription: lower,
            situationalReasoning: inCombat ? 'Under combat pressure (+$combatPenalty DC)' : null,
          );
        }
      }
    }

    // Check for "try to" / "attempt to" phrasing
    if (lower.contains('try to') || lower.contains('attempt to') ||
        lower.contains('i try') || lower.contains('i attempt')) {
      final ability = _guessAbilityFromContext(lower);
      final adjustedDc = (13 + combatPenalty + hpPenalty).clamp(5, 30);
      return _rollCheck(
        player: player,
        ability: ability,
        dc: adjustedDc,
        actionDescription: lower,
        situationalReasoning: inCombat ? 'Under combat pressure (+$combatPenalty DC)' : null,
      );
    }

    return PlausibilityResult(outcome: PlausibilityOutcome.noCheckNeeded);
  }

  /// Parse ability string to enum.
  static Ability _parseAbility(String str) {
    switch (str.toLowerCase()) {
      case 'str': case 'strength': return Ability.str;
      case 'dex': case 'dexterity': return Ability.dex;
      case 'con': case 'constitution': return Ability.con;
      case 'int': case 'intelligence': case 'int_': return Ability.int_;
      case 'wis': case 'wisdom': return Ability.wis;
      case 'cha': case 'charisma': return Ability.cha;
      default: return Ability.dex;
    }
  }

  /// Guess ability from context words.
  static Ability _guessAbilityFromContext(String text) {
    if (text.contains('jump') || text.contains('run') || text.contains('catch') ||
        text.contains('grab') || text.contains('swing') || text.contains('dodge')) return Ability.dex;
    if (text.contains('convince') || text.contains('talk') || text.contains('persuade') ||
        text.contains('lie') || text.contains('bluff')) return Ability.cha;
    if (text.contains('think') || text.contains('figure') || text.contains('know') ||
        text.contains('recall') || text.contains('study')) return Ability.int_;
    if (text.contains('find') || text.contains('notice') || text.contains('hear') ||
        text.contains('search') || text.contains('sense')) return Ability.wis;
    if (text.contains('lift') || text.contains('carry') || text.contains('push') ||
        text.contains('break') || text.contains('force')) return Ability.str;
    return Ability.dex;
  }

  static String _modStr(int mod) => mod >= 0 ? '+$mod' : '$mod';
}

/// Fallback keyword patterns when AI call fails.
class _FallbackPattern {
  final List<String> keywords;
  final Ability ability;
  final int baseDc;
  const _FallbackPattern(this.keywords, this.ability, this.baseDc);
}

const _fallbackPatterns = <_FallbackPattern>[
  _FallbackPattern(['break', 'smash', 'force', 'push', 'pull', 'lift', 'bend', 'pry',
      'bash', 'shove', 'throw', 'wrestle', 'grapple'], Ability.str, 14),
  _FallbackPattern(['pick the lock', 'lockpick', 'pick lock', 'unlock', 'disarm trap',
      'sneak', 'stealth', 'hide', 'dodge', 'climb', 'scale', 'pickpocket',
      'steal', 'sleight of hand'], Ability.dex, 13),
  _FallbackPattern(['endure', 'resist', 'hold breath', 'withstand',
      'power through', 'stay conscious'], Ability.con, 12),
  _FallbackPattern(['investigate', 'study', 'recall', 'decipher', 'decode',
      'analyze', 'examine', 'identify', 'solve', 'translate'], Ability.int_, 12),
  _FallbackPattern(['perceive', 'notice', 'spot', 'listen', 'sense', 'track',
      'forage', 'navigate', 'insight', 'detect', 'search',
      'check for traps', 'medicine'], Ability.wis, 12),
  _FallbackPattern(['persuade', 'convince', 'charm', 'intimidate', 'threaten',
      'deceive', 'lie', 'bluff', 'negotiate', 'haggle', 'barter',
      'flatter', 'inspire', 'perform'], Ability.cha, 13),
];
