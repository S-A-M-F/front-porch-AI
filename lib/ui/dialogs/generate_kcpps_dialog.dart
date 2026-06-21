import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/model_manager.dart';
import 'package:front_porch_ai/services/kcpps_generator_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/gguf_parser.dart';
import 'package:front_porch_ai/utils/vram_estimator.dart';

class GenerateKcppsDialog extends StatefulWidget {
  const GenerateKcppsDialog({super.key});

  @override
  State<GenerateKcppsDialog> createState() => _GenerateKcppsDialogState();
}

class _GenerateKcppsDialogState extends State<GenerateKcppsDialog> {
  String? _selectedModelPath;
  final _contextSizeController = TextEditingController(text: '8192');
  int _contextSize = 8192;
  String _kvQuant = 'f16';
  int _threads = 4;
  int _batchSize = 512;
  bool _greedyAllocation = false;
  ContextManagementMode _contextMode = ContextManagementMode.fastForwardSmartCache;
  int _smartCacheSlots = 5;
  final _smartCacheSlotsController = TextEditingController(text: '5');
  bool _detecting = true;
  bool _generating = false;
  GGUFModelInfo? _modelInfo;
  HardwareInfo? _hardwareInfo;
  Map<String, dynamic> _gpuConfig = {};
  String? _errorMessage;
  ({
    int weightsMb,
    int kvCacheMb,
    int computeBufMb,
    int overheadMb,
    int totalMb,
    double activeWeightRatio,
  })? _vramEstimate;

  final _kvQuantOptions = ['f16', 'q8_0', 'q4_0'];
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    Provider.of<HardwareService>(context, listen: false).addListener(_onHardwareChanged);
    _initDetection();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    Provider.of<HardwareService>(context, listen: false).removeListener(_onHardwareChanged);
    _contextSizeController.dispose();
    _smartCacheSlotsController.dispose();
    super.dispose();
  }

  void _onHardwareChanged() {
    if (!mounted) return;
    final hw = Provider.of<HardwareService>(context, listen: false);
    if (hw.hardwareInfo == null) return;
    if (_hardwareInfo == hw.hardwareInfo && _gpuConfig.isNotEmpty) return;

    _hardwareInfo = hw.hardwareInfo;
    _gpuConfig = KcppsGeneratorService.detectGpuBackend(_hardwareInfo);
    _computeVramEstimate();
    final newBatchSize = _suggestBatchSize();
    setState(() => _batchSize = newBatchSize);
  }

  Future<void> _initDetection() async {
    try {
      final hardware = Provider.of<HardwareService>(context, listen: false);
      _hardwareInfo = hardware.hardwareInfo;
      _gpuConfig = KcppsGeneratorService.detectGpuBackend(_hardwareInfo);

      final detected = await KcppsGeneratorService.suggestThreadCount();

      setState(() {
        _threads = detected;
        _batchSize = _suggestBatchSize();
        _detecting = false;
      });
      _computeVramEstimate();
    } catch (_) {
      setState(() {
        _detecting = false;
      });
    }
  }

  Future<void> _refreshModelInfo() async {
    if (_selectedModelPath == null) return;
    final mgr = Provider.of<ModelManager>(context, listen: false);
    final info = await mgr.getModelArchitectureInfo(_selectedModelPath!);
    setState(() {
      _modelInfo = info;
      _batchSize = _suggestBatchSize();
    });
    _computeVramEstimate();
  }

  Future<void> _refreshDefaults() async {
    setState(() {
      _batchSize = _suggestBatchSize();
    });
    _computeVramEstimate();
  }

  void _debouncedEstimate() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _computeVramEstimate();
    });
  }

  void _computeVramEstimate() {
    if (_selectedModelPath == null) {
      _vramEstimate = null;
      return;
    }
    final file = File(_selectedModelPath!);
    if (!file.existsSync()) {
      _vramEstimate = null;
      return;
    }
    final fileSizeBytes = file.lengthSync();
    final fileSizeMb = fileSizeBytes ~/ (1024 * 1024);

    if (_modelInfo != null) {
      _vramEstimate = VramEstimator.estimateFromArchitecture(
        modelInfo: _modelInfo!,
        fileSizeBytes: fileSizeBytes,
        contextSize: _contextSize,
        batchSize: _batchSize,
        kvQuant: _kvQuant,
        isSwa: _contextMode == ContextManagementMode.slidingWindowAttention,
        moeExpertsOnCpu: true,
      );
    } else if (_hardwareInfo?.vramMb != null && _hardwareInfo!.vramMb > 0) {
      final totalMb = VramEstimator.estimateVramNeeded(
        fileSizeBytes: fileSizeBytes,
        contextSize: _contextSize,
      );
      final kvMb = (totalMb - fileSizeMb - VramEstimator.defaultFixedOverheadMb)
          .clamp(0, totalMb);
      _vramEstimate = (
        weightsMb: fileSizeMb,
        kvCacheMb: kvMb,
        computeBufMb: 0,
        overheadMb: VramEstimator.defaultFixedOverheadMb,
        totalMb: totalMb,
        activeWeightRatio: 1.0,
      );
    } else {
      _vramEstimate = null;
    }
  }

  int _suggestBatchSize() {
    final vramMb = _hardwareInfo?.vramMb ?? 0;
    if (vramMb <= 0 || _selectedModelPath == null) return 512;
    final file = File(_selectedModelPath!);
    if (!file.existsSync()) return 512;

    // Use a reasonable default if model info isn't available yet
    final modelInfo = _modelInfo ?? GGUFModelInfo(
      nLayers: 32,
      nHeads: 32,
      nKvHeads: 8,
      nEmbd: 4096,
      kvBytesPerToken: 2048,
    );

    final padding = _greedyAllocation ? 32 : 1024;

    return VramEstimator.suggestBatchSize(
      modelInfo: modelInfo,
      fileSizeBytes: file.lengthSync(),
      contextSize: _contextSize,
      kvQuant: _kvQuant,
      isSwa: _contextMode == ContextManagementMode.slidingWindowAttention,
      moeExpertsOnCpu: true,
      availableVramMb: vramMb,
      autofitpaddingMb: padding,
    );
  }

  Future<void> _generate() async {
    if (_selectedModelPath == null) {
      setState(() => _errorMessage = 'Please select a model first.');
      return;
    }

    setState(() {
      _generating = true;
      _errorMessage = null;
    });

    try {
      final storage = Provider.of<StorageService>(context, listen: false);
      final content = KcppsGeneratorService.buildKcppsContent(
        modelPath: _selectedModelPath!,
        contextSize: _contextSize,
        batchSize: _batchSize,
        threads: _threads,
        kvQuant: _kvQuant,
        greedyAllocation: _greedyAllocation,
        gpuConfig: _gpuConfig,
        contextMode: _contextMode,
        smartCacheSlots: _smartCacheSlots,
      );

      final kcppsFile = await KcppsGeneratorService.writeKcppsFile(
        storage.binDir,
        _selectedModelPath!,
        content,
      );

      await storage.setModelPreset(_selectedModelPath!, kcppsFile.path);
      await storage.setActiveKcppsPath(kcppsFile.path);

      if (!mounted) return;
      Navigator.of(context).pop(true);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'KCPPS config generated for ${path.basename(_selectedModelPath!)}',
          ),
        ),
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to generate config: $e';
      });
    } finally {
      setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final modelManager = Provider.of<ModelManager>(context, listen: false);
    final theme = Theme.of(context);
    final colors = AppColors.surfaceContainerOf(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.tune,
                    color: AppColors.textPrimary(context),
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Generate KCPPS Config',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                ],
              ),
            ),
            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Model selector
                    Text(
                      'Model',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    ModelSelector(
                      models: modelManager.models,
                      selectedModelPath: _selectedModelPath,
                      showManagedByKcpps: false,
                      onChanged: (val) {
                        setState(() {
                          _selectedModelPath = val;
                          _modelInfo = null;
                        });
                        if (val != null) _refreshModelInfo();
                      },
                    ),
                    const SizedBox(height: 20),

                    // Context size
                    Text(
                      'Context Size',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _contextSizeController,
                      keyboardType: TextInputType.number,
                      style: theme.textTheme.bodyMedium,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        filled: true,
                        fillColor: colors,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        suffixText: 'tokens',
                        suffixStyle: TextStyle(
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                      onChanged: (val) {
                        final parsed = int.tryParse(val);
                        if (parsed != null && parsed > 0) {
                          setState(() {
                            _contextSize = parsed;
                            _batchSize = _suggestBatchSize();
                          });
                          _debouncedEstimate();
                        }
                      },
                    ),
                    const SizedBox(height: 20),

                    // KV Cache Quantization
                    Text(
                      'KV Cache Quantization',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _buildDropdown(
                      value: _kvQuant,
                      items: _kvQuantOptions,
                      onChanged: (val) {
                        setState(() => _kvQuant = val!);
                        _refreshDefaults();
                      },
                      colors: colors,
                      theme: theme,
                    ),
                    const SizedBox(height: 20),

                    // CPU Threads
                    Text(
                      'CPU Threads',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: TextEditingController(text: '$_threads'),
                      keyboardType: TextInputType.number,
                      style: theme.textTheme.bodyMedium,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        filled: true,
                        fillColor: colors,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        hintText: _detecting ? 'Detecting...' : null,
                      ),
                      onChanged: (val) {
                        final parsed = int.tryParse(val);
                        if (parsed != null && parsed > 0) {
                          _threads = parsed;
                        }
                      },
                    ),
                    const SizedBox(height: 20),

                    // Batch Size
                    Text(
                      'Batch Size',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: TextEditingController(text: '$_batchSize'),
                      keyboardType: TextInputType.number,
                      style: theme.textTheme.bodyMedium,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        filled: true,
                        fillColor: colors,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (val) {
                        final parsed = int.tryParse(val);
                        if (parsed != null && parsed > 0) {
                          _batchSize = parsed.clamp(64, 8192);
                        }
                        _debouncedEstimate();
                      },
                    ),
                    const SizedBox(height: 20),

                    // Context Management
                    Text(
                      'Context Management',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: colors,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: RadioGroup<ContextManagementMode>(
                        groupValue: _contextMode,
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _contextMode = v);
                            _computeVramEstimate();
                          }
                        },
                        child: Column(
                          children: [
                            RadioListTile<ContextManagementMode>(
                              title: const Text(
                                'Sliding Window Attention (SWA)',
                                style: TextStyle(fontSize: 13),
                              ),
                              subtitle: const Text(
                                'Slightly lower VRAM, incompatible with '
                                'FastForwarding/ContextShift',
                                style: TextStyle(fontSize: 11),
                              ),
                              dense: true,
                              value: ContextManagementMode
                                  .slidingWindowAttention,
                            ),
                            RadioListTile<ContextManagementMode>(
                              title: const Text(
                                'FastForwarding + ContextShift + SmartCache',
                                style: TextStyle(fontSize: 13),
                              ),
                              subtitle: const Text(
                                'Faster context reprocessing, '
                                'uses RAM for cached context',
                                style: TextStyle(fontSize: 11),
                              ),
                              dense: true,
                              value: ContextManagementMode
                                  .fastForwardSmartCache,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_contextMode ==
                        ContextManagementMode.fastForwardSmartCache) ...[
                      const SizedBox(height: 12),
                      Text(
                        'SmartCache Slots',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _smartCacheSlotsController,
                        keyboardType: TextInputType.number,
                        style: theme.textTheme.bodyMedium,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          filled: true,
                          fillColor: colors,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (val) {
                          final parsed = int.tryParse(val);
                          if (parsed != null && parsed > 0) {
                            _smartCacheSlots = parsed.clamp(1, 20);
                          }
                        },
                      ),
                    ],
                    const SizedBox(height: 20),

                    // Greedy allocation toggle
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: colors,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Greedy memory allocation',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  'Lower padding = more VRAM for model, '
                                  'brief startup freeze',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary(context),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _greedyAllocation,
                            activeTrackColor: Colors.blueAccent,
                            onChanged: (val) {
                              setState(() => _greedyAllocation = val);
                              _computeVramEstimate();
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // GPU info (read-only)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: colors,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.memory,
                            size: 16,
                            color: AppColors.textSecondary(context),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _hardwareInfo != null
                                  ? 'GPU: ${_hardwareInfo!.gpuName} '
                                      '(${_hardwareInfo!.vramMb}MB VRAM)'
                                      '${_gpuConfig.isNotEmpty ? " — ${_gpuConfig.keys.first}" : " — CPU"}'
                                  : 'GPU: detecting...',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondary(context),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                    _buildVramSection(context, theme, colors),
                    const SizedBox(height: 4),

                    // Error message
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Footer buttons
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed:
                        (_generating || _selectedModelPath == null)
                            ? null
                            : _generate,
                    icon: _generating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_fix_high, size: 18),
                    label: Text(
                      _generating ? 'Generating...' : 'Generate & Apply',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVramSection(BuildContext context, ThemeData theme, Color colors) {
    if (_selectedModelPath == null) return const SizedBox.shrink();

    if (_vramEstimate == null) {
      String msg;
      if (_modelInfo == null) {
        msg = _hardwareInfo?.vramMb != null
            ? 'Parsing model metadata...'
            : 'Detecting hardware...';
      } else {
        msg = _hardwareInfo?.vramMb != null
            ? 'VRAM estimate unavailable'
            : 'Waiting for GPU detection...';
      }
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colors,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.memory, size: 16,
                color: AppColors.textSecondary(context)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                msg,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary(context),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final availableMb = _hardwareInfo?.vramMb ?? 0;
    final fraction = availableMb > 0 ? _vramEstimate!.totalMb / availableMb : 0.0;
    final fits = fraction <= 1.0;

    final Color barColor;
    if (!fits) {
      barColor = Colors.redAccent;
    } else if (fraction > 0.85) {
      barColor = Colors.deepOrange;
    } else if (fraction > 0.6) {
      barColor = Colors.amber.shade700;
    } else {
      barColor = Colors.green;
    }

    final paddingMb = _greedyAllocation ? 32 : 1024;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.memory, size: 16,
                  color: AppColors.textSecondary(context)),
              const SizedBox(width: 8),
              Text(
                'VRAM Usage Estimate',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary(context),
                ),
              ),
              const Spacer(),
              if (_modelInfo == null) ...[
                Text(
                  '(basic)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: Colors.amber.shade500,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Icon(
                fits
                    ? Icons.check_circle_outline
                    : Icons.warning_amber_rounded,
                size: 16,
                color: fits ? Colors.green : Colors.redAccent,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              backgroundColor: const Color(0x4D808080),
              valueColor: AlwaysStoppedAnimation(barColor),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Weights: ${_vramEstimate!.weightsMb} MB  ·  '
            'KV: ${_vramEstimate!.kvCacheMb} MB  ·  '
            'Compute: ${_vramEstimate!.computeBufMb} MB  ·  '
            'Overhead: ${_vramEstimate!.overheadMb} MB',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: AppColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Total: ${_vramEstimate!.totalMb} MB / $availableMb MB '
            '(${(fraction * 100).toStringAsFixed(0)}%)'
            '${fits ? "" : " — EXCEEDS VRAM"}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: fits ? null : Colors.redAccent,
            ),
          ),
          if (_modelInfo?.isMoe == true) ...[
            const SizedBox(height: 4),
            Text(
              'MoE: ${(_vramEstimate!.activeWeightRatio * 100).toStringAsFixed(0)}% active '
              '(${_modelInfo!.expertUsedCount ?? "?"} of ${_modelInfo!.expertCount ?? "?"} experts on GPU)',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: AppColors.textSecondary(context),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Autofit padding: $paddingMb MB${_greedyAllocation ? " (greedy)" : ""}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: AppColors.textSecondary(context),
            ),
          ),
          if (!fits) ...[
            const SizedBox(height: 4),
            Text(
              'Reduce context size or enable greedy allocation',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: Colors.redAccent,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    required Color colors,
    required ThemeData theme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: colors,
          style: theme.textTheme.bodyMedium?.apply(
            color: AppColors.textPrimary(context),
          ),
          icon: Icon(
            Icons.arrow_drop_down,
            color: AppColors.textSecondary(context),
          ),
          items: items.map((v) {
            String label;
            if (v == 'f16') {
              label = 'None (f16) — highest quality';
            } else if (v == 'q8_0') {
              label = '8-bit (q8_0) — ~50% savings';
            } else {
              label = '4-bit (q4_0) — ~75% savings';
            }
            return DropdownMenuItem<String>(
              value: v,
              child: Text(label, style: const TextStyle(fontSize: 13)),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
