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

/// `meta=siteinfo&siprop=statistics`: how many articles the wiki has, so
/// the catalog knows whether "all pages" can list them whole.
Uri mediawikiStatisticsUri(Uri wikiBase) {
  return mediawikiActionApiUri(wikiBase).replace(
    queryParameters: {
      'action': 'query',
      'meta': 'siteinfo',
      'siprop': 'statistics',
      'format': 'json',
    },
  );
}

int? parseMediaWikiArticleCount(String body) {
  try {
    final dynamic json = jsonDecode(body);
    if (json is! Map) return null;
    final query = json['query'];
    if (query is! Map) return null;
    final stats = query['statistics'];
    if (stats is! Map) return null;
    final raw = stats['articles'];
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '');
  } catch (_) {
    return null;
  }
}

/// Special:MostLinkedPages through the API: the articles other pages
/// point at most, which on a big wiki is its cast, its places and its
/// terms in importance order — the opposite of an alphabetical prefix.
Uri mediawikiMostLinkedUri(Uri wikiBase) {
  return mediawikiActionApiUri(wikiBase).replace(
    queryParameters: {
      'action': 'query',
      'list': 'querypage',
      'qppage': 'Mostlinked',
      'qplimit': 'max',
      'format': 'json',
    },
  );
}

/// Article-namespace titles from a querypage answer, in rank order.
List<String> parseMediaWikiQueryPageTitles(String body) {
  final out = <String>[];
  try {
    final dynamic json = jsonDecode(body);
    if (json is! Map) return out;
    final query = json['query'];
    if (query is! Map) return out;
    final page = query['querypage'];
    if (page is! Map) return out;
    final results = page['results'];
    if (results is! List) return out;
    for (final r in results) {
      if (r is! Map) continue;
      final ns = r['ns'];
      if (ns != 0 && ns != '0') continue;
      final title = r['title']?.toString().trim() ?? '';
      if (title.isEmpty || skipWikiStudioTitle(title)) continue;
      out.add(title);
    }
  } catch (_) {}
  return out;
}

/// Categories for a named batch of titles (`prop=categories&titles=`);
/// hidden maintenance categories are left out. The answer has the same
/// `query.pages` shape as the generator form, so one parser reads both.
Uri mediawikiCategoriesForTitlesUri(Uri wikiBase, List<String> titles) {
  return mediawikiActionApiUri(wikiBase).replace(
    queryParameters: {
      'action': 'query',
      'prop': 'categories',
      'clshow': '!hidden',
      'cllimit': 'max',
      'titles': titles.join('|'),
      'format': 'json',
    },
  );
}
