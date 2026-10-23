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

import 'package:flutter/foundation.dart';
import '../mediawiki_categories.dart';

import 'package:front_porch_ai/services/chat/mediawiki_search.dart';
import 'package:front_porch_ai/services/chat/tiddly_wiki.dart';
import 'package:front_porch_ai/services/chat/wiki_search_service/wiki_backend.dart';
import 'package:front_porch_ai/services/chat/wiki_search_service/wiki_http_client.dart';

/// Studio catalog. Chat `wiki_search` stays a 3-hit postcard.
class WikiStudioCatalog {
  const WikiStudioCatalog({
    required this.backend,
    required this.titles,
    this.skipped = 0,
    this.parsed = 0,
    this.tagsByTitle = const {},
    this.articleCount,
    this.ranked = false,
  });

  final WikiBackend backend;
  final List<String> titles;
  final int skipped;
  final int parsed;

  /// How many articles the wiki reports, when it says; null for Tiddly
  /// and for a wiki that would not answer.
  final int? articleCount;

  /// True when [titles] is the wiki's most-linked pages plus the premise
  /// search rather than a complete listing — a big wiki's index.
  final bool ranked;

  /// Slice 8 (design §9.1): the tag sets the scout must SEE — Tiddly
  /// tags or MediaWiki categories, keyed by the exact catalog title.
  /// Additive: an empty map means "no tag signal", and the wizard
  /// yields one flat world exactly as before.
  final Map<String, List<String>> tagsByTitle;
}

/// Studio catalog listing for a wiki base. The owning service resolves the
/// backend and hands in the cached tiddler index; HTTP calls are reported
/// back through [onHttpCall].
class WikiStudioLister {
  WikiStudioLister({required this.http, required this.onHttpCall});

  final WikiHttpClient http;
  final void Function() onHttpCall;

  /// Tiddly: index titles. MediaWiki: allpages (index analog), seed search
  /// as a fallback. Skips `$:/`, media, galleries. Cap is the catalog, not 3.
  Future<WikiStudioCatalog> listStudioTitles(
    Uri base,
    WikiBackend kind, {
    TiddlyIndex? tiddlyIndex,
    String? seedQuery,
  }) async {
    if (kind == WikiBackend.tiddly) {
      final index = tiddlyIndex;
      if (index == null) {
        return const WikiStudioCatalog(backend: WikiBackend.tiddly, titles: []);
      }
      final titles = <String>[];
      final tagsByTitle = <String, List<String>>{};
      var skipped = index.skippedSystem;
      for (final t in index.tiddlers) {
        if (skipWikiStudioTitle(t.title)) {
          skipped++;
          continue;
        }
        titles.add(t.title);
        if (t.tags.isNotEmpty) tagsByTitle[t.title] = t.tags;
        if (titles.length >= kWorldWikiCatalogCap) break;
      }
      return WikiStudioCatalog(
        backend: WikiBackend.tiddly,
        titles: titles,
        skipped: skipped,
        parsed: index.parsedCount,
        tagsByTitle: tagsByTitle,
      );
    }
    if (kind != WikiBackend.mediawiki) {
      return WikiStudioCatalog(backend: kind, titles: const []);
    }
    // A wiki bigger than the catalog cap cannot be listed whole: "all
    // pages" is alphabetical, so the cap would hold its A and B pages and
    // nothing else (Bleach: 3,005 articles, a shelf of Aaroniero, Arturo
    // and Askin). Its index is the pages the wiki links to most, with the
    // premise search in front, and their categories fetched by title.
    final articles = await _mediawikiArticleCount(base);
    if (articles != null && articles > kWorldWikiCatalogCap) {
      final ranked = await _mediawikiRanked(base, seedQuery);
      if (ranked.titles.isNotEmpty) {
        return WikiStudioCatalog(
          backend: WikiBackend.mediawiki,
          titles: ranked.titles,
          parsed: ranked.titles.length,
          tagsByTitle: ranked.tags,
          articleCount: articles,
          ranked: true,
        );
      }
    }
    // Slice 8: one generator round fetches titles AND categories; a
    // wiki that refuses it (old fork, error) falls back to the bare
    // allpages listing exactly as before — never a dead catalog.
    final tagged = await _mediawikiAllPagesTagged(base);
    if (tagged.titles.isNotEmpty) {
      return WikiStudioCatalog(
        backend: WikiBackend.mediawiki,
        titles: tagged.titles,
        parsed: tagged.titles.length,
        tagsByTitle: tagged.tags,
        articleCount: articles,
      );
    }
    final fromPages = await _mediawikiAllPages(base);
    if (fromPages.isNotEmpty) {
      return WikiStudioCatalog(
        backend: WikiBackend.mediawiki,
        titles: fromPages,
        parsed: fromPages.length,
        articleCount: articles,
      );
    }
    final seed = (seedQuery ?? '').trim();
    if (seed.isEmpty) {
      return const WikiStudioCatalog(
        backend: WikiBackend.mediawiki,
        titles: [],
      );
    }
    final searched = await _mediawikiStudioSearch(base, seed);
    return WikiStudioCatalog(
      backend: WikiBackend.mediawiki,
      titles: searched,
      parsed: searched.length,
    );
  }

  Future<int?> _mediawikiArticleCount(Uri wikiBase) async {
    onHttpCall();
    try {
      final resp = await http.get(
        mediawikiStatisticsUri(wikiBase),
        kind: 'search',
        cap: kMediaWikiMaxBodyBytes,
      );
      if (resp.statusCode != 200) return null;
      return parseMediaWikiArticleCount(resp.body);
    } catch (e) {
      debugPrint('[World] statistics miss/fail reason=$e');
      return null;
    }
  }

  /// Premise search hits first, then the most-linked articles, up to the
  /// cap; categories fetched for them [kCategoryBatch] titles at a time.
  Future<({List<String> titles, Map<String, List<String>> tags})>
  _mediawikiRanked(Uri wikiBase, String? seedQuery) async {
    final titles = <String>[];
    final seen = <String>{};
    void add(String t) {
      if (titles.length >= kWorldWikiCatalogCap) return;
      if (seen.add(t.toLowerCase())) titles.add(t);
    }

    final seed = (seedQuery ?? '').trim();
    if (seed.isNotEmpty) {
      for (final t in await _mediawikiStudioSearch(wikiBase, seed)) {
        add(t);
      }
    }
    onHttpCall();
    try {
      final resp = await http.get(
        mediawikiMostLinkedUri(wikiBase),
        kind: 'search',
        cap: kMediaWikiMaxBodyBytes,
      );
      if (resp.statusCode == 200 &&
          resp.bodyBytes.length <= kMediaWikiMaxBodyBytes) {
        for (final t in parseMediaWikiQueryPageTitles(resp.body)) {
          add(t);
        }
      }
    } catch (e) {
      debugPrint('[World] mostlinked miss/fail reason=$e');
    }
    final tags = <String, List<String>>{};
    for (var i = 0; i < titles.length; i += kCategoryBatch) {
      final batch = titles.sublist(
        i,
        (i + kCategoryBatch).clamp(0, titles.length),
      );
      onHttpCall();
      try {
        final resp = await http.get(
          mediawikiCategoriesForTitlesUri(wikiBase, batch),
          kind: 'search',
          cap: kMediaWikiMaxBodyBytes,
        );
        if (resp.statusCode != 200) continue;
        final parsed = parseMediaWikiPagesWithCategories(resp.body);
        for (final entry in parsed.categoriesByTitle.entries) {
          if (entry.value.isNotEmpty) tags[entry.key] = entry.value;
        }
      } catch (e) {
        debugPrint('[World] categories miss/fail reason=$e');
      }
    }
    return (titles: titles, tags: tags);
  }

  /// Titles per categories request: a wiki with many categories a page
  /// stays under the 500-category answer cap at this size.
  static const int kCategoryBatch = 25;

  Future<({List<String> titles, Map<String, List<String>> tags})>
  _mediawikiAllPagesTagged(Uri wikiBase) async {
    final titles = <String>[];
    final seen = <String>{};
    final tags = <String, List<String>>{};
    String? cont;
    for (var page = 0; page < 4; page++) {
      onHttpCall();
      final uri = mediawikiPagesWithCategoriesUri(wikiBase, gapcontinue: cont);
      try {
        final resp = await http.get(
          uri,
          kind: 'search',
          cap: kMediaWikiMaxBodyBytes,
        );
        if (resp.statusCode != 200) break;
        if (resp.bodyBytes.length > kMediaWikiMaxBodyBytes) break;
        final parsed = parseMediaWikiPagesWithCategories(resp.body);
        for (final entry in parsed.categoriesByTitle.entries) {
          if (!seen.add(entry.key.toLowerCase())) continue;
          titles.add(entry.key);
          if (entry.value.isNotEmpty) tags[entry.key] = entry.value;
          if (titles.length >= kWorldWikiCatalogCap) {
            return (titles: titles, tags: tags);
          }
        }
        cont = parsed.gapcontinue;
        if (cont == null || cont.isEmpty) break;
      } catch (e) {
        debugPrint('[World] allpages+categories miss/fail reason=$e');
        break;
      }
    }
    return (titles: titles, tags: tags);
  }

  Future<List<String>> _mediawikiAllPages(Uri wikiBase) async {
    final out = <String>[];
    final seen = <String>{};
    String? cont;
    for (var page = 0; page < 4; page++) {
      onHttpCall();
      final uri = mediawikiAllPagesUri(wikiBase, apcontinue: cont);
      try {
        final resp = await http.get(
          uri,
          kind: 'search',
          cap: kMediaWikiMaxBodyBytes,
        );
        if (resp.statusCode != 200) break;
        if (resp.bodyBytes.length > kMediaWikiMaxBodyBytes) break;
        final parsed = parseMediaWikiAllPages(resp.body);
        for (final t in parsed.titles) {
          if (!seen.add(t.toLowerCase())) continue;
          out.add(t);
          if (out.length >= kWorldWikiCatalogCap) return out;
        }
        cont = parsed.apcontinue;
        if (cont == null || cont.isEmpty) break;
      } catch (e) {
        debugPrint('[World] allpages miss/fail reason=$e');
        break;
      }
    }
    return out;
  }

  Future<List<String>> _mediawikiStudioSearch(
    Uri wikiBase,
    String query,
  ) async {
    onHttpCall();
    final uri = mediawikiStudioSearchUri(wikiBase, query);
    try {
      final resp = await http.get(
        uri,
        kind: 'search',
        cap: kMediaWikiMaxBodyBytes,
      );
      if (resp.statusCode != 200) return const [];
      if (resp.bodyBytes.length > kMediaWikiMaxBodyBytes) return const [];
      return [
        for (final t in parseMediaWikiSearchTitles(resp.body, maxTitles: 50))
          if (!skipWikiStudioTitle(t)) t,
      ];
    } catch (e) {
      debugPrint('[World] studio search miss/fail reason=$e');
      return const [];
    }
  }
}
