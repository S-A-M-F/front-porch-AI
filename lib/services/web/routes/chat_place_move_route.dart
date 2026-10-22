// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Slice 6: answering a suggested scene move over the relay. Its own file
// because chat_routes.dart sits one line under the 500-line ratchet and
// every slice-4/6 endpoint has to fit somewhere.

import 'package:shelf/shelf.dart' as shelf;

import 'package:front_porch_ai/services/web/facade/chat_facade.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

/// POST /api/chat/place-move — {accept: true} runs the desktop's manual
/// swap through the ONE slots writer; {accept: false} records the
/// decline for this Setting. The flag then leaves the snapshot on the
/// next tick, closing the modal in both shells.
/// POST /api/chat/guest-picker/dismiss — close a parked `/join` picker.
/// (Same extraction rationale as [handlePlaceMove]; kept beside it so the
/// two scene-prompt endpoints live in one readable place.)
shelf.Response handleDismissGuestPicker(ChatFacade facade) {
  facade.dismissGuestPicker();
  return JsonResponse.ok({'ok': true});
}

Future<shelf.Response> handlePlaceMove(
  ChatFacade facade,
  shelf.Request request,
) async {
  final body = await RequestBody.readJsonMap(request);
  await facade.answerPlaceMove(body['accept'] == true);
  return JsonResponse.ok({'ok': true});
}
