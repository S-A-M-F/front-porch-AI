// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The prompt family for web Settings, mirroring the desktop General tab:
// the Fallback system prompt box with the Global prompt additions flat
// under it (prompt-picker SOW Phase 2 — one prompt family, one place).

export function PromptSettingsCard({
  systemPrompt,
  additionalSystemPrompt,
  additionalPostHistoryInstructions,
  patch,
}: {
  systemPrompt?: string;
  additionalSystemPrompt?: string;
  additionalPostHistoryInstructions?: string;
  patch: (p: Record<string, unknown>) => void;
}) {
  if (systemPrompt === undefined) return null;
  return (
    <section className="card" data-testid="prompt-settings-card">
      <h3>Fallback system prompt</h3>
      <p className="muted small">Used in one-to-one chats when the character has no system prompt. Groups use their own prompt or a group default.</p>
      <label data-testid="fallback-system-prompt">
        Fallback system prompt
        <textarea
          rows={6}
          value={systemPrompt}
          onChange={(e) => patch({ systemPrompt: e.target.value })}
        />
      </label>
      {additionalSystemPrompt !== undefined &&
        additionalPostHistoryInstructions !== undefined && (
          <div className="prompt-additions" data-testid="global-prompt-additions">
            <h4>Global prompt additions</h4>
            <p className="muted small">Extra instructions for every character and chat model. Leave blank to disable. Both fields support {'{{char}}'} and {'{{user}}'}. Use Save settings to apply changes.</p>
            <label>Additional system instructions
              <textarea rows={4} value={additionalSystemPrompt}
                onChange={(e) => patch({ additionalSystemPrompt: e.target.value })} />
            </label>
            <p className="muted small">Appended to the selected system prompt, including character and group prompts.</p>
            <label>Additional post-history instructions
              <textarea rows={4} value={additionalPostHistoryInstructions}
                onChange={(e) => patch({ additionalPostHistoryInstructions: e.target.value })} />
            </label>
            <p className="muted small">Appended after existing post-history instructions.</p>
          </div>
        )}
    </section>
  );
}
