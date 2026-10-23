// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Self-hosted MediaWiki under a non-root path must still hit the Action API.
// Proven: /w/ used to miss both Tiddly and the root-only MW fallback.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/chat/chat.dart';

void main() {
  test('path-hosted MediaWiki uses /w/api.php, not origin only', () {
    final base = parseWikiBaseUrl('https://wiki.example.com/w/')!;
    expect(base.path, '/w/');
    expect(mediawikiActionApiUri(base).path, '/w/api.php');
    expect(mediawikiSearchUri(base, 'Aizen').path, '/w/api.php');
  });

  test('self-hosted MediaWiki under /w/ still lists pages', () async {
    final fetched = <Uri>[];
    final wiki = WikiSearchService(
      getBaseUrl: () => 'https://wiki.example.com/w/',
      sendRequest: (request) async {
        fetched.add(request.url);
        if (request.url.path == '/w/api.php') {
          final action = request.url.queryParameters['action'];
          final list = request.url.queryParameters['list'];
          final meta = request.url.queryParameters['meta'];
          if (action == 'query' && meta == 'siteinfo') {
            return http.Response(
              jsonEncode({
                'query': {
                  'general': {'sitename': 'Path Wiki'},
                },
              }),
              200,
            );
          }
          if (action == 'query' && list == 'allpages') {
            return http.Response(
              jsonEncode({
                'query': {
                  'allpages': [
                    {'title': 'Sosuke Aizen'},
                  ],
                },
              }),
              200,
            );
          }
        }
        if (request.url.path.endsWith('api.php')) {
          return http.Response('nope', 404);
        }
        return http.Response(
          '<html><body>not a tiddler store</body></html>',
          200,
        );
      },
    );
    final catalog = await wiki.listStudioTitles();
    expect(catalog.backend, WikiBackend.mediawiki);
    expect(catalog.titles, contains('Sosuke Aizen'));
    expect(fetched.any((u) => u.path == '/w/api.php'), isTrue);
    expect(
      fetched.where((u) => u.path == '/api.php'),
      isEmpty,
      reason: 'path-hosted MW must not only probe origin /api.php',
    );
  });

  test(
    'MediaWiki categories reach the catalog as tags (pages is a map)',
    () async {
      // The real Action API answers `generator=allpages&prop=categories`
      // with `query.pages` keyed by page id (formatversion 1); only
      // `formatversion=2` makes it a list. Captured from yugioh.fandom.com.
      const generatorBody = {
        'batchcomplete': '',
        'query': {
          'pages': {
            '30438': {
              'pageid': 30438,
              'ns': 0,
              'title': 'Reustran Empire',
              'categories': [
                {'ns': 14, 'title': 'Category:Nations'},
                {'ns': 14, 'title': 'Category:Northern Reach'},
              ],
            },
            '48321': {'pageid': 48321, 'ns': 0, 'title': 'Untagged Page'},
          },
        },
      };
      const listBody = {
        'batchcomplete': true,
        'query': {
          'pages': [
            {
              'pageid': 7,
              'ns': 0,
              'title': 'Salt Garden',
              'categories': [
                {'ns': 14, 'title': 'Category:Places'},
              ],
            },
          ],
        },
      };
      final mapShape = parseMediaWikiPagesWithCategories(
        jsonEncode(generatorBody),
      );
      expect(mapShape.categoriesByTitle.keys, [
        'Reustran Empire',
        'Untagged Page',
      ]);
      expect(mapShape.categoriesByTitle['Reustran Empire'], [
        'Nations',
        'Northern Reach',
      ]);
      expect(mapShape.categoriesByTitle['Untagged Page'], isEmpty);
      final listShape = parseMediaWikiPagesWithCategories(jsonEncode(listBody));
      expect(listShape.categoriesByTitle['Salt Garden'], ['Places']);

      final wiki = WikiSearchService(
        getBaseUrl: () => 'https://wiki.example.com/w/',
        sendRequest: (request) async {
          if (request.url.path == '/w/api.php') {
            final q = request.url.queryParameters;
            if (q['action'] == 'query' && q['meta'] == 'siteinfo') {
              return http.Response(
                jsonEncode({
                  'query': {
                    'general': {'sitename': 'Tagged Wiki'},
                  },
                }),
                200,
              );
            }
            if (q['action'] == 'query' && q['generator'] == 'allpages') {
              return http.Response(jsonEncode(generatorBody), 200);
            }
            if (q['action'] == 'query' && q['list'] == 'allpages') {
              fail(
                'the tagged generator answered; the bare fallback must not run',
              );
            }
          }
          return http.Response(
            '<html><body>not a tiddler store</body></html>',
            200,
          );
        },
      );
      final catalog = await wiki.listStudioTitles();
      expect(catalog.backend, WikiBackend.mediawiki);
      expect(catalog.titles, containsAll(['Reustran Empire', 'Untagged Page']));
      expect(catalog.tagsByTitle['Reustran Empire'], [
        'Nations',
        'Northern Reach',
      ], reason: 'the scout only sees places through tagsByTitle');
      expect(catalog.tagsByTitle.containsKey('Untagged Page'), isFalse);
    },
  );

  group('a big wiki is cataloged by importance, not alphabet', () {
    const statsBig = {
      'query': {
        'statistics': {'articles': 3005},
      },
    };
    const mostLinked = {
      'query': {
        'querypage': {
          'name': 'Mostlinked',
          'results': [
            {'ns': 0, 'title': 'Ichigo Kurosaki', 'value': '2861'},
            {'ns': 10, 'title': 'Template:Infobox', 'value': '2000'},
            {'ns': 0, 'title': 'Soul Society', 'value': '900'},
            {'ns': 0, 'title': 'Image Gallery', 'value': '500'},
            {'ns': 0, 'title': 'Gotei 13', 'value': '400'},
          ],
        },
      },
    };
    const search = {
      'query': {
        'search': [
          {'title': 'Hollow'},
          {'title': 'Soul Society'},
        ],
      },
    };
    const cats = {
      'query': {
        'pages': {
          '1': {
            'title': 'Ichigo Kurosaki',
            'categories': [
              {'title': 'Category:Characters'},
              {'title': 'Category:Kurosaki Family'},
            ],
          },
          '2': {
            'title': 'Soul Society',
            'categories': [
              {'title': 'Category:Locations'},
            ],
          },
          '3': {'title': 'Hollow'},
        },
      },
    };

    WikiSearchService wikiWith({
      required Map<String, dynamic> stats,
      required List<String> log,
    }) {
      return WikiSearchService(
        getBaseUrl: () => 'https://bleach.example.com',
        sendRequest: (request) async {
          final q = request.url.queryParameters;
          if (request.url.path == '/api.php') {
            if (q['meta'] == 'siteinfo' && q['siprop'] == 'statistics') {
              log.add('statistics');
              return http.Response(jsonEncode(stats), 200);
            }
            if (q['meta'] == 'siteinfo') {
              return http.Response(
                jsonEncode({
                  'query': {
                    'general': {'sitename': 'Big Wiki'},
                  },
                }),
                200,
              );
            }
            if (q['list'] == 'querypage') {
              log.add('mostlinked');
              return http.Response(jsonEncode(mostLinked), 200);
            }
            if (q['list'] == 'search') {
              log.add('search:${q['srsearch']}');
              return http.Response(jsonEncode(search), 200);
            }
            if (q['prop'] == 'categories' && q['titles'] != null) {
              log.add('categories:${q['titles']}');
              return http.Response(jsonEncode(cats), 200);
            }
            if (q['generator'] == 'allpages') {
              log.add('allpages+categories');
              return http.Response(
                jsonEncode({
                  'query': {
                    'pages': {
                      '9': {
                        'title': 'Aaroniero Arruruerie',
                        'categories': [
                          {'title': 'Category:Arrancar'},
                        ],
                      },
                    },
                  },
                }),
                200,
              );
            }
          }
          return http.Response('<html>not a tiddler store</html>', 200);
        },
      );
    }

    test('3,005 articles: premise search first, then most-linked, with '
        'categories by title; the alphabet is never asked', () async {
      final log = <String>[];
      final catalog = await wikiWith(
        stats: statsBig,
        log: log,
      ).listStudioTitles(seedQuery: 'Soul Society Hollows');
      expect(catalog.backend, WikiBackend.mediawiki);
      expect(catalog.ranked, isTrue);
      expect(catalog.articleCount, 3005);
      expect(
        catalog.titles,
        ['Hollow', 'Soul Society', 'Ichigo Kurosaki', 'Gotei 13'],
        reason:
            'search hits lead, ranked pages follow, templates and galleries drop, no repeats',
      );
      expect(catalog.tagsByTitle['Ichigo Kurosaki'], [
        'Characters',
        'Kurosaki Family',
      ]);
      expect(catalog.tagsByTitle['Soul Society'], ['Locations']);
      expect(catalog.tagsByTitle.containsKey('Hollow'), isFalse);
      expect(log, contains('statistics'));
      expect(log, contains('search:Soul Society Hollows'));
      expect(log, contains('mostlinked'));
      expect(log.where((l) => l.startsWith('categories:')), hasLength(1));
      expect(log, isNot(contains('allpages+categories')));
    });

    test('120 articles: the complete listing, as before', () async {
      final log = <String>[];
      final catalog = await wikiWith(
        stats: const {
          'query': {
            'statistics': {'articles': 120},
          },
        },
        log: log,
      ).listStudioTitles(seedQuery: 'anything');
      expect(catalog.ranked, isFalse);
      expect(catalog.articleCount, 120);
      expect(catalog.titles, ['Aaroniero Arruruerie']);
      expect(catalog.tagsByTitle['Aaroniero Arruruerie'], ['Arrancar']);
      expect(log, isNot(contains('mostlinked')));
    });
  });
}
