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

import 'package:front_porch_ai/services/chat/eval_lane_params.dart';
import 'package:front_porch_ai/services/chat/tool_catalog.dart';
import 'package:front_porch_ai/services/chat/web_search_tools.dart';
import 'package:front_porch_ai/services/llm_service.dart';

/// Instruction for the web-search doorbell. It sees [lastUserMessage] only.
const String kWebSearchDoorbellSystem =
    'The message below is the user\'s latest line and nothing else. '
    'If it names a person, place, work, character, title, or fact that '
    'should be looked up, call web_search with a short search-box query '
    '(the name, plus at most one extra word). '
    'If nothing needs a lookup, do not call a tool.';

/// Eval-lane params for the web-search check. No character card, no
/// transcript, no images. Wiki and recipe cards do not use this.
GenerationParams webSearchDoorbellParams(String lastUserMessage) {
  return evalLaneParams(
    prompt: lastUserMessage.trim(),
    systemPrompt: kWebSearchDoorbellSystem,
  );
}

/// One doorbell trip: which tools, and which prompt they are allowed to see.
class CatalogDoorbellJob {
  const CatalogDoorbellJob({required this.params, required this.catalog});

  final GenerationParams params;
  final CatalogBuildResult catalog;
}

/// Web search gets [lastUserMessage]. Every other advertised tool keeps
/// [mouth], the character prompt. An empty user line skips the search trip.
List<CatalogDoorbellJob> catalogDoorbellJobs({
  required GenerationParams mouth,
  required CatalogBuildResult catalog,
  required String lastUserMessage,
}) {
  final search = <CatalogTool>[];
  final rest = <CatalogTool>[];
  for (final tool in catalog.tools) {
    if (tool.name == kWebSearchToolName) {
      search.add(tool);
    } else {
      rest.add(tool);
    }
  }
  final jobs = <CatalogDoorbellJob>[];
  final line = lastUserMessage.trim();
  if (search.isNotEmpty && line.isNotEmpty) {
    jobs.add(
      CatalogDoorbellJob(
        params: webSearchDoorbellParams(line),
        catalog: CatalogBuildResult(tools: search, exclusions: const []),
      ),
    );
  }
  if (rest.isNotEmpty) {
    jobs.add(
      CatalogDoorbellJob(
        params: mouth,
        catalog: CatalogBuildResult(
          tools: rest,
          exclusions: catalog.exclusions,
        ),
      ),
    );
  }
  return jobs;
}
