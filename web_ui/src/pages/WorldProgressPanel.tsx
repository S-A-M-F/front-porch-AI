// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import type { WorldProgressLine } from './worldFromWiki';

/** How many earlier lines the panel shows under the current one. */
export const WORLD_PROGRESS_SHOWN = 6;

/**
 * The wizard's progress while the host scouts or writes: the line for what
 * it is doing now, the time the run has taken, and the lines before it. The
 * desktop twin is WorldProgressPanel in the Flutter wizard.
 */
export function WorldProgressPanel({
  status,
  fallback,
  log,
  elapsed,
}: {
  status: string;
  fallback: string;
  log: WorldProgressLine[];
  elapsed: string;
}) {
  const earlier = log.slice(0, -1).reverse().slice(0, WORLD_PROGRESS_SHOWN);
  return (
    <div className="world-progress" data-testid="world-from-wiki-progress">
      <p className="world-progress-now">
        <span className="world-progress-spin" aria-hidden="true" />
        <span className="world-progress-text">{status || fallback}</span>
        <span className="muted small world-progress-elapsed">{elapsed}</span>
      </p>
      {earlier.length > 0 && (
        <ul className="world-progress-log muted small">
          {earlier.map((line, i) => (
            <li key={`${line.at}-${i}`}>
              <span className="world-progress-at">{line.at}</span> {line.text}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
