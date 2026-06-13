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
import 'dart:math';

import 'package:front_porch_ai/models/story_project.dart' as story_model;

/// Small pure utilities extracted from web_server_service.dart during Stage 6
/// route handler extraction (per docs/refactoring-guide.md).
/// No service state; used by routes and helpers.
class RouteUtils {
  /// Generate a random 6-digit PIN (used for auto-PIN if none set).
  static String generatePin() {
    final rng = Random.secure();
    return (100000 + rng.nextInt(900000)).toString();
  }

  /// Generate a secure random session token (hex).
  static String generateSessionToken() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Extract basename from path (cross platform / \ ; matches FolderService).
  static String basename(String path) {
    final parts = path.split(RegExp(r'[/\\]'));
    return parts.last;
  }

  /// Parse User-Agent into human readable "Browser on OS (ip)".
  static String parseUserAgent(String ua, String? ip) {
    if (ua.isEmpty) return ip ?? 'Unknown';

    String browser;
    if (ua.contains('Edg/') || ua.contains('Edge/')) {
      browser = 'Edge';
    } else if (ua.contains('OPR/') || ua.contains('Opera')) {
      browser = 'Opera';
    } else if (ua.contains('Vivaldi/')) {
      browser = 'Vivaldi';
    } else if (ua.contains('Brave')) {
      browser = 'Brave';
    } else if (ua.contains('Firefox/')) {
      browser = 'Firefox';
    } else if (ua.contains('Chrome/') && ua.contains('Safari/')) {
      browser = 'Chrome';
    } else if (ua.contains('Safari/') && !ua.contains('Chrome/')) {
      browser = 'Safari';
    } else if (ua.contains('curl/')) {
      browser = 'curl';
    } else if (ua.contains('Postman')) {
      browser = 'Postman';
    } else {
      browser = 'Unknown';
    }

    String os;
    if (ua.contains('Windows')) {
      os = 'Windows';
    } else if (ua.contains('Mac OS X') || ua.contains('Macintosh')) {
      os = 'macOS';
    } else if (ua.contains('Android')) {
      os = 'Android';
    } else if (ua.contains('iPhone') ||
        ua.contains('iPad') ||
        ua.contains('iOS')) {
      os = 'iOS';
    } else if (ua.contains('Linux')) {
      os = 'Linux';
    } else if (ua.contains('CrOS')) {
      os = 'ChromeOS';
    } else {
      os = 'Unknown OS';
    }

    final ipPart = ip != null ? ' ($ip)' : '';
    return '$browser on $os$ipPart';
  }

  /// Try parse JSON list, return [] on failure (used for tags etc).
  static List<dynamic> tryParseJsonList(String jsonStr) {
    try {
      return jsonDecode(jsonStr) as List<dynamic>;
    } catch (_) {
      return [];
    }
  }

  /// Count words in a StoryProject's prose (draft + final).
  static int countWords(story_model.StoryProject p) {
    int count = 0;
    for (final bp in p.prose.values) {
      final text = bp.final_ ?? bp.draft ?? '';
      if (text.isNotEmpty) count += text.split(RegExp(r'\s+')).length;
    }
    return count;
  }
}
