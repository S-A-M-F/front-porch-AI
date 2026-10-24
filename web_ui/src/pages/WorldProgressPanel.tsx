// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { worldElapsedLabel, type WorldProgressLine } from './worldFromWiki';

/** A step waited on this long shows its own timer beside the total. */
export const WORLD_PROGRESS_STEP_TIMER_AFTER_MS = 15_000;

/**
 * The wizard's progress while the host scouts or writes: the line for what
 * it is doing now, the time the run has taken, and how long this step has
 * been waited on. No history under it (the maintainer's ask). The desktop
 * twin is WorldProgressPanel in the Flutter wizard.
 */
export function WorldProgressPanel({
  status,
  fallback,
  elapsed,
  stepMs = 0,
}: {
  status: string;
  fallback: string;
  log?: WorldProgressLine[];
  elapsed: string;
  /** How long the current line has been waited on. */
  stepMs?: number;
}) {
  const stepLabel = stepMs >= WORLD_PROGRESS_STEP_TIMER_AFTER_MS ? worldElapsedLabel(stepMs) : '';
  return (
    <div className="world-progress" data-testid="world-from-wiki-progress">
      <p className="world-progress-now">
        <span className="world-progress-spin" aria-hidden="true" />
        <span className="world-progress-text">{status || fallback}</span>
        <span className="muted small world-progress-elapsed">{elapsed}</span>
      </p>
      {stepLabel && (
        <p className="muted small world-progress-step" data-testid="world-from-wiki-step-elapsed">
          {stepLabel} on this step
        </p>
      )}
    </div>
  );
}
