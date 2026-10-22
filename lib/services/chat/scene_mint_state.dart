// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Slice 7: the mint half of scene suggestions. When the judge says the
// reply arrived at a NAMED place that isn't in the library, it flags a
// mint proposal; nothing becomes a World until the author taps. Ignored
// names are remembered for the chat so the same side street is not
// pitched again (session reset forgets, same law as Scene-Guest names).

/// One proposed mint: the name and one-line descriptor the model heard
/// in the narration — the same pair DetectedCharacter carries.
class ProposedPlace {
  const ProposedPlace({required this.name, required this.descriptor});
  final String name;
  final String descriptor;
}

class SceneMintState {
  ProposedPlace? pending;

  final Set<String> _ignored = {};

  bool isIgnored(String name) => _ignored.contains(name.trim().toLowerCase());

  void ignore(String name) {
    _ignored.add(name.trim().toLowerCase());
    pending = null;
  }

  void resolve() => pending = null;

  void reset() {
    pending = null;
    _ignored.clear();
  }
}
