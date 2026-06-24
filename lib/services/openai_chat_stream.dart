// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:front_porch_ai/services/llm_service.dart';

/// Streams an OpenAI-compatible `/v1/chat/completions` response token by token.
///
/// This is the single transport shared by every backend that speaks the OpenAI
/// chat protocol: the `.kcpps` pseudo-remote backend and the managed local
/// KoboldCpp backend both point it at `http://127.0.0.1:5001`.
///
/// Why this matters for local KoboldCpp: KoboldCpp serves this endpoint on the
/// same port as its native API and applies the loaded model's instruct/chat
/// template server-side — which the raw `/api/extra/generate/stream` endpoint
/// does NOT. Routing local generation here is what lets instruct GGUFs follow
/// instructions (character cards, realism evals) and stop naturally via EOS,
/// instead of emitting an immediate empty response or running away repeating on
/// an un-templated prompt.
///
/// [baseUrl] is the server root WITHOUT a trailing slash (e.g.
/// `http://127.0.0.1:5001`); `/v1/chat/completions` is appended here. KoboldCpp
/// ignores [modelName] (it serves the single loaded model), so a placeholder is
/// fine. [registerClient] hands the live [http.Client] to the caller so an abort
/// can close it; [onDone] fires in `finally` so the caller can clear its handle.
///
/// Kept intentionally minimal and identical to the long-proven pseudo-remote
/// path: a single `user` message (plus optional `system`), `frequency_penalty`
/// derived from `repeatPenalty`, and the model's own template doing the rest.
Stream<String> streamOpenAiChat(
  String baseUrl,
  GenerationParams params, {
  String modelName = 'koboldcpp',
  void Function(http.Client client)? registerClient,
  void Function()? onDone,
}) async* {
  final uri = Uri.parse('$baseUrl/v1/chat/completions');

  final messages = <Map<String, String>>[];
  if (params.systemPrompt != null && params.systemPrompt!.isNotEmpty) {
    messages.add({'role': 'system', 'content': params.systemPrompt!});
  }
  messages.add({'role': 'user', 'content': params.prompt});

  final payload = <String, dynamic>{
    'model': modelName,
    'stream': true,
    'max_tokens': params.maxLength,
    'temperature': params.temperature,
    'top_p': params.topP,
    'frequency_penalty': params.repeatPenalty > 1.0
        ? (params.repeatPenalty - 1.0).clamp(0.0, 2.0)
        : 0.0,
    'messages': messages,
  };

  if (params.reasoningEnabled || params.reasoningMaxTokens != null) {
    final reasoning = <String, dynamic>{'enabled': params.reasoningEnabled};
    if (params.reasoningEnabled) {
      reasoning['effort'] = params.reasoningEffort;
    }
    if (params.reasoningMaxTokens != null) {
      reasoning['max_tokens'] = params.reasoningMaxTokens;
    }
    if (!params.reasoningEnabled) {
      reasoning['exclude'] = true;
    }
    payload['reasoning'] = reasoning;
  }

  if (params.stopSequences != null && params.stopSequences!.isNotEmpty) {
    payload['stop'] = params.stopSequences!.take(4).toList();
  }

  final request = http.Request('POST', uri);
  request.headers['Content-Type'] = 'application/json';
  request.body = jsonEncode(payload);

  final client = http.Client();
  registerClient?.call(client);

  try {
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 120));

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      String errorMsg = 'HTTP ${response.statusCode}';
      try {
        final errJson = jsonDecode(body);
        errorMsg = errJson['error']?['message'] ?? errorMsg;
      } catch (_) {}
      throw Exception('API error: $errorMsg');
    }

    String buffer = '';
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      buffer += chunk;
      while (buffer.contains('\n')) {
        final idx = buffer.indexOf('\n');
        final line = buffer.substring(0, idx).trim();
        buffer = buffer.substring(idx + 1);
        if (line.isEmpty) continue;
        if (line == 'data: [DONE]' || line == 'data:[DONE]') return;
        if (!line.startsWith('data:')) continue;
        final data = line.startsWith('data: ')
            ? line.substring(6)
            : line.substring(5);
        try {
          final json = jsonDecode(data);
          final choice = json['choices']?[0];
          final delta = choice?['delta'];
          if (delta == null) continue;
          final content = delta['content'];
          if (content != null && content is String && content.isNotEmpty) {
            yield content;
          }
        } catch (_) {}
      }
    }
  } finally {
    onDone?.call();
    client.close();
  }
}
