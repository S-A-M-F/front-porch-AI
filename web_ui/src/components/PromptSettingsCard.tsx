// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The prompt family for web Settings, mirroring the desktop General tab:
// the Fallback system prompt box with the Global prompt additions flat
// under it (prompt-picker SOW Phase 2 — one prompt family, one place),
// then the Group system prompt every group chat uses.

export function PromptSettingsCard({
  systemPrompt,
  additionalSystemPrompt,
  additionalPostHistoryInstructions,
  groupSystemPrompt,
  builtInGroupSystemPrompt,
  patch,
}: {
  systemPrompt?: string;
  additionalSystemPrompt?: string;
  additionalPostHistoryInstructions?: string;
  groupSystemPrompt?: string;
  builtInGroupSystemPrompt?: string;
  patch: (p: Record<string, unknown>) => void;
}) {
  if (systemPrompt === undefined) return null;
  return (
    <section className="card" data-testid="prompt-settings-card">
      <h3>Fallback system prompt</h3>
      <p className="muted small">Used in one-to-one chats whose character card has no system prompt of its own. Group chats use the Group system prompt further down instead.</p>
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
      <div className="prompt-additions" data-testid="group-system-prompt">
        <h4>Group system prompt</h4>
        <p className="muted small">Used in every group chat, unless that group has its own prompt in Group Settings. Leave blank for the built-in group prompt. Director Mode adds its own rules on top either way.</p>
        <label>Group system prompt
          <textarea rows={5} value={groupSystemPrompt ?? ''}
            placeholder="Blank uses the built-in group prompt"
            onChange={(e) => patch({ groupSystemPrompt: e.target.value })} />
        </label>
        {builtInGroupSystemPrompt && (
          <button type="button" className="ghost"
            onClick={() => patch({ groupSystemPrompt: builtInGroupSystemPrompt })}>
            Start from the built-in prompt
          </button>
        )}
      </div>
    </section>
  );
}
