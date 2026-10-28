// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { worldElapsedLabel, type WorldProgressLine } from './worldFromWiki';

/** A step waited on this long shows its own timer beside the total. */
export const WORLD_PROGRESS_STEP_TIMER_AFTER_MS = 15_000;

/**
 * The wizard's progress while the host scouts, writes or reviews: one amber
 * card with the spinner, the line for what it is doing now, the run's total
 * time and, once a step has been waited on a while, that step's own timer;
 * a slow sweep bar; the stages as chips with the current one lit; and Stop.
 * No history under it (the maintainer's ask). The desktop twin is
 * WorldProgressPanel in the Flutter wizard.
 */
export function WorldProgressPanel({
  status,
  fallback,
  elapsed,
  stepMs = 0,
  subtitle = '',
  stages = [],
  stage = 0,
  onStop,
}: {
  status: string;
  fallback: string;
  log?: WorldProgressLine[];
  elapsed: string;
  /** How long the current line has been waited on. */
  stepMs?: number;
  subtitle?: string;
  stages?: string[];
  stage?: number;
  onStop?: () => void;
}) {
  const stepLabel = stepMs >= WORLD_PROGRESS_STEP_TIMER_AFTER_MS ? worldElapsedLabel(stepMs) : '';
  return (
    <div className="world-progress" data-testid="world-from-wiki-progress">
      <div className="world-progress-now">
        <span className="world-progress-spin" aria-hidden="true" />
        <div className="world-progress-text">
          <strong>{status || fallback}</strong>
          {subtitle && <span className="muted small">{subtitle}</span>}
        </div>
        <div className="world-progress-times">
          <span className="world-progress-elapsed">{elapsed}</span>
          {stepLabel && (
            <span className="muted small world-progress-step" data-testid="world-from-wiki-step-elapsed">
              {stepLabel} on this step
            </span>
          )}
        </div>
      </div>
      <div className="world-progress-bar" aria-hidden="true">
        <span />
      </div>
      {(stages.length > 0 || onStop) && (
        <div className="world-progress-stages">
          {stages.map((s, i) => (
            <span key={s} className={`world-progress-stage${i === stage ? ' lit' : ''}`} data-testid={`world-from-wiki-stage-${i}`}>
              {i + 1} · {s}
            </span>
          ))}
          <span className="world-progress-grow" />
          {onStop && (
            <button type="button" className="world-progress-stop" onClick={onStop}>
              Stop
            </button>
          )}
        </div>
      )}
    </div>
  );
}
