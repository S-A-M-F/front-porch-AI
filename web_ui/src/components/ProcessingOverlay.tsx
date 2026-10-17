// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Realism / Objective "engine is thinking" overlay — the web mirror of the
// desktop realism_processing_overlay + objective_check_overlay. Shows the live
// eval stream while the Realism Engine evaluates, and a status panel while the
// Objective Engine checks task completion. Driven by the `processing` WS event.

import { useEffect, useRef, useState } from 'react';

export interface Processing {
  active: boolean;
  realism: boolean;
  objective: boolean;
  greeting: boolean;
  verifying: boolean;
  text: string;
}

export const NO_PROCESSING: Processing = {
  active: false,
  realism: false,
  objective: false,
  greeting: false,
  verifying: false,
  text: '',
};

function ActiveProcessingOverlay({
  p,
  onCancel,
  onSkipObjective,
  minimized = false,
  onMinimizedChange,
  saving = false,
}: {
  minimized?: boolean;
  onMinimizedChange?: (value: boolean) => void;
  saving?: boolean;
  p: Processing;
  onCancel: () => void;
  // Stops only the goal check; the reply still comes (desktop twin:
  // objective_check_overlay.dart).
  onSkipObjective: () => void;
}) {
  const [elapsed, setElapsed] = useState(0);
  useEffect(() => {
    if (!p.active) return;
    const start = Date.now();
    const timer = window.setInterval(() => setElapsed(Math.floor((Date.now() - start) / 1000)), 1000);
    return () => window.clearInterval(timer);
  }, [p.active]);
  const streamRef = useRef<HTMLPreElement>(null);
  // Keep the live stream scrolled to the newest text.
  useEffect(() => {
    if (streamRef.current) streamRef.current.scrollTop = streamRef.current.scrollHeight;
  }, [p.text, minimized]);


  const realismMode = p.realism;
  const title = p.greeting
    ? 'Reading the room…'
    : p.verifying
      ? '🕵️ Verifying Realism output'
      : realismMode
        ? 'Realism Engine'
        : 'Objective Engine';
  const subtitle = p.greeting
    ? 'Capturing emotional baseline from the opening message'
    : p.verifying
      ? 'Checking deltas & latent context; applying corrections as needed'
      : realismMode
        ? 'Evaluating relationship, mood & scene state'
        : 'Evaluating objective & task completion';
  const stages = realismMode
    ? [...(p.objective ? ['Objective'] : []), 'Relationship', 'Emotion', 'Scene', 'Trust']
    : ['Objective', 'Progress', 'Completion'];

  return (
    <div className={`proc-overlay${minimized ? " proc-minimized" : ""}`} role="status" aria-live="polite">
      <div className="proc-card">
        <div className="proc-head">
          <span className="proc-spinner" aria-hidden />
          <div className="proc-headtext">
            <div className="proc-title">{title}</div>
            <div className="proc-sub muted small">{subtitle}</div>
          </div>
        </div>

        <div className="proc-progress-controls">
          {elapsed >= 30 && <span className="muted small" aria-hidden="true" aria-live="off">{elapsed}s elapsed</span>}
          <button type="button" aria-expanded={!minimized} disabled={saving} onClick={() => onMinimizedChange?.(!minimized)}>
            {minimized ? 'Show evaluation details' : 'Minimize evaluation'}
          </button>
        </div>
        {!minimized && (<>
          <div className="proc-stages">
            {stages.map((s) => (
              <span key={s} className="proc-pill">{s}</span>
            ))}
          </div>

          {realismMode && p.text ? (
            <div className="proc-stream">
              <div className="proc-stream-head"><span className="proc-dot" aria-hidden /> LIVE EVAL STREAM</div>
              <pre className="proc-stream-body" ref={streamRef}>{p.text}</pre>
            </div>
          ) : !realismMode ? (
            <p className="muted small proc-objtext">
              Reviewing recent conversation to determine if objectives or tasks have been fulfilled…
            </p>
          ) : null}

        </>)}
        {(realismMode || p.greeting) && (
          <button type="button" className="proc-cancel" onClick={onCancel}>Stop this reply</button>
        )}
        {!realismMode && !p.greeting && !p.verifying && p.objective && (
          <button type="button" className="proc-skip" onClick={onSkipObjective}>Skip goal check</button>
        )}
      </div>
    </div>
  );
}

export function ProcessingOverlay(props: {
  minimized?: boolean;
  onMinimizedChange?: (value: boolean) => void;
  saving?: boolean;
  p: Processing;
  onCancel: () => void;
  onSkipObjective: () => void;
}) {
  return props.p.active ? <ActiveProcessingOverlay {...props} /> : null;
}
