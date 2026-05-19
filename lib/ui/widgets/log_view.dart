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

class LogView extends StatefulWidget {
  final List<String> logs;

  const LogView({super.key, required this.logs});

  @override
  State<LogView> createState() => _LogViewState();
}

class _LogViewState extends State<LogView> with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late final AnimationController _blinkController;
  late final Animation<double> _blinkAnimation;
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
    _updateState();
  }

  @override
  void didUpdateWidget(LogView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateState();
  }

  void _updateState() {
    if (!mounted) return;
    final logs = widget.logs;

    if (logs.length != _lastLogCount) {
      _lastLogCount = logs.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }

    if (logs.isNotEmpty && _isProgressLine(logs.last)) {
      if (!_blinkController.isAnimating) {
        _blinkController.repeat(reverse: true);
      }
    } else {
      _blinkController.stop();
      _blinkController.value = 1.0;
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

  @override
  void dispose() {
    _blinkController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Scrollbar(
        controller: _scrollController,
        child: SingleChildScrollView(
          controller: _scrollController,
          child: AnimatedBuilder(
            animation: _blinkAnimation,
            builder: (context, _) {
              final spans = <TextSpan>[];
              final logs = widget.logs;
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
    );
  }
}
