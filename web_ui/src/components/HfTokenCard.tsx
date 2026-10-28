// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → Backend: the optional HuggingFace token the host's model
// downloader sends to HuggingFace so gated repos list and download. Same
// control as the desktop Backend tab. The token is never read back; saving
// one needs the web login password (and 2FA code), clearing it does not.

import { useEffect, useState } from 'react';
import { api, ApiError } from '../api/client';
import { StepUpFields, attachStepUp } from './StepUpFields';

export function HfTokenCard({ hasToken, totpEnabled }: { hasToken: boolean; totpEnabled: boolean }) {
  const [value, setValue] = useState('');
  const [saved, setSaved] = useState(hasToken);
  const [password, setPassword] = useState('');
  const [totp, setTotp] = useState('');
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');
  useEffect(() => setSaved(hasToken), [hasToken]);

  const post = async (body: Record<string, unknown>, done: string, nowSaved: boolean) => {
    setBusy(true);
    setError('');
    setMessage('');
    try {
      await api.post('/api/settings', body);
      setValue('');
      setPassword('');
      setTotp('');
      setSaved(nowSaved);
      setMessage(done);
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Could not save the token');
    } finally {
      setBusy(false);
    }
  };

  const save = () => {
    const token = value.trim();
    if (!token || busy) return;
    const body: Record<string, unknown> = { hfToken: token };
    attachStepUp(body, password, totpEnabled, totp);
    void post(body, 'HuggingFace token saved.', true);
  };

  return (
    <section className="card" data-testid="hf-token-card">
      <h3>HuggingFace token</h3>
      <p className="muted small">
        Optional. Gated repos (official Llama and Gemma, some tunes) only list and download with a token. Create a
        read-only one under Settings → Access Tokens on huggingface.co, and accept the repo&apos;s licence there first.
      </p>
      <label>
        Token
        <input
          type="password"
          autoComplete="off"
          placeholder={saved ? '•••••• saved (paste to replace)' : 'hf_…'}
          value={value}
          onChange={(e) => setValue(e.target.value)}
        />
      </label>
      {value.trim() && (
        <StepUpFields
          password={password}
          onPassword={setPassword}
          totpEnabled={totpEnabled}
          totpCode={totp}
          onTotp={setTotp}
          reason="Saving a token lets this computer reach gated repos as you, so it needs your web login password."
        />
      )}
      <div className="tool-row">
        <button className="primary" disabled={busy || !value.trim()} onClick={save}>
          Save token
        </button>
        {saved && (
          <button
            className="ghost"
            disabled={busy}
            onClick={() => void post({ hfTokenClear: true }, 'HuggingFace token removed.', false)}
          >
            Clear token
          </button>
        )}
      </div>
      {message && <p className="muted small">{message}</p>}
      {error && <p className="error small">{error}</p>}
    </section>
  );
}
