import 'package:kobold_character_card_manager/services/hardware_service.dart';

class OptimizationResult {
  final int gpuLayers;
  final int contextSize;
  final bool useVulkan;
  final String reasoning;

  OptimizationResult({
    required this.gpuLayers,
    required this.contextSize,
    required this.useVulkan,
    required this.reasoning,
  });
}

class OptimizationService {
  static OptimizationResult calculateSettings(HardwareInfo hardware, {int modelSizeMb = 0}) {
    int vram = hardware.vramMb;
    
    // Default to Vulkan for non-Nvidia
    bool useVulkan = hardware.vendor != 'Nvidia'; 

    // Basic heuristic: if VRAM is generous, offload everything
    if (vram > modelSizeMb + 1000) {
      return OptimizationResult(
        gpuLayers: 99, // Offload all
        contextSize: 8192,
        useVulkan: useVulkan,
        reasoning: 'High VRAM detected. Offloading all layers to GPU.${useVulkan ? " Using Vulkan." : ""}',
      );
    } else if (vram > 4000) {
       return OptimizationResult(
        gpuLayers: 20,
        contextSize: 4096,
        useVulkan: useVulkan,
        reasoning: 'Moderate VRAM. Offloading some layers.${useVulkan ? " Using Vulkan." : ""}',
      );
    } else {
      return OptimizationResult(
        gpuLayers: 0,
        contextSize: 2048,
        useVulkan: useVulkan,
        reasoning: 'Low VRAM. Running primarily on CPU.',
      );
    }
  }
}
