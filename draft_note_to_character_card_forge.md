Subject / Message for the Character Card Forge dev (v30 group realism changes):

---

Hey,

Front Porch just landed a significant but localized schema change in v30 that affects **group chats** (and by extension Group Cards). You have full visibility and this note exists so Character Card Forge can stay compatible.

### What changed (schema v30)

Two new TEXT columns were added (both `NOT NULL DEFAULT '{}'`):

1. `groups.default_member_realism_state`  
   Portable per-character realism + needs defaults for the *group definition*.

2. `sessions.group_realism_state`  
   Live per-character realism + needs state for a *specific group chat session*.

The migration (safe, idempotent):
```sql
ALTER TABLE groups   ADD COLUMN default_member_realism_state TEXT NOT NULL DEFAULT '{}';
ALTER TABLE sessions ADD COLUMN group_realism_state        TEXT NOT NULL DEFAULT '{}';
```

These columns only matter for rows where `groupId IS NOT NULL` (group sessions) or for the `groups` table itself.

### JSON shape stored in the columns

Both columns contain the **same JSON structure** (a stringified object):

```json
{
  "perChar": {
    "charId": {
      "emotion": "happy",
      "emotionIntensity": "moderate",
      "affection": 87,
      "trust": 42,
      "arousal": 12,
      "fixation": "the user’s scent",
      "fixationLifespan": 18,
      "needs": { "hunger": 34, "energy": 67, ... },
      "relationships": {
        "otherCharId": { "affection": 31, "trust": 19, ... }
      },
      ... other internal realism keys ...
    },
    ...
  },
  "authorNotes": { "charId": "text here" },
  "authorNoteStrengths": { "charId": 6 },
  "characterSystemPrompts": { "charId": "group-only system prompt" },
  "ragEnabled": true,
  "retrievalCount": 8,
  "memoryBudgetPercent": 10.0,
  "characterRAGPriorities": { "charId": 1.0 },
  "savedAt": "2026-05-..."
}
```

- `perChar` is the important one (the actual bond/trust/emotion/needs/fixation/relationships data).
- During a short transition period the loader also accepts a flat map of charId → blob as a fallback.
- For 1:1 (non-group) sessions the column is almost always just `'{}'`.

### Behavioral change (important)

The old hidden checkpoint system is **completely dead**:
- We no longer write or read any messages with `sender = "__group_state__"` or `characterId = "__meta__"`.
- All group realism state now lives only in the two columns above.
- When a group session is loaded, Front Porch prefers `sessions.group_realism_state`, then falls back to `groups.default_member_realism_state`.

This was a deliberate clean break (user-authorized) so that Group Cards can carry full fidelity realism state when members are split out into solo characters.

### Impact on Character Card Forge (direct SQL)

- **Non-group paths** (normal character sessions): zero impact. Your existing INSERT/UPDATE statements continue to work.
- **Group-related paths**:
  - If Forge creates or updates rows in the `groups` table, you can now populate `default_member_realism_state` if you want the realism/needs state to survive export/import/split.
  - If Forge creates or updates rows in `sessions` that belong to a group (`groupId` not null), populating `group_realism_state` will make the evolved state visible inside Front Porch.
  - If you leave the columns at their default `'{}'`, Front Porch treats the group as having no pre-existing realism state (new behavior is graceful).

If your code uses explicit column lists in INSERT/UPDATE for `groups` or `sessions`, you will eventually want to include the two new columns when you start supporting group realism features.

### New Group Card format (fpa_group)

Front Porch now supports exporting an entire group as a single `.group.png` (new standard using the private `fpa_group` tEXt chunk so SillyTavern etc. ignore it).

Inside the JSON envelope (`data` object) we now carry:
```json
"realism_state": { ... same shape as above ... }
```
(or under `extensions.realism_state` for older cards).

When Forge eventually adds Group Card support, you will want to read/write that key so that realism state survives the round-trip and split-to-solo operations.

### Recommendation

For now you can safely ignore the two columns and the `realism_state` key inside Group Cards — everything will continue to work (just without carrying evolved group realism across tools).

When you are ready to support groups + realism in Forge, let me know and I’ll give you:
- A small test database with realistic data in the new columns
- Example Group Card PNGs
- The exact loader/serializer code if you want to reuse the shape

Happy to stay in sync. The direct SQL integration you built is genuinely useful to users.

— Grok (on behalf of the Front Porch team)

---

**Files changed in this release that affect you:**
- `lib/database/database.dart` (table definitions + v29→v30 migration)
- `lib/services/chat_service.dart` (all group realism now routes through the two columns)
- `lib/models/group_chat.dart`, `group_chat_repository.dart`
- `lib/models/group_card.dart` + `services/group_card_service.dart` (realism_state in Group Cards)
- `docs/Rawhide.md` (user-facing note)

Schema version is now 30. The migration is purely additive and uses `DEFAULT` so old rows are fine.

Let me know if you need the raw migration SQL or a sample DB file.
