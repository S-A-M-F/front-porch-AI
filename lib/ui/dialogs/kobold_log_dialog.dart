// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/pseudo_remote_service.dart';

/// Dialog that displays live KoboldCPP process logs in real-time.
/// Matches the visual style of [ContextViewerDialog].
class KoboldLogDialog extends StatefulWidget {
  const KoboldLogDialog({super.key});

  @override
  State<KoboldLogDialog> createState() => _KoboldLogDialogState();
}

class _KoboldLogDialogState extends State<KoboldLogDialog>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late final AnimationController _blinkController;
  late final Animation<double> _blinkAnimation;
  bool _autoScroll = true;
  int _lastLogCount = 0;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _blinkAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _blinkController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _blinkController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Scroll to the very bottom of the log list.
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  bool _isProgressLine(String line) =>
      line.startsWith('Generating (') ||
      RegExp(r'^Processing Prompt', caseSensitive: false).hasMatch(line);

  Color _lineColor(String line) {
    if (line.toLowerCase().contains('error') ||
        line.toLowerCase().contains('fail') ||
        line.toLowerCase().contains('fatal')) {
      return const Color(0xFFFF6B6B);
    } else if (line.toLowerCase().contains('warn')) {
      return const Color(0xFFFFD93D);
    } else if (line.toLowerCase().contains('ready') ||
        line.toLowerCase().contains('server listen') ||
        line.toLowerCase().contains('please connect')) {
      return Colors.greenAccent;
    } else if (line.toLowerCase().contains('loading') ||
        line.toLowerCase().contains('starting')) {
      return const Color(0xFF93C5FD);
    }
    return const Color(0xFF86EFAC);
  }

  void _updateBlinking(List<String> logs) {
    if (logs.isNotEmpty && _isProgressLine(logs.last)) {
      if (!_blinkController.isAnimating) {
        _blinkController.repeat(reverse: true);
      }
    } else {
      _blinkController.stop();
      _blinkController.value = 1.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<LLMProvider, KoboldService>(
      builder: (context, llmProvider, kobold, _) {
        final pseudoRemote = Provider.of<PseudoRemoteService>(context, listen: false);
        final isPseudo = llmProvider.activeBackend == BackendType.pseudoRemote;
        final logs = isPseudo ? pseudoRemote.logs : kobold.logs;
        final isRunning = isPseudo ? pseudoRemote.isRunning : kobold.isRunning;
        final isReady = isPseudo ? pseudoRemote.isReady : kobold.isReady;

        // Auto-scroll whenever new lines arrive, but only if the user hasn't
        // manually scrolled up.
        if (_autoScroll && logs.length != _lastLogCount) {
          _lastLogCount = logs.length;
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        }

        final statusColor = isRunning ? Colors.greenAccent : Colors.white38;
        final statusLabel = isRunning
            ? (isReady ? 'Ready' : 'Starting…')
            : 'Stopped';

        return Dialog(
          backgroundColor: const Color(0xFF0f172a),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 720,
              maxHeight: 620,
              minWidth: 480,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Header ───────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.white12)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.terminal,
                        color: Colors.greenAccent,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        isPseudo ? 'Pseudo-Remote Log' : 'KoboldCpp Log',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Live status pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: statusColor.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              statusLabel,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Copy all button
                      Tooltip(
                        message: 'Copy all logs',
                        child: IconButton(
                          icon: const Icon(
                            Icons.copy_all,
                            color: Colors.white38,
                            size: 18,
                          ),
                          onPressed: logs.isEmpty
                              ? null
                              : () {
                                  Clipboard.setData(
                                    ClipboardData(text: logs.join('\n')),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Logs copied to clipboard'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                },
                        ),
                      ),
                      // Auto-scroll toggle
                      Tooltip(
                        message: _autoScroll
                            ? 'Auto-scroll: ON'
                            : 'Auto-scroll: OFF (click to re-enable)',
                        child: IconButton(
                          icon: Icon(
                            Icons.vertical_align_bottom,
                            color: _autoScroll
                                ? Colors.greenAccent
                                : Colors.white24,
                            size: 18,
                          ),
                          onPressed: () {
                            setState(() {
                              _autoScroll = !_autoScroll;
                            });
                            if (_autoScroll) _scrollToBottom();
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white54,
                          size: 20,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),

                // ── Log count + hint ─────────────────────────────────────
                if (logs.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Text(
                          '${logs.length} line${logs.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                            color: Colors.white24,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          '· Text is selectable and copyable',
                          style: TextStyle(
                            color: Colors.white12,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),

                // ── Log body ──────────────────────────────────────────────
                Flexible(
                  child: logs.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.terminal,
                                color: Colors.white12,
                                size: 36,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'No log output yet.',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isPseudo
                                    ? 'Start the Pseudo-Remote backend from Settings → Backend.'
                                    : 'Start the backend from Settings → Backend, or from the Model Settings dialog.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white24,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        )
                      : NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (notification is UserScrollNotification) {
                              final atBottom =
                                  _scrollController.hasClients &&
                                  _scrollController.position.pixels >=
                                      _scrollController.position.maxScrollExtent - 32;
                              if (_autoScroll != atBottom) {
                                setState(() => _autoScroll = atBottom);
                              }
                            }
                            return false;
                          },
                          child: Container(
                            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF020617),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Scrollbar(
                              controller: _scrollController,
                              thumbVisibility: true,
                              child: SingleChildScrollView(
                                controller: _scrollController,
                                padding: const EdgeInsets.all(12),
                                child: AnimatedBuilder(
                                  animation: _blinkAnimation,
                                  builder: (context, _) {
                                    _updateBlinking(logs);

                                    final spans = <TextSpan>[];
                                    for (int i = 0; i < logs.length; i++) {
                                      final line = logs[i];
                                      Color color = _lineColor(line);

                                      if (i == logs.length - 1 && _isProgressLine(line)) {
                                        color = color.withValues(alpha: _blinkAnimation.value);
                                      }

                                      spans.add(TextSpan(
                                        text: i < logs.length - 1 ? '$line\n' : line,
                                        style: TextStyle(color: color, height: 1.45),
                                      ));
                                    }

                                    return SelectableText.rich(
                                      TextSpan(children: spans),
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
