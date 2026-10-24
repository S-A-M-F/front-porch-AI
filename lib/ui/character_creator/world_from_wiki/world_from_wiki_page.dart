// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/widgets.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/steps/steps.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_review_actions.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_state.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';
import 'package:front_porch_ai/services/storage/settings/web_search_settings.dart';

/// Studio wizard: wiki → lorebook cards → a real World in the library.
class WorldFromWikiPage extends StatefulWidget {
  const WorldFromWikiPage({super.key});

  @override
  State<WorldFromWikiPage> createState() => _WorldFromWikiPageState();
}

class _WorldFromWikiPageState extends State<WorldFromWikiPage> {
  late final CreatorState creatorState = CreatorState();
  late final WorldFromWikiState worldState = WorldFromWikiState();
  late final ChatService _chat;
  late final LLMProvider _llm;

  void _tick() {
    if (mounted) setState(() {});
  }

  /// Chat's tool check moved (started, answered) or the backend changed.
  void _readToolsGate() {
    if (!mounted || worldState.currentStep != 0) return;
    worldState.refreshToolsGate(chat: _chat, llm: _llm, creator: creatorState);
  }

  void _onToolCheck() => _readToolsGate();

  void _onCreator() {
    _tick();
    _readToolsGate();
  }

  @override
  void initState() {
    super.initState();
    _chat = Provider.of<ChatService>(context, listen: false);
    _llm = Provider.of<LLMProvider>(context, listen: false);
    creatorState.loadSavedState();
    creatorState.addListener(_onCreator);
    worldState.addListener(_tick);
    _chat.addListener(_onToolCheck);
    _llm.addListener(_onToolCheck);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final storage = Provider.of<StorageService>(context, listen: false);
        creatorState.scanLocalModels(storage);
        creatorState.scanLocalPresets(storage);
        creatorState.initLocalSettingsControllers(storage);
        final modelManager = Provider.of<ModelManager>(context, listen: false);
        modelManager.refreshModels();
        if (creatorState.selectedLocalModelPath.isEmpty &&
            storage.backendSettings.lastUsedModelPath != null &&
            storage.backendSettings.lastUsedModelPath!.isNotEmpty) {
          creatorState.selectedLocalModelPath =
              storage.backendSettings.lastUsedModelPath!;
        }
        final llm = Provider.of<LLMProvider>(context, listen: false);
        if (!llm.hasManagedProcess) {
          creatorState.loadAvailableModels(llm);
        }
        final saved = storage.webSearchSettings.savedWikiUrls;
        if (worldState.wikiUrl.isEmpty && saved.isNotEmpty) {
          worldState.wikiUrl = saved.first;
        }
      } catch (_) {}
      _readToolsGate();
    });
  }

  @override
  void dispose() {
    _chat.removeListener(_onToolCheck);
    _llm.removeListener(_onToolCheck);
    creatorState.removeListener(_onCreator);
    worldState.removeListener(_tick);
    creatorState.disposeControllers();
    worldState.disposeControllers();
    super.dispose();
  }

  Future<void> _saveAndFinish() async {
    final repo = Provider.of<WorldRepository>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ok = await worldState.save(repo);
    if (!mounted) return;
    if (ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${worldState.nameController.text.trim()} minted into Worlds.',
          ),
        ),
      );
      navigator.pop();
    }
  }

  Widget _nav() {
    final step = worldState.currentStep;
    final busy = worldState.busy;
    String nextLabel;
    VoidCallback? onNext;
    switch (step) {
      case 0:
        nextLabel = 'Next: Book';
        // Next is the one press that may load a model: an unchecked model
        // is asked here, not when it was picked, and a model that failed
        // once is asked again rather than trusted to have failed.
        final gate = worldState.toolsGate;
        onNext =
            gate == WorldToolsGate.ready ||
                gate == WorldToolsGate.notChecked ||
                gate == WorldToolsGate.failed
            ? () async {
                final ok = await worldState.ensureToolsChecked(
                  chat: _chat,
                  llm: _llm,
                  creator: creatorState,
                );
                if (!ok || !mounted) return;
                worldState.currentStep = 1;
                worldState.notify();
              }
            : null;
      case 1:
        nextLabel = worldState.lorebooksOn ? 'Scout wiki' : 'Next: Preview';
        onNext = busy
            ? null
            : () {
                if (!worldState.lorebooksOn) {
                  worldState.currentStep = 4;
                  worldState.notify();
                  return;
                }
                final storage = Provider.of<StorageService>(
                  context,
                  listen: false,
                );
                worldState.scout(
                  llm: Provider.of<LLMProvider>(context, listen: false),
                  creator: creatorState,
                  contextTokens: worldWizardContextTokens(storage),
                  depth: worldWizardDepth(storage),
                );
              };
      case 2:
        nextLabel = 'Write ${worldState.signed.length} cards';
        onNext = busy || worldState.signed.isEmpty
            ? null
            : () {
                final storage = Provider.of<StorageService>(
                  context,
                  listen: false,
                );
                worldState.write(
                  llm: Provider.of<LLMProvider>(context, listen: false),
                  creator: creatorState,
                  contextTokens: worldWizardContextTokens(storage),
                  depth: worldWizardDepth(storage),
                );
              };
      case 3:
        // Writing: Stop in `bad` (the spec's outlined action); stopped: Back.
        return Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 24),
          child: Center(
            child: worldState.writing
                ? SizedBox(
                    height: 44,
                    child: OutlinedButton.icon(
                      key: const Key('world-from-wiki-stop-nav'),
                      onPressed: worldState.abortWrite,
                      icon: const Icon(Icons.stop, size: 18),
                      label: const Text(
                        'Stop',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: StudioColors.badOf(context),
                        side: BorderSide(
                          color: StudioColors.badOf(context),
                          width: 1.5,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  )
                : CreatorNavBar(
                    busy: false,
                    showBack: true,
                    onBack: () {
                      worldState.currentStep = 2;
                      worldState.notify();
                    },
                    onNext: null,
                    nextLabel: '',
                    showNext: false,
                  ),
          ),
        );
      default:
        // Review: Back, the direction note's send-back, and Mint.
        return WorldReviewNav(
          state: worldState,
          onBack: () {
            worldState.currentStep = 3;
            worldState.notify();
          },
          onSendBack: () => worldState.sendBackAround(
            worldState.directionController.text,
            wholeWorld: worldState.directionWholeWorld,
          ),
          onMint: _saveAndFinish,
        );
    }
    final hint = _navHint(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CreatorNavBar(
          busy: busy,
          showBack: step > 0,
          onBack: () {
            worldState.currentStep = step - 1;
            worldState.notify();
          },
          onNext: onNext,
          nextLabel: nextLabel,
          isLast: step >= 4,
          nextKey: const Key('world-from-wiki-next'),
        ),
        if (hint.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              hint,
              key: const Key('world-from-wiki-nav-hint'),
              style: TextStyle(
                fontSize: 12,
                color: StudioColors.mutedOf(context),
              ),
            ),
          ),
      ],
    );
  }

  /// Why Next is locked, in plain words, and the pill's "ask again" when the
  /// model is running but nothing has asked it yet.
  Widget _toolsBanner(BuildContext context) {
    final gate = worldState.toolsGate;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Row(
        children: [
          if (gate == WorldToolsGate.checking) ...[
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: StudioColors.amberOf(context),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              worldFromWikiToolsCopy(gate) ?? '',
              key: const Key('world-from-wiki-tools-copy'),
              style: TextStyle(
                color: StudioColors.proseOf(context),
                height: 1.4,
              ),
            ),
          ),
          if (worldFromWikiToolsCanRetest(gate))
            TextButton(
              key: const Key('world-from-wiki-tools-retest'),
              onPressed: () => worldState.retestTools(
                chat: _chat,
                llm: _llm,
                creator: creatorState,
              ),
              child: const Text('Check now'),
            ),
        ],
      ),
    );
  }

  static const _stepLabels = ['Setup', 'Book', 'Shelf', 'Write', 'Review'];

  /// The app bar's second line: where the wizard stands, in a few words.
  String _subtitle(BuildContext context) {
    final name = worldState.nameController.text.trim();
    final wiki = worldState.wikiUrl.isEmpty
        ? ''
        : wikiHostLabel(worldState.wikiUrl);
    final storage = Provider.of<StorageService>(context, listen: false);
    switch (worldState.currentStep) {
      case 0:
        return 'Pick the model that writes it';
      case 1:
        if (worldState.scouting) {
          final tokens = worldWizardContextTokens(storage);
          return 'Scouting $wiki · ${worldWizardDepth(storage).label} · '
              '${worldWikiContextLabel(tokens)}';
        }
        return 'A whole place, with its people and its weather, from a wiki '
            'you name';
      case 2:
        return [
          if (name.isNotEmpty) name,
          if (wiki.isNotEmpty) wiki,
        ].join(' · ');
      case 3:
        return worldState.writing
            ? 'Writing ${name.isEmpty ? 'the world' : name}…'
            : 'Stopped';
      default:
        return '${name.isEmpty ? 'The world' : name} · review before you mint';
    }
  }

  /// A line under the nav: how long the next press takes, in plain words.
  String _navHint(BuildContext context) {
    final storage = Provider.of<StorageService>(context, listen: false);
    switch (worldState.currentStep) {
      case 1:
        return worldState.lorebooksOn
            ? 'Full on a remote model: ${worldWizardDepth(storage).timeHint.replaceFirst('About ', 'about ')}, with every step shown'
            : '';
      case 2:
        return 'A few minutes per book on a remote model';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) =>
      CreatorTheme(child: Builder(builder: _scaffold));

  Widget _scaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: StudioColors.bgOf(context),
      appBar: AppBar(
        toolbarHeight: 60,
        backgroundColor: StudioColors.sideOf(context),
        shape: Border(bottom: BorderSide(color: StudioColors.lineOf(context))),
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(
          spacing: 14,
          children: [
            SizedBox.square(
              dimension: 40,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(
                  worldState.writing || worldState.reviewing
                      ? Icons.stop
                      : Icons.arrow_back,
                ),
                tooltip: worldState.writing || worldState.reviewing
                    ? 'Stop'
                    : 'Back',
                color: StudioColors.proseOf(context),
                onPressed: worldState.writing || worldState.reviewing
                    ? worldState.abortWrite
                    : () => Navigator.of(context).pop(),
              ),
            ),
            const WorldIconBadge(icon: Icons.menu_book_outlined, size: 36),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'World from Wiki',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      color: StudioColors.inkOf(context),
                    ),
                  ),
                  Text(
                    _subtitle(context),
                    key: const Key('world-from-wiki-subtitle'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: StudioColors.mutedOf(context),
                    ),
                  ),
                ],
              ),
            ),
            WorldStepIndicator(
              labels: _stepLabels,
              current: worldState.currentStep,
            ),
          ],
        ),
        actions: const [SizedBox(width: 16)],
      ),
      body: Column(
        children: [
          if (worldState.currentStep == 0 && !worldState.toolsReady)
            _toolsBanner(context),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              child: worldState.currentStep == 0
                  ? SetupStep(state: creatorState)
                  : worldState.currentStep == 1
                  ? WorldFromWikiBookStep(state: worldState)
                  : worldState.currentStep == 2
                  ? WorldFromWikiReviewStep(state: worldState)
                  : worldState.currentStep == 3
                  ? WorldFromWikiWriteStep(state: worldState)
                  : WorldFromWikiReviewWorldStep(state: worldState),
            ),
          ),
          _nav(),
        ],
      ),
    );
  }
}
