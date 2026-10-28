// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Slice 6: the state half of confirmed scene moves — where the clock judge's
// arrival answer waits for the author. The service NEVER applies a move;
// this object holds the offer, remembers declines for the CURRENT setting
// only, and is emptied the moment the Setting changes (a declined Tea Rooms
// under one setting must be offerable again once the scene has moved,
// because arrival is re-judged from a new place).

import 'scene_mint_state.dart';

/// One suggested move: an offered place the judge says the reply arrived at.
class PendingPlaceMove {
  const PendingPlaceMove({required this.id, required this.name});
  final String id;
  final String name;
}

/// The offer + the decline memory. One pending move per chat (design §3:
/// one scene place, no split parties); declines are remembered per setting.
class SceneMoveState {
  PendingPlaceMove? pending;

  /// Slice 7: the mint half of the same suggestion pipeline — one
  /// proposed place awaiting the author's tap, plus the per-chat
  /// ignored-name memory. Cleared by the same reset sites as the move
  /// flags (chat/session boundaries), unlike declines which are
  /// setting-scoped: an ignored 'Salt Garden' stays ignored until the
  /// chat changes, because the name itself, not the vantage, was
  /// refused.
  final SceneMintState mints = SceneMintState();

  /// Place ids declined while the setting was [_declineScope]. Any pending
  /// or declined id equal to the CURRENT setting itself is never offered
  /// (you are already there) — the reach law excludes it upstream, too.
  final Set<String> _declined = {};
  String? _declineScope;

  bool isDeclined(String id) => _declined.contains(id);

  void decline(String id, String? currentSettingId) {
    if (_declineScope != currentSettingId) {
      _declined.clear();
      _declineScope = currentSettingId;
    }
    _declined.add(id);
    pending = null;
  }

  /// The Setting changed (a move landed, manual or not): the decline
  /// memory was written AT the old setting and dies with it, and any
  /// still-open dialog offer about the old place is stale.
  void settingChanged() {
    _declined.clear();
    _declineScope = null;
    pending = null;
  }

  /// Session-reset parity with the Scene-Guest flags.
  void reset() {
    pending = null;
    _declined.clear();
    _declineScope = null;
    mints.reset();
  }
}
