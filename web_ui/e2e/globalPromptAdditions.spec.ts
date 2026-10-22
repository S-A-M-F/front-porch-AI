// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { join } from 'node:path';
import { test, expect, openRoute } from './support/fixtures';

test('global prompt additions save, reload, and clear under General settings', async ({ page }) => {
  const original = await (await page.request.get('/api/settings')).json() as {
    additionalSystemPrompt?: string; additionalPostHistoryInstructions?: string;
  };
  const read = async () => (await (await page.request.get('/api/settings')).json()) as typeof original;
  try {
    await openRoute(page, '/settings');
    // Flat under the fallback prompt in General — no accordion to expand.
    const additions = page.locator(
      '[data-section="general"] [data-testid="global-prompt-additions"]',
    );
    await expect(additions).toBeVisible();
    const system = page.getByRole('textbox', { name: 'Additional system instructions', exact: true });
    const post = page.getByRole('textbox', { name: 'Additional post-history instructions', exact: true });
    await system.fill('Use concise scene descriptions for {{char}}.');
    await post.fill('Keep each reply focused on one action.');
    await page.getByRole('button', { name: 'Save settings', exact: true }).click();
    await expect.poll(async () => (await read()).additionalSystemPrompt).toBe('Use concise scene descriptions for {{char}}.');
    await expect.poll(async () => (await read()).additionalPostHistoryInstructions).toBe('Keep each reply focused on one action.');
    await page.reload();
    await expect(additions).toBeVisible();
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

test('the Group system prompt saves under General, resets to the built-in prompt, and clears', async ({ page }) => {
  const read = async () => (await (await page.request.get('/api/settings')).json()) as {
    groupSystemPrompt?: string; builtInGroupSystemPrompt?: string;
  };
  const original = await read();
  try {
    await openRoute(page, '/settings');
    const card = page.locator('[data-section="general"] [data-testid="group-system-prompt"]');
    await expect(card).toBeVisible();
    const field = page.getByRole('textbox', { name: 'Group system prompt', exact: true });
    await field.fill('Novel style for every group.');
    await page.getByRole('button', { name: 'Save settings', exact: true }).click();
    await expect.poll(async () => (await read()).groupSystemPrompt).toBe('Novel style for every group.');
    // "Start from the built-in prompt" became Reset to built-in: the box
    // shows the built-in, and it is stored blank so Director Mode keeps its
    // own built-in base.
    await card.getByRole('button', { name: 'Reset to built-in', exact: true }).click();
    const builtIn = (await read()).builtInGroupSystemPrompt;
    expect(builtIn).toBeTruthy();
    await expect(field).toHaveValue(builtIn ?? '');
    await page.getByRole('button', { name: 'Save settings', exact: true }).click();
    await expect.poll(async () => (await read()).groupSystemPrompt).toBe('');
    await field.fill('Novel style for every group.');
    await page.getByRole('button', { name: 'Save settings', exact: true }).click();
    await expect.poll(async () => (await read()).groupSystemPrompt).toBe('Novel style for every group.');
    await field.fill('');
    await page.getByRole('button', { name: 'Save settings', exact: true }).click();
    await expect.poll(async () => (await read()).groupSystemPrompt).toBe('');
  } finally {
    expect((await page.request.post('/api/settings', { data: {
      groupSystemPrompt: original.groupSystemPrompt ?? '',
    }})).ok()).toBe(true);
  }
});
