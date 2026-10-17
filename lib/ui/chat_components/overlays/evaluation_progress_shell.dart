// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

class EvaluationProgressShell extends StatefulWidget {
  const EvaluationProgressShell({
    super.key,
    required this.title,
    required this.minimized,
    required this.onExpand,
    this.onStop,
    this.stopLabel = 'Stop this reply',
  });

  final String title;
  final bool minimized;
  final VoidCallback onExpand;
  final VoidCallback? onStop;
  final String stopLabel;

  @override
  State<EvaluationProgressShell> createState() =>
      _EvaluationProgressShellState();
}

class _EvaluationProgressShellState extends State<EvaluationProgressShell> {
  int _seconds = 0;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _seconds = timer.tick;
      if (_seconds >= 30) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.minimized) return const SizedBox.shrink();
    return Material(
      color: AppColors.surfaceOf(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.porchAmberOf(context),
              ),
            ),
            Text(
              widget.title,
              style: TextStyle(color: AppColors.textPrimary(context)),
            ),
            if (_seconds >= 30)
              ExcludeSemantics(child: Text('${_seconds}s elapsed')),
            TextButton.icon(
              onPressed: widget.onExpand,
              icon: const Icon(Icons.open_in_full),
              label: const Text('Show evaluation details'),
            ),
            if (widget.onStop != null)
              TextButton(
                onPressed: widget.onStop,
                child: Text(widget.stopLabel),
              ),
          ],
        ),
      ),
    );
  }
}
