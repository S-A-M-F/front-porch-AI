// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { join } from 'node:path';
import { test, expect, openRoute } from './support/fixtures';

test('global prompt additions save, reload, and clear in Generation settings', async ({ page }) => {
  const original = await (await page.request.get('/api/settings')).json() as {
    additionalSystemPrompt?: string; additionalPostHistoryInstructions?: string;
  };
  const read = async () => (await (await page.request.get('/api/settings')).json()) as typeof original;
  try {
    await openRoute(page, '/settings');
    await page.getByText('Global prompt additions', { exact: true }).click();
    const system = page.getByRole('textbox', { name: 'Additional system instructions', exact: true });
    const post = page.getByRole('textbox', { name: 'Additional post-history instructions', exact: true });
    await system.fill('Use concise scene descriptions for {{char}}.');
    await post.fill('Keep each reply focused on one action.');
    await page.getByRole('button', { name: 'Save settings', exact: true }).click();
    await expect.poll(async () => (await read()).additionalSystemPrompt).toBe('Use concise scene descriptions for {{char}}.');
    await expect.poll(async () => (await read()).additionalPostHistoryInstructions).toBe('Keep each reply focused on one action.');
    await page.reload();
    await page.getByText('Global prompt additions', { exact: true }).click();
    await expect(system).toHaveValue('Use concise scene descriptions for {{char}}.');
    await expect(post).toHaveValue('Keep each reply focused on one action.');
    if (process.env.FPAI_REVIEW_ARTIFACT_DIR) {
      await system.scrollIntoViewIfNeeded();
      await page.screenshot({ path: join(process.env.FPAI_REVIEW_ARTIFACT_DIR,
        `global-prompt-additions-${test.info().project.name}.png`) });
    }
    await system.fill(''); await post.fill('');
    await page.getByRole('button', { name: 'Save settings', exact: true }).click();
    await expect.poll(async () => (await read()).additionalSystemPrompt).toBe('');
    await expect.poll(async () => (await read()).additionalPostHistoryInstructions).toBe('');
  } finally {
    expect((await page.request.post('/api/settings', { data: {
      additionalSystemPrompt: original.additionalSystemPrompt ?? '',
      additionalPostHistoryInstructions: original.additionalPostHistoryInstructions ?? '',
    }})).ok()).toBe(true);
  }
});
