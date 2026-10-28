// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// One card of the Book step: an icon badge, a title, "n of 4" on the
/// right, and the card's content below. The theme's own colours.
class WorldSectionCard extends StatelessWidget {
  const WorldSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.step,
    required this.of,
    required this.child,
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final int step;
  final int of;
  final Widget child;

  /// An amber edge, for the card a run is about to use.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final amber = StudioColors.amberOf(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: StudioColors.cardOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlighted ? amber : StudioColors.lineOf(context),
          width: highlighted ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              WorldIconBadge(icon: icon),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: StudioColors.inkOf(context),
                ),
              ),
              const Spacer(),
              Text(
                '$step of $of',
                style: TextStyle(
                  fontSize: 12,
                  color: StudioColors.mutedOf(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// A small amber-tinted square with an icon, the wizard's section mark.
class WorldIconBadge extends StatelessWidget {
  const WorldIconBadge({super.key, required this.icon, this.size = 30});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final amber = StudioColors.amberOf(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.27),
      ),
      child: Icon(icon, size: size * 0.55, color: amber),
    );
  }
}

/// A small outlined chip of muted text: "optional", "14 cards", a kind.
class WorldChip extends StatelessWidget {
  const WorldChip(this.text, {super.key, this.accent = false});

  final String text;

  /// Amber text on an amber wash, for the one that matters.
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final amber = StudioColors.amberOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent
            ? amber.withValues(alpha: 0.14)
            : StudioColors.raiseOf(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: accent ? Colors.transparent : StudioColors.lineOf(context),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: accent ? amber : StudioColors.proseOf(context),
        ),
      ),
    );
  }
}

/// A selectable tile: the wiki, the depth. Amber edge and wash when on.
class WorldPickTile extends StatelessWidget {
  const WorldPickTile({
    super.key,
    required this.selected,
    required this.onTap,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final bool selected;
  final VoidCallback? onTap;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final amber = StudioColors.amberOf(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: selected
                ? amber.withValues(alpha: 0.08)
                : StudioColors.bgOf(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? amber : StudioColors.lineOf(context),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A pill in a row of choices: the context sizes.
class WorldPill extends StatelessWidget {
  const WorldPill({
    super.key,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final String text;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final amber = StudioColors.amberOf(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? amber.withValues(alpha: 0.1) : null,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? amber : StudioColors.lineOf(context),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              color: selected
                  ? StudioColors.inkOf(context)
                  : StudioColors.proseOf(context),
            ),
          ),
        ),
      ),
    );
  }
}
