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

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Basic sidebar section (extracted).
class SidebarSection extends StatefulWidget {
  final String title;
  final String content;
  const SidebarSection({required this.title, required this.content});

  @override
  State<SidebarSection> createState() => _SidebarSectionState();
}

class _SidebarSectionState extends State<SidebarSection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              children: [
                Icon(
                  _expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 16,
                  color: AppColors.iconSecondary(context),
                ),
                const SizedBox(width: 4),
                Text(
                  widget.title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 20.0),
            child: Text(
              widget.content,
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A generic collapsible sidebar section with icon, colored title, trailing badge, and arbitrary child.
class CollapsibleSidebarSection extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget? trailing;
  final Widget child;
  final bool initiallyExpanded;

  const CollapsibleSidebarSection({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
    this.trailing,
    this.initiallyExpanded = false,
  });

  @override
  State<CollapsibleSidebarSection> createState() =>
      _CollapsibleSidebarSectionState();
}

class _CollapsibleSidebarSectionState extends State<CollapsibleSidebarSection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              children: [
                Icon(widget.icon, size: 16, color: widget.iconColor),
                const SizedBox(width: 6),
                Text(
                  widget.title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: widget.iconColor,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                if (widget.trailing != null) widget.trailing!,
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: widget.child,
          ),
        ],
      ],
    );
  }
}
