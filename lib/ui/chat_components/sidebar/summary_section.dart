// standard
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Chat Summary sidebar section — shows enable toggle, config,
/// current summary, and allows editing/pause/regeneration.
class SummarySection extends StatefulWidget {
  final ChatService chatService;
  const SummarySection({super.key, required this.chatService});

  @override
  State<SummarySection> createState() => SummarySectionState();
}

class SummarySectionState extends State<SummarySection> {
  late TextEditingController _controller;
  bool _showSettings = false;
  bool _expanded = false;
  double? _dragSummaryInterval;
  double? _dragSummaryMaxWords;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.chatService.summary);
    widget.chatService.addListener(_onChatChanged);
  }

  void _onChatChanged() {
    if (_controller.text != widget.chatService.summary) {
      _controller.text = widget.chatService.summary;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.chatService.removeListener(_onChatChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final storage = Provider.of<StorageService>(context);
    final enabled = storage.summaryEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with enable toggle
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              children: [
                Icon(
                  _expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 16,
                  color: AppColors.iconSecondary(context),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.auto_stories,
                  size: 14,
                  color: AppColors.resolve(
                    context,
                    Colors.tealAccent,
                    Colors.teal.shade700,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Chat Summary',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary(context),
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                if (enabled && widget.chatService.isSummaryGenerating)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.resolve(
                          context,
                          Colors.tealAccent,
                          Colors.teal.shade700,
                        ),
                      ),
                    ),
                  ),
                SizedBox(
                  height: 28,
                  child: FittedBox(
                    child: Switch(
                      value: enabled,
                      onChanged: (val) {
                        storage.setSummaryEnabled(val);
                        if (val) setState(() => _expanded = true);
                      },
                      activeTrackColor: AppColors.resolve(
                        context,
                        Colors.tealAccent,
                        Colors.teal.shade700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        if (_expanded) ...[
          if (!enabled)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 20),
              child: Text(
                'Auto-summarize conversations so the AI remembers earlier events even after they leave the context window.',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary(context),
                ),
              ),
            ),

          if (enabled) ...[
            const SizedBox(height: 8),
            // Summary text field
            Padding(
              padding: const EdgeInsets.only(left: 20.0),
              child: AppTextField(
                controller: _controller,
                maxLines: 6,
                minLines: 2,
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 12,
                ),
                decoration: InputDecoration(
                  hintText:
                      'No summary yet. It will generate after enough messages...',
                  hintStyle: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 12,
                  ),
                  filled: true,
                  fillColor: AppColors.surfaceContainerOf(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppColors.borderOf(context)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppColors.borderOf(context)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: AppColors.resolve(
                        context,
                        Colors.tealAccent,
                        Colors.teal.shade700,
                      ),
                    ),
                  ),
                  contentPadding: const EdgeInsets.all(10),
                ),
                onChanged: (val) {
                  widget.chatService.setSummary(val);
                },
              ),
            ),
            const SizedBox(height: 6),
            // Controls row
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Row(
                children: [
                  // Pause/Resume toggle
                  InkWell(
                    onTap: () => widget.chatService.setSummaryPaused(
                      !widget.chatService.summaryPaused,
                    ),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.chatService.summaryPaused
                                ? Icons.play_arrow
                                : Icons.pause,
                            size: 14,
                            color: widget.chatService.summaryPaused
                                ? AppColors.resolve(
                                    context,
                                    Colors.orangeAccent,
                                    Colors.orange.shade700,
                                  )
                                : AppColors.iconSecondary(context),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            widget.chatService.summaryPaused
                                ? 'Paused'
                                : 'Auto',
                            style: TextStyle(
                              fontSize: 10,
                              color: widget.chatService.summaryPaused
                                  ? AppColors.resolve(
                                      context,
                                      Colors.orangeAccent,
                                      Colors.orange.shade700,
                                    )
                                  : AppColors.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Settings gear toggle
                  InkWell(
                    onTap: () => setState(() => _showSettings = !_showSettings),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Icon(
                        Icons.tune,
                        size: 14,
                        color: _showSettings
                            ? Colors.tealAccent
                            : Colors.white38,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Regenerate button
                  InkWell(
                    onTap: widget.chatService.isSummaryGenerating
                        ? null
                        : () => widget.chatService.forceSummaryUpdate(),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.refresh,
                            size: 14,
                            color: widget.chatService.isSummaryGenerating
                                ? Colors.white12
                                : Colors.tealAccent,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Regen',
                            style: TextStyle(
                              fontSize: 10,
                              color: widget.chatService.isSummaryGenerating
                                  ? Colors.white12
                                  : Colors.tealAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.chatService.summaryLastIndex > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 24),
                child: Text(
                  'Last updated at message #${widget.chatService.summaryLastIndex}',
                  style: const TextStyle(fontSize: 10, color: Colors.white24),
                ),
              ),

            // Expandable settings panel
            if (_showSettings) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 20),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Update Interval
                      Row(
                        children: [
                          const Text(
                            'Update every',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white54,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${(_dragSummaryInterval ?? storage.summaryInterval.toDouble()).round()} messages',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.tealAccent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                        ),
                        child: Slider(
                          value:
                              _dragSummaryInterval ??
                              storage.summaryInterval.toDouble(),
                          min: 3,
                          max: 50,
                          divisions: 47,
                          activeColor: Colors.tealAccent,
                          inactiveColor: Colors.white12,
                          onChanged: (val) =>
                              setState(() => _dragSummaryInterval = val),
                          onChangeEnd: (val) {
                            _dragSummaryInterval = null;
                            storage.setSummaryInterval(val.toInt());
                          },
                        ),
                      ),
                      // Max Words
                      Row(
                        children: [
                          const Text(
                            'Max words',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white54,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${(_dragSummaryMaxWords ?? storage.summaryMaxWords.toDouble()).round()}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.tealAccent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                        ),
                        child: Slider(
                          value:
                              _dragSummaryMaxWords ??
                              storage.summaryMaxWords.toDouble(),
                          min: 50,
                          max: 1000,
                          divisions: 19,
                          activeColor: Colors.tealAccent,
                          inactiveColor: Colors.white12,
                          onChanged: (val) =>
                              setState(() => _dragSummaryMaxWords = val),
                          onChangeEnd: (val) {
                            _dragSummaryMaxWords = null;
                            storage.setSummaryMaxWords(val.toInt());
                          },
                        ),
                      ),
                      // Summary Prompt
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Text(
                            'Summary Prompt',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white54,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () {
                              storage.setSummaryPrompt(
                                StorageService.defaultSummaryPrompt,
                              );
                              setState(() {});
                            },
                            child: const Text(
                              'Reset',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.tealAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      AppTextField(
                        controller: TextEditingController(
                          text: storage.summaryPrompt,
                        ),
                        maxLines: 3,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Instructions for summarizing...',
                          hintStyle: const TextStyle(
                            color: Colors.white24,
                            fontSize: 11,
                          ),
                          filled: true,
                          fillColor: const Color(0xFF0D1117),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(color: Colors.white12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(color: Colors.white12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(
                              color: Colors.tealAccent,
                            ),
                          ),
                          contentPadding: const EdgeInsets.all(8),
                        ),
                        onChanged: (val) => storage.setSummaryPrompt(val),
                      ),
                      const SizedBox(height: 6),
                      const Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 12,
                            color: Colors.amber,
                          ),
                          SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Uses your active LLM — consumes tokens on paid APIs.',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.amber,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ],
      ],
    );
  }
}
