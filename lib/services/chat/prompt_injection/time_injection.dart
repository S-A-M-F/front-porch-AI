// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:front_porch_ai/services/chat/time_service.dart';

/// Plain time injection builder (step 8).
/// Authoritative scene time text; god _getTimeInjection and time_service.build
/// are thin wrappers (per pre-step comments). State remains in TimeService.
class TimeInjection {
  final TimeService timeService;

  TimeInjection({required this.timeService});

  String buildTimeInjection() {
    if (timeService.timeOfDay.isEmpty) return '';
    final timeLabel = timeService.timeOfDay.replaceAll('_', ' ');
    final cap =
        timeLabel.substring(0, 1).toUpperCase() + timeLabel.substring(1);
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final narrativeDayIndex =
        (timeService.startDayOfWeekAnchor - 1 + (timeService.dayCount - 1)) % 7;
    final weekdayName = days[narrativeDayIndex];
    return '[Scene Time: $cap, $weekdayName (Day ${timeService.dayCount})\n'
        ' Describe appropriate lighting, atmosphere, and environmental details.]\n';
  }
}
