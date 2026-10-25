// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// When the app writes flash attention off. Seen on real engines on
// 2026-10-04: KoboldCpp 1.122.1 on Vulkan (RX 6900 XT) loads Gemma 4 and
// dies on its first prompt with flash attention on, and runs it with it
// off; the ROCm build ran every model tested with it on. The maintainer
// ruled: Gemma 4 on Vulkan gets it off, in the app's own launches and in
// generated presets; ROCm gets it, unless it already died there.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';

KoboldLaunchConfig _auto({
  required KoboldGpuBackend backend,
  String? architecture,
  KvQuant kvQuant = KvQuant.q8_0,
}) => koboldAppConfig(
  modelPath: '/m/a.gguf',
  settings: KoboldAppSettings(
    contextSize: 16384,
    batchSize: 512,
    layersManual: false,
    manualLayers: 0,
    backend: backend,
    gpuId: 0,
    rocm: false,
    flashAttention: true,
    kvQuant: kvQuant,
    mlock: false,
  ),
  model: KoboldModelFacts(architecture: architecture),
);

KoboldLaunchConfig _generated({
  required KoboldGpuBackend backend,
  String? architecture,
}) => koboldGeneratedPreset(
  modelPath: '/m/a.gguf',
  contextSize: 16384,
  batchSize: 512,
  threads: 8,
  greedyAllocation: false,
  kvQuant: KvQuant.q8_0,
  backend: backend,
  gpuId: null,
  contextMode: ContextManagementMode.fastForwardSmartCache,
  smartCacheSlots: 0,
  architecture: architecture,
);

void main() {
  test('Gemma 4 on Vulkan: flash attention off, and the cache full size '
      'since compression needs it', () {
    for (final config in [
      _auto(backend: KoboldGpuBackend.vulkan, architecture: 'gemma4'),
      _generated(backend: KoboldGpuBackend.vulkan, architecture: 'gemma4'),
    ]) {
      final map = kcppsMap(config);
      expect(map['noflashattention'], isTrue);
      expect(map['quantkv'], 'f16');
    }
  });

  test('Gemma 4 elsewhere, and other models on Vulkan, keep flash attention '
      'and their compressed cache', () {
    for (final config in [
      _auto(backend: KoboldGpuBackend.cuda, architecture: 'gemma4'),
      _auto(backend: KoboldGpuBackend.vulkan, architecture: 'gemma3'),
      _generated(backend: KoboldGpuBackend.cuda, architecture: 'gemma4'),
      _generated(backend: KoboldGpuBackend.vulkan, architecture: 'qwen3'),
    ]) {
      final map = kcppsMap(config);
      expect(map['noflashattention'], isFalse);
      expect(map['quantkv'], 'q8_0');
    }
  });

  test('the launch says why, in plain words', () {
    expect(
      koboldFlashAttentionNote(
        backend: KoboldGpuBackend.vulkan,
        rocm: false,
        architecture: 'gemma4',
      ),
      contains('Gemma 4 on Vulkan'),
    );
    expect(
      koboldFlashAttentionNote(
        backend: KoboldGpuBackend.cuda,
        rocm: true,
        rocmFailedBefore: true,
      ),
      contains('stopped on this machine'),
    );
    expect(
      koboldFlashAttentionNote(backend: KoboldGpuBackend.cuda, rocm: true),
      isNull,
    );
  });

  test('Gemma 4 on Vulkan turned on by the user runs flash attention and '
      'its compressed cache, and the launch has no "off" note', () {
    final auto = kcppsMap(
      koboldAppConfig(
        modelPath: '/m/a.gguf',
        settings: const KoboldAppSettings(
          contextSize: 16384,
          batchSize: 512,
          layersManual: false,
          manualLayers: 0,
          backend: KoboldGpuBackend.vulkan,
          gpuId: 0,
          rocm: false,
          flashAttention: true,
          kvQuant: KvQuant.q8_0,
          mlock: false,
          flashAttentionRiskAccepted: true,
        ),
        model: const KoboldModelFacts(architecture: 'gemma4'),
      ),
    );
    expect(auto['noflashattention'], isFalse);
    expect(auto['quantkv'], 'q8_0');

    // A preset's own box is the say-so: ticked runs it, unticked does not.
    for (final ticked in [true, false]) {
      final preset = kcppsMap(
        KcppsDraft(
          name: 'Mine',
          modelPath: '/m/a.gguf',
          backend: KoboldGpuBackend.vulkan,
          kvQuant: KvQuant.q8_0,
          flashAttention: ticked,
        ).toConfig(architecture: 'gemma4'),
      );
      expect(preset['noflashattention'], !ticked, reason: 'ticked $ticked');
      expect(preset['quantkv'], ticked ? 'q8_0' : 'f16');
    }

    expect(
      koboldFlashAttentionNote(
        backend: KoboldGpuBackend.vulkan,
        rocm: false,
        architecture: 'gemma4',
        riskAccepted: true,
      ),
      isNull,
    );
    expect(
      koboldFlashAttentionRisky(
        backend: KoboldGpuBackend.vulkan,
        architecture: 'gemma4',
      ),
      isTrue,
    );
    expect(
      koboldFlashAttentionRisky(
        backend: KoboldGpuBackend.cuda,
        architecture: 'gemma4',
      ),
      isFalse,
    );
  });
}
