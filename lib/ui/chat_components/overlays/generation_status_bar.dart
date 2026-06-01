// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// ... full standard header ...
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Rich, phase-aware generation status bar. (extracted)
class GenerationStatusBar extends StatefulWidget {
  final ChatService chatService;
  const GenerationStatusBar({required this.chatService});

  @override
  State<GenerationStatusBar> createState() => _GenerationStatusBarState();
}

class _GenerationStatusBarState extends State<GenerationStatusBar> {
  Timer? _elapsedTimer;

  @override
  void initState() {
    super.initState();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.chatService;
    final phase = cs.generationPhase;

    final (
      String label,
      Color accentColor,
      IconData icon,
      bool showMetrics,
    ) = switch (phase) {
      GenerationPhase.preparing => (
        'Assembling prompt...',
        AppColors.resolve(
          context,
          const Color(0xFFF59E0B),
          const Color(0xFFB45309),
        ),
        Icons.build_rounded,
        false,
      ),
      GenerationPhase.prefilling => _prefillLabel(cs),
      GenerationPhase.thinking => _thinkingLabel(cs),
      GenerationPhase.buffering => (
        'Buffering tokens...',
        AppColors.resolve(
          context,
          const Color(0xFF3B82F6),
          const Color(0xFF1D4ED8),
        ),
        Icons.hourglass_top_rounded,
        true,
      ),
      GenerationPhase.generating => (
        'Generating response...',
        AppColors.resolve(
          context,
          const Color(0xFF10B981),
          const Color(0xFF059669),
        ),
        Icons.bolt_rounded,
        true,
      ),
      GenerationPhase.idle => (
        'Idle',
        AppColors.textTertiary(context),
        Icons.check_rounded,
        false,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        border: Border(
          top: BorderSide(
            color: AppColors.borderOf(context).withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child:
                    phase == GenerationPhase.prefilling ||
                        phase == GenerationPhase.preparing
                    ? PulsingIcon(icon: icon, color: accentColor)
                    : Icon(icon, size: 16, color: accentColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: accentColor.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (showMetrics) ...[
                Text(
                  '${cs.tokensPerSecond.toStringAsFixed(1)} t/s',
                  style: TextStyle(
                    color: AppColors.resolve(
                      context,
                      Colors.amberAccent,
                      const Color(0xFFB45309),
                    ),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${cs.tokensGenerated} / ${cs.maxTokens}',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${(cs.generationProgress * 100).toInt()}%',
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: _buildProgressBar(cs, phase, accentColor),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(
    ChatService cs,
    GenerationPhase phase,
    Color accentColor,
  ) {
    if (phase == GenerationPhase.generating ||
        phase == GenerationPhase.buffering) {
      return LinearProgressIndicator(
        value: cs.generationProgress,
        minHeight: 4,
        backgroundColor: AppColors.borderOf(context).withValues(alpha: 0.08),
        valueColor: AlwaysStoppedAnimation<Color>(
          Color.lerp(
            accentColor,
            AppColors.resolve(
              context,
              AppColors.resolve(
                context,
                const Color(0xFF10B981),
                const Color(0xFF059669),
              ),
              const Color(0xFF059669),
            ),
            cs.generationProgress,
          )!,
        ),
      );
    }
    return LinearProgressIndicator(
      minHeight: 4,
      backgroundColor: Colors.white.withValues(alpha: 0.08),
      valueColor: AlwaysStoppedAnimation<Color>(
        accentColor.withValues(alpha: 0.7),
      ),
    );
  }

  (String, Color, IconData, bool) _prefillLabel(ChatService cs) {
    final elapsed = cs.prefillElapsedSeconds;
    final elapsedStr = elapsed >= 1 ? ' (${elapsed.toInt()}s)' : '';
    final promptTokens = cs.prefillPromptTokens;
    String tokenStr = '';
    if (promptTokens > 0) {
      if (promptTokens >= 1000) {
        tokenStr =
            '~${(promptTokens / 1000).toStringAsFixed(promptTokens >= 10000 ? 0 : 1)}K tokens';
      } else {
        tokenStr = '~$promptTokens tokens';
      }
    }
    final perf = cs.lastPerfData;
    String speedStr = '';
    if (perf != null) {
      final idle = perf['idle'];
      if (idle == 0) {
        final speed = perf['last_process_speed'];
        if (speed != null && speed is num && speed > 0) {
          speedStr = '~${speed.toStringAsFixed(0)} t/s';
        }
      }
    }
    final parts = <String>[
      if (tokenStr.isNotEmpty) tokenStr,
      if (speedStr.isNotEmpty) speedStr,
    ];
    final detail = parts.isNotEmpty ? ' — ${parts.join(', ')}' : '';
    return (
      'Processing prompt$elapsedStr$detail',
      const Color(0xFFF97316),
      Icons.memory_rounded,
      false,
    );
  }

  (String, Color, IconData, bool) _thinkingLabel(ChatService cs) {
    final tokens = cs.tokensGenerated;
    final tps = cs.tokensPerSecond;
    String detail = '';
    if (tokens > 0 && tps > 0) {
      detail = ' — ${tps.toStringAsFixed(1)} t/s, $tokens tokens';
    } else if (tokens > 0) {
      detail = ' — $tokens tokens';
    }
    return (
      'Model is thinking...$detail',
      const Color(0xFFA855F7),
      Icons.psychology_rounded,
      false,
    );
  }
}

/// Pulsing icon (extracted).
class PulsingIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  const PulsingIcon({required this.icon, required this.color});

  @override
  State<PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<PulsingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: 0.4 + (_controller.value * 0.6),
          child: Icon(widget.icon, size: 16, color: widget.color),
        );
      },
    );
  }
}
