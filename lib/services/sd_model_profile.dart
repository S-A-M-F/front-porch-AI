import 'dart:io';

/// Known Stable Diffusion architecture families.
enum SdArchitecture {
  sd15,    // Stable Diffusion 1.5 (512×512 native)
  sdxl,    // Stable Diffusion XL (1024×1024 native)
  flux,    // Black Forest Labs Flux (1024×1024, natural language)
  sd3,     // Stability AI SD3 / SD3.5 (1024×1024)
  unknown, // Fallback — use conservative SD 1.5-style defaults
}

/// Auto-detected generation profile for a Stable Diffusion model.
/// Determines optimal resolution, steps, CFG scale, and prompt style
/// based on the model's architecture family.
class SdModelProfile {
  final SdArchitecture architecture;
  final String label;           // Human-readable name, e.g. "Stable Diffusion XL"
  final int nativeWidth;        // Optimal width for this architecture
  final int nativeHeight;       // Optimal height for this architecture
  final int defaultSteps;       // Default inference steps
  final double defaultCfgScale; // Default CFG guidance scale
  final bool prefersNaturalLanguage; // true = natural lang prompts, false = tag-style
  final String promptTip;       // Brief guidance text shown in UI

  const SdModelProfile({
    required this.architecture,
    required this.label,
    required this.nativeWidth,
    required this.nativeHeight,
    required this.defaultSteps,
    required this.defaultCfgScale,
    required this.prefersNaturalLanguage,
    required this.promptTip,
  });

  /// Detect the SD architecture from a model filename.
  /// Uses pattern matching on common naming conventions.
  factory SdModelProfile.fromFilename(String filename) {
    final lower = filename.toLowerCase();

    // ── Flux ──────────────────────────────────────────────────
    if (lower.contains('flux') ||
        lower.contains('black-forest') ||
        lower.contains('bfl')) {
      return const SdModelProfile(
        architecture: SdArchitecture.flux,
        label: 'Flux',
        nativeWidth: 1024,
        nativeHeight: 1024,
        defaultSteps: 4,       // Flux is distilled, needs very few steps
        defaultCfgScale: 1.0,  // Flux ignores CFG typically
        prefersNaturalLanguage: true,
        promptTip: 'Flux excels with natural language descriptions. No need for tags.',
      );
    }

    // ── SD3 / SD3.5 ──────────────────────────────────────────
    if (lower.contains('sd3') ||
        lower.contains('stable-diffusion-3') ||
        lower.contains('sd-3')) {
      return const SdModelProfile(
        architecture: SdArchitecture.sd3,
        label: 'Stable Diffusion 3',
        nativeWidth: 1024,
        nativeHeight: 1024,
        defaultSteps: 28,
        defaultCfgScale: 4.5,
        prefersNaturalLanguage: true,
        promptTip: 'SD3 works well with natural language and light tagging.',
      );
    }

    // ── SDXL ─────────────────────────────────────────────────
    if (lower.contains('sdxl') ||
        lower.contains('sd_xl') ||
        lower.contains('xl-base') ||
        lower.contains('stable-diffusion-xl') ||
        lower.contains('pony') ||  // PonyDiffusion is SDXL-based
        lower.contains('animagine-xl') ||
        lower.contains('juggernaut-xl') ||
        lower.contains('dreamshaper-xl')) {
      return const SdModelProfile(
        architecture: SdArchitecture.sdxl,
        label: 'Stable Diffusion XL',
        nativeWidth: 1024,
        nativeHeight: 1024,
        defaultSteps: 25,
        defaultCfgScale: 7.0,
        prefersNaturalLanguage: false,
        promptTip: 'SDXL works best with detailed tag-style prompts.',
      );
    }

    // ── SD 1.5 (explicit match) ──────────────────────────────
    if (lower.contains('sd15') ||
        lower.contains('sd-1.5') ||
        lower.contains('sd_1.5') ||
        lower.contains('v1-5') ||
        lower.contains('v1.5') ||
        lower.contains('sd-v1') ||
        lower.contains('dreamshaper') ||   // DreamShaper (non-XL) is SD 1.5
        lower.contains('deliberate') ||    // Deliberate v2/v3 is SD 1.5
        lower.contains('realistic-vision') ||
        lower.contains('cyberrealistic') ||
        lower.contains('meinamix') ||
        lower.contains('anything-v') ||    // Anything v3/v4/v5 is SD 1.5
        lower.contains('counterfeit') ||
        lower.contains('revanimated') ||
        lower.contains('ghostmix')) {
      return const SdModelProfile(
        architecture: SdArchitecture.sd15,
        label: 'Stable Diffusion 1.5',
        nativeWidth: 512,
        nativeHeight: 512,
        defaultSteps: 20,
        defaultCfgScale: 7.0,
        prefersNaturalLanguage: false,
        promptTip: 'SD 1.5 prefers comma-separated tags: "1girl, blue hair, portrait, detailed"',
      );
    }

    // ── Unknown / Fallback → conservative SD 1.5-style defaults ──
    return const SdModelProfile(
      architecture: SdArchitecture.unknown,
      label: 'Unknown SD Model',
      nativeWidth: 512,
      nativeHeight: 512,
      defaultSteps: 20,
      defaultCfgScale: 7.0,
      prefersNaturalLanguage: false,
      promptTip: 'Using safe defaults. Specify model type in the filename for auto-detection.',
    );
  }

  /// Detect profile from an absolute file path (extracts basename).
  factory SdModelProfile.fromPath(String filePath) {
    final basename = filePath.split(Platform.pathSeparator).last;
    return SdModelProfile.fromFilename(basename);
  }

  /// Return the portrait-optimized resolution (3:4 ratio) for this architecture.
  /// Useful for character avatar generation.
  ({int width, int height}) get portraitSize {
    switch (architecture) {
      case SdArchitecture.sd15:
        return (width: 384, height: 512);
      case SdArchitecture.sdxl:
      case SdArchitecture.sd3:
        return (width: 768, height: 1024);
      case SdArchitecture.flux:
        return (width: 768, height: 1024);
      case SdArchitecture.unknown:
        return (width: 384, height: 512);
    }
  }

  /// Return the square resolution for this architecture (used for most gen).
  ({int width, int height}) get squareSize {
    return (width: nativeWidth, height: nativeHeight);
  }

  /// Adapt a prompt to work optimally with this architecture.
  /// For tag-style models (SD 1.5, SDXL): converts natural language to tags.
  /// For natural language models (Flux, SD3): passes through cleanly.
  String adaptPrompt(String rawPrompt) {
    if (prefersNaturalLanguage) {
      // Flux/SD3: natural language is fine, just clean up
      return rawPrompt.trim();
    }

    // Tag-style models: ensure the prompt is comma-separated tags
    // If the prompt looks like natural language (has "a", "the", "is", etc.),
    // do a light conversion
    final words = rawPrompt.split(' ');
    final hasArticles = words.any((w) =>
        ['a', 'an', 'the', 'is', 'are', 'was', 'were', 'with', 'has', 'have',
         'who', 'that', 'this', 'from', 'they', 'she', 'he', 'her', 'his']
            .contains(w.toLowerCase()));

    if (hasArticles && !rawPrompt.contains(',')) {
      // Looks like natural language without commas — do a light tag conversion
      // Remove common articles and convert to comma-separated
      String cleaned = rawPrompt;
      for (final article in ['a ', 'an ', 'the ', 'is ', 'are ', 'was ', 'were ']) {
        cleaned = cleaned.replaceAll(RegExp('\\b$article', caseSensitive: false), '');
      }
      // Split on spaces and rejoin with commas for tag-heavy models
      final tags = cleaned.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
      return tags.join(', ');
    }

    return rawPrompt.trim();
  }

  @override
  String toString() => 'SdModelProfile($label, ${nativeWidth}×$nativeHeight, steps=$defaultSteps, cfg=$defaultCfgScale)';
}
