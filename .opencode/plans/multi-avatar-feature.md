# Multi-Avatar Feature Plan

## Overview

Allow characters to have multiple avatar images (up to 10) with one marked as the "prime" image for display. Users can add, remove, label, reorder, and set prime avatars. Chat session avatar cycling is a display-only feature that doesn't change the prime.

**User request:** Discord community feature request inspired by similar apps.

---

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Max avatars per character | 10 | Matches reference app, reasonable storage limit |
| Label type | Free-text | Flexible ("outfit 1", "casual", "formal") |
| Storage location | Per-character subfolder | `KoboldManager/Characters/{Name}/avatars/` — avoids filename collisions, keeps related files together |
| Main character PNG | Always shows prime avatar | Best compatibility with KoboldCpp/V2 card ecosystem |
| Prime avatar | Set in editor/creator, changeable anytime | User controls which image represents the character |
| Chat cycling | Session-scoped only | Display-only convenience, doesn't change any stored state |
| Home page display | Prime image only | KISS — no hover previews, no complexity |
| Backward compat | Existing single image becomes avatar #1 | Seamless migration, no data loss |

---

## Phase 1: Data Layer

### 1.1 Database Schema (v23 → v24)

**File:** `lib/database/database.dart`

**New table — `character_avatars`:**

| Column | Type | Notes |
|--------|------|-------|
| `id` | TEXT (PK) | UUID |
| `character_id` | TEXT (FK → characters.id) | Cascade delete |
| `filename` | TEXT NOT NULL | e.g. `"avatar_1.png"` |
| `label` | TEXT | Nullable free-text label |
| `display_order` | INTEGER NOT NULL | Sort order, defaults 0 |
| `created_at` | DATETIME | Auto-timestamp |

**New column — `characters` table:**

| Column | Type | Notes |
|--------|------|-------|
| `prime_avatar_index` | INTEGER NOT NULL | 1-based index into avatar list, defaults 1 |

**Migration pattern:** Use `if (from < 24)` with `try/catch` on ALTER (per existing convention for optional columns).

**Migration code:**
```dart
if (from < 24) {
  // v23→v24: multi-avatar support
  await customStatement('''CREATE TABLE character_avatars (
    id TEXT NOT NULL PRIMARY KEY,
    character_id TEXT NOT NULL REFERENCES characters(id),
    filename TEXT NOT NULL,
    label TEXT,
    display_order INTEGER NOT NULL DEFAULT 0,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
  )''');
  try {
    await customStatement(
      'ALTER TABLE characters ADD COLUMN prime_avatar_index INTEGER NOT NULL DEFAULT 1',
    );
  } catch (_) {}
}
```

### 1.2 New Model

**New file:** `lib/models/avatar_image.dart` (~40 lines)

```dart
class AvatarImage {
  final String id;           // UUID
  final String characterId;
  final String filename;     // basename, e.g. "avatar_3.png"
  final String? label;       // free-text label
  final int displayOrder;
  final DateTime createdAt;

  File get file => storageService.resolveAvatarPath(characterId, filename);
}
```

### 1.3 CharacterCard Model Changes

**File:** `lib/models/character_card.dart`

Add fields:
```dart
int primeAvatarIndex = 1;
List<AvatarImage>? avatarImages;  // lazy-loaded at runtime, not directly persisted

/// Returns the resolved file path for display (prime avatar or fallback).
File? get primeAvatarFile {
  if (avatarImages == null || avatarImages!.isEmpty) return null;
  final idx = primeAvatarIndex.clamp(1, avatarImages!.length);
  return avatarImages![idx - 1].file;
}
```

---

## Phase 2: Storage & Repository Layer

### 2.1 Storage Service Changes

**File:** `lib/services/storage_service.dart`

Add methods (~30 lines):

```dart
/// Get the avatars subdirectory for a character.
Directory characterAvatarDir(String characterId, String characterName) {
  final safeName = characterName
      .replaceAll(RegExp(r'[^\w\s-]'), '')
      .replaceAll(RegExp(r'\s+'), '_');
  return Directory(path.join(charactersDir.path, safeName, 'avatars'));
}

/// Resolve an avatar image path for a given character.
File resolveAvatarPath(String characterId, String filename) {
  final char = _characters?.firstWhere(
    (c) => c.dbId == characterId,
    orElse: () => throw Exception('Character not found'),
  );
  if (char != null) {
    final dir = characterAvatarDir(characterId, char.name);
    final file = File(path.join(dir.path, filename));
    if (file.existsSync()) return file;
  }
  // Fallback: flat characters directory (backward compat)
  return File(path.join(charactersDir.path, filename));
}

/// Resolve the prime avatar File for a character.
File? resolvePrimeAvatar(CharacterCard character) {
  if (character.avatarImages != null && character.avatarImages!.isNotEmpty) {
    final idx = character.primeAvatarIndex.clamp(1, character.avatarImages!.length);
    return character.avatarImages![idx - 1].file;
  }
  return null;
}
```

### 2.2 Character Repository Changes

**File:** `lib/services/character_repository.dart`

New methods:

| Method | Description |
|--------|-------------|
| `getAvatarImages(String characterId)` | Fetch all avatars for a character |
| `addAvatar(String characterId, Uint8List bytes, String? label)` | Save new avatar PNG to avatars folder |
| `removeAvatar(String characterId, String avatarId)` | Delete avatar file + DB row |
| `setPrimeAvatar(String characterId, int index)` | Update prime_avatar_index in DB |
| `reorderAvatars(String characterId, List<String> orderedIds)` | Update display_order for all avatars |
| `updateAvatarLabel(String avatarId, String label)` | Update label in DB |
| `setCharacterNameForAvatarDir(String characterId, String newName)` | Rename avatars folder when character is renamed |

Modify existing methods:

- `addCharacter()`: Create avatars subdirectory on character creation
- `deleteCharacter()`: Delete entire avatars subdirectory when character is deleted
- `cleanOrphanedPngs()`: Also scan avatars subdirectories (don't delete PNGs inside them)
- `loadCharacters()`: After loading characters, also load their avatar images

### 2.3 Database Helper Methods

**File:** `lib/database/database.dart`

New helper methods in `AppDatabase`:

| Method | Description |
|--------|-------------|
| `getAvatarImagesForCharacter(String characterId)` | Query avatars table |
| `insertAvatar(Avatar avatar)` | Insert new avatar row |
| `deleteAvatar(String avatarId)` | Delete avatar row |
| `updateAvatarLabel(String avatarId, String label)` | Update label |
| `updatePrimeAvatarIndex(String characterId, int index)` | Update prime index |
| `updateAvatarDisplayOrder(String characterId, Map<String, int> orderMap)` | Bulk reorder |

---

## Phase 3: V2CardService Integration

**File:** `lib/services/v2_card_service.dart`

When saving the main character PNG, always use the **prime avatar image** as the base image. If the prime avatar changes after save, the PNG should be regenerated.

Change `saveCardAsPng()` to accept an optional `File? sourceImage` parameter:
- If provided: use that image as the PNG base
- If null: fall back to existing behavior (use imagePath)

When `primeAvatarIndex` changes on a character, trigger a PNG regeneration.

---

## Phase 4: Core UI — Avatar Management Dialog

### 4.1 New Dialog

**New file:** `lib/ui/dialogs/character_avatars_dialog.dart` (~400 lines)

This is the primary UI for managing character avatars. It's a reusable dialog opened from:
- Edit character page (full editor)
- Edit character dialog (right-click menu)
- Character creator page (after first avatar picked)

**UI Layout:**

```
┌──────────────────────────────────────────┐
│  Character Images (Up to 10 images)      │
│                                          │
│  ┌──────┐  ┌──────┐  ┌──────┐  ┌────┐  │
│  │  🖼️  │  │  🖼️  │  │  🖼️  │  │ +  │  │
│  │  ⭐  │  │      │  │      │  │    │  │
│  │label │  │label │  │label │  │Add │  │
│  │[x]   │  │[x]   │  │[x]   │  │img │  │
│  └──────┘  └──────┘  └──────┘  └────┘  │
│                                          │
│                    [Cancel]    [Done]     │
└──────────────────────────────────────────┘
```

**Features:**
- Grid of avatar thumbnails (3-column grid)
- Star icon overlay on prime avatar (tap to set/unset)
- Label text input below each thumbnail ("Add label")
- Delete button (trash icon) below each thumbnail
- "Add image" card as last item (opens file picker)
- Visual disabled state when 10 avatars reached
- Drag-to-reorder support
- Confirmation dialog on delete
- "Set as prime" on star tap

**Implementation approach:**
- Use `StatefulWidget` with local state for the avatar list
- `file_picker` for adding images
- `ImageCropDialog` for cropping before saving
- Save to DB + disk on "Done"
- Cancel discards unsaved changes

---

## Phase 5: Editor & Creator Integration

### 5.1 Edit Character Page

**File:** `lib/ui/pages/edit_character_page.dart` (~1,874 lines)

Add "Manage Avatars" button in the avatar section that opens `CharacterAvatarsDialog`. Place it near the existing avatar preview area.

### 5.2 Edit Character Dialog

**File:** `lib/ui/dialogs/edit_character_dialog.dart` (~835 lines)

Add "Manage Avatars" button to the dialog. Opens the same `CharacterAvatarsDialog`.

### 5.3 Manual Character Creator

**File:** `lib/ui/pages/create_character_page.dart` (~1,538 lines)

Modify Step 0 (Identity):
- After picking first avatar, show "Add more avatars" option
- Display selected avatars in a small grid within the step
- Allow setting which one is prime before saving
- On save, write all avatars to the character's avatars subdirectory

---

## Phase 6: Display Updates

### 6.1 Home Page

**File:** `lib/ui/pages/home_page.dart` (~4,381 lines)

Modify `_resolveCharImage()`:
```dart
File _resolveCharImage(CharacterCard character) {
  if (character.avatarImages != null && character.avatarImages!.isNotEmpty) {
    final idx = character.primeAvatarIndex.clamp(1, character.avatarImages!.length);
    return character.avatarImages![idx - 1].file;
  }
  // Fallback to old imagePath
  return storage.resolveCharacterImage(character.imagePath ?? '');
}
```

Modify `loadCharacters()` to also load avatar images for each character after loading the character list.

### 6.2 Chat Page

**File:** `lib/ui/pages/chat_page.dart` (~10,432 lines)

Add avatar cycling strip in the chat header area:
- Large prime avatar displayed at top
- Thumbnail row below with left/right arrow buttons
- Tapping a thumbnail switches the displayed avatar for that chat session only
- Session-scoped: doesn't affect prime avatar or any saved state
- "Edit Character" button opens `CharacterAvatarsDialog`

The cycling state is local to the chat page widget (not persisted).

---

## Phase 7: Web Server API

**File:** `lib/services/web_server_service.dart` (~4,847 lines)

New endpoints:

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/characters/<id>/avatars` | List all avatars for character |
| POST | `/api/characters/<id>/avatars` | Add new avatar (base64 + optional label) |
| DELETE | `/api/characters/<id>/avatars/<avatarId>` | Remove avatar |
| PUT | `/api/characters/<id>/avatars/prime` | Set prime avatar (`{ "index": 1 }`) |
| PUT | `/api/characters/<id>/avatars/<id>/label` | Update label (`{ "label": "..." }`) |
| PUT | `/api/characters/<id>/avatars/reorder` | Reorder (`{ "order": ["id1", "id2"] }`) |
| GET | `/api/characters/<id>/avatars/<index>` | Serve avatar image by index |

Modify existing `POST /api/characters/<id>/avatar` to add as additional avatar rather than replacing prime.

---

## Phase 8: Migration & Cleanup

### 8.1 Backward Compatibility

- Existing characters with `imagePath` set: the single image becomes avatar #1 on first load
- `primeAvatarIndex` defaults to 1
- `avatarImages` list populated from the single `imagePath` at load time
- Main character PNG stays at old location (unchanged)
- `cleanOrphanedPngs()` ignores avatars subdirectories

### 8.2 Lazy Migration Strategy

On `loadCharacters()`, for characters that have `imagePath` but no avatar DB records:
1. Create the avatars subdirectory
2. Move the existing PNG into it as `avatar_1.png`
3. Insert a `character_avatars` row
4. Update the character's `imagePath` to point to the new location

This avoids a bulk migration pass and handles migration incrementally.

---

## File Change Summary

| File | Type | Lines Changed |
|------|------|---------------|
| `lib/database/database.dart` | Modify | +60 (new table, column, migration, helper methods) |
| `lib/models/avatar_image.dart` | **NEW** | ~40 |
| `lib/models/character_card.dart` | Modify | +15 |
| `lib/services/storage_service.dart` | Modify | +40 |
| `lib/services/character_repository.dart` | Modify | +150 |
| `lib/services/v2_card_service.dart` | Modify | +20 |
| `lib/ui/dialogs/character_avatars_dialog.dart` | **NEW** | ~400 |
| `lib/ui/pages/create_character_page.dart` | Modify | +80 |
| `lib/ui/pages/edit_character_page.dart` | Modify | +30 |
| `lib/ui/dialogs/edit_character_dialog.dart` | Modify | +20 |
| `lib/ui/pages/home_page.dart` | Modify | +40 |
| `lib/ui/pages/chat_page.dart` | Modify | +120 |
| `lib/services/web_server_service.dart` | Modify | +150 |

---

## Implementation Order

1. **Phase 1** — Database schema + model (foundation, no UI)
2. **Phase 2** — Storage + repository (data operations)
3. **Phase 3** — V2CardService (PNG integration)
4. **Phase 4** — Avatar management dialog (core UI)
5. **Phase 5** — Editor + creator integration (wire up)
6. **Phase 6** — Display updates (home page + chat)
7. **Phase 7** — Web server API (remote access)
8. **Phase 8** — Migration + cleanup (backward compat)

---

## Merge Safety Notes

Per `AGENTS.md` guidelines:

- **Database changes:** Always run `git pull --rebase origin main` before starting. This is a new table + column — low risk of conflicts with existing code.
- **After editing large files** (`chat_page.dart` 10K, `home_page.dart` 4.4K, `web_server_service.dart` 4.8K), verify no existing functions were accidentally reverted.
- **Run `flutter analyze`** before every commit — 0 errors required.
- **Run `flutter test`** — ensure all existing tests pass.
- **Key verification:** After modifying `character_repository.dart`, verify `cleanOrphanedPngs()` still works correctly and doesn't delete avatars subdirectory contents.

---

## Testing Checklist

### Unit Tests
- [ ] AvatarImage model serialization/deserialization
- [ ] Repository: add/remove/set prime/reorder avatars
- [ ] Storage: avatar path resolution (per-character + fallback)
- [ ] V2CardService: prime avatar used as PNG base

### Manual Tests
- [ ] Create character with single avatar — displays on home page
- [ ] Create character with multiple avatars — set prime, verify display
- [ ] Edit character — add/remove/reorder avatars, set prime
- [ ] Chat page — avatar cycling works, doesn't affect prime
- [ ] Import character with existing single image — migrates correctly
- [ ] Delete character — avatars subdirectory cleaned up
- [ ] Rename character — avatars folder renamed
- [ ] Cloud sync — avatars synced with character
- [ ] Web server API — all endpoints functional
- [ ] Edge case: character with 10 avatars (max) — "Add" disabled
- [ ] Edge case: delete prime avatar — next avatar becomes prime
- [ ] Edge case: delete all avatars — falls back to old imagePath

---

## Known Trade-offs

1. **Per-character folders** vs flat namespace: Folders prevent filename collisions but create more directories. The flat approach would require more complex naming (`{charId}_avatar_{n}.png`). Chose folders for cleanliness.

2. **Lazy migration** vs bulk migration: Lazy migration avoids a slow startup but means characters may temporarily have both old and new avatar storage. Bulk migration is cleaner but slower on first run after update.

3. **Session-scoped chat cycling**: Keeps implementation simple and doesn't risk user confusion about which avatar is "real" prime. The cycling is purely visual.

4. **No animated avatars**: GIF/WebP support not included in this phase. Could be added later if requested.
