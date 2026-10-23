// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Slice 8 (design §9.1): MediaWiki page CATEGORIES, the twin of the
// Tiddly `tags` field. The generator form of allpages fetches titles and
// their categories in one round trip, so the studio catalog can show the
// scout which pages belong to which nation/faction instead of a bare
// title list. Split from mediawiki_search.dart, which is already close to
// the 500-line bar.

import 'dart:convert';

import 'mediawiki_search.dart';

Uri mediawikiPagesWithCategoriesUri(Uri wikiBase, {String? gapcontinue}) {
  return mediawikiActionApiUri(wikiBase).replace(
    queryParameters: {
      'action': 'query',
      'generator': 'allpages',
      'gapnamespace': '0',
      'gaplimit': '500',
      'gapfilterredir': 'nonredirects',
      'prop': 'categories',
      'cllimit': 'max',
      'format': 'json',
      if (gapcontinue != null && gapcontinue.isNotEmpty)
        'gapcontinue': gapcontinue,
    },
  );
}

/// Titles + per-title category names from one generator response. Pages
/// the API returns without a `categories` array simply get no entry —
/// an untagged wiki still yields its titles, and the wizard stays flat.
///
/// `query.pages` is a map keyed by page id unless the request asked for
/// `formatversion=2`, which makes it a list. Fandom and Wikipedia answer
/// this request with the map (verified live against yugioh.fandom.com);
/// reading only the list shape left every MediaWiki catalog untagged.
({Map<String, List<String>> categoriesByTitle, String? gapcontinue})
parseMediaWikiPagesWithCategories(String body) {
  final out = <String, List<String>>{};
  try {
    final dynamic json = jsonDecode(body);
    if (json is! Map) return (categoriesByTitle: out, gapcontinue: null);
    final query = json['query'];
    if (query is Map) {
      final raw = query['pages'];
      final pages = raw is List
          ? raw
          : raw is Map
          ? raw.values.toList()
          : const <dynamic>[];
      for (final page in pages) {
        if (page is! Map) continue;
        final title = page['title']?.toString().trim() ?? '';
        if (title.isEmpty || skipWikiStudioTitle(title)) continue;
        // The title is kept even with no categories so callers can
        // count it; only non-empty lists land in the map.
        out.putIfAbsent(title, () => const []);
        final cats = page['categories'];
        if (cats is List && cats.isNotEmpty) {
          out[title] = [
            for (final c in cats)
              if (c is Map)
                stripMediaWikiCategoryNamespace(c['title']?.toString() ?? ''),
          ];
        }
      }
    }
    final cont = json['continue'];
    return (
      categoriesByTitle: out,
      gapcontinue: cont is Map ? cont['gapcontinue']?.toString() : null,
    );
  } catch (_) {
    return (categoriesByTitle: out, gapcontinue: null);
  }
}

/// `Category:Reustran Empire` -> `Reustran Empire`; the scout reads
/// subjects, not namespace plumbing.
String stripMediaWikiCategoryNamespace(String title) {
  const ns = 'Category:';
  return title.startsWith(ns) ? title.substring(ns.length).trim() : title;
}
