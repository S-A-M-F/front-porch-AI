// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useRef, useState } from 'react';
import { api } from '../api/client';
import { ChatSocket } from '../api/ws';

export function useEvaluationView() {
  const [minimized, setMinimized] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const owner = useRef<{ save: (value: boolean) => Promise<void> } | null>(null);
  useEffect(() => {
    let alive = true;
    let revision = 0;
    let writing = false;
    const read = async () => {
      const token = ++revision;
      try {
        const settings = await api.get<{ evaluationMinimized?: boolean }>('/api/settings');
        if (alive && token === revision && !writing) {
          setMinimized(settings.evaluationMinimized === true);
        }
      } catch (e) {
        if (alive) setError(`Could not load evaluation view: ${String(e)}`);
      }
    };
    owner.current = { save: async (value) => {
      if (writing) return;
      writing = true;
      ++revision;
      setSaving(true);
      setError('');
      try {
        await api.post('/api/settings', { evaluationMinimized: value });
        if (alive) setMinimized(value);
      } catch (e) {
        if (alive) setError(`Could not save evaluation view: ${String(e)}`);
      } finally {
        writing = false;
        if (alive) { setSaving(false); void read(); }
      }
    }};
    void read();
    const socket = new ChatSocket((event) => {
      if (event.event === 'settings_changed' || event.event === 'connected') void read();
    });
    socket.connect();
    return () => { alive = false; owner.current = null; socket.close(); };
  }, []);
  return { minimized, saving, error, change: (value: boolean) => { void owner.current?.save(value); } };
}
