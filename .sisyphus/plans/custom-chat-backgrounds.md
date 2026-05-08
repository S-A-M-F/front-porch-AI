# Custom Chat Backgrounds — Implementation Plan

## Goal
Allow users to upload and manage multiple custom images (JPG, PNG, WebP, GIF, BMP, TIFF) as chat backgrounds. Each custom background gets a user-assigned name. Custom backgrounds auto-resize to fill the chat window and scale on resize — identical to the built-in backgrounds, but rendered from a file path.

## Architecture Analysis

### Current System
- **StorageService** (`lib/services/storage_service.dart`): Stores `chatBackground` as a `String` preference. Keys are asset identifiers (`"cyberpunk_bedroom"`, `"none"`, etc.). The `_k()` method namespaces keys with `beta_` for prerelease builds.
- **BackgroundSettingsDialog** (`lib/ui/dialogs/background_settings_dialog.dart`): Renders a 3-column grid of thumbnails. Each tile calls `storageService.setChatBackground(key)` on tap. 18 built-in assets + "None".
- **ChatPage** (`lib/ui/pages/chat_page.dart`, ~line 366): Looks up `bgKey` in a `bgAssets` const map. If found, renders `Image.asset(bgPath, fit: BoxFit.cover)` inside `Positioned.fill`. If not found (e.g., `"none"`), renders nothing — just a solid color.
- **Expression background sprite** (`lib/ui/pages/chat_page.dart`, ~line 419-474): Already renders `FileImage` via `BoxDecoration` + `DecorationImage` + `BoxFit.cover` — the exact pattern needed for custom backgrounds.

### Design Decisions

**Built-in vs custom storage:** Built-in backgrounds remain as Flutter assets (`Image.asset()`). Custom backgrounds are copied to app data on upload. They don't need to live in the same directory — the selector just renders both sources together.

**Multiple custom backgrounds:** Users can upload as many as they want. Each is stored as a separate file with a unique internal key, and the user sees them by their assigned name in the grid.

**Naming:** On upload, a dialog prompts the user for a name. The name is what appears in the grid. The internal key (UUID) is what's stored in `chatBackground` — this avoids all collision issues.

**Collision strategy:** Built-in backgrounds use asset keys like `"cyberpunk_bedroom"`. Custom backgrounds use UUID keys like `"a1b2c3d4"`. The user's name is metadata stored alongside the path, never used as the key. No collision possible between custom and built-in. Duplicate names among custom backgrounds are prevented by checking the list.

## Data Model

Each custom background entry:
```dart
// Stored as List<Map<String, String>> in SharedPreferences
// {'id': 'uuid', 'name': 'user name', 'filePath': '/full/path/to/image.png'}
```

## Changes (3 files)

### 1. `lib/services/storage_service.dart` — Custom background list + directory

**What:** Add a list of custom background entries, persistence, and a directory helper.

**Changes:**

Add field near line 141 (after `_chatBackground`):
```dart
List<Map<String, String>> _customBackgrounds = [];
// Each entry: {'id': uuid, 'name': 'user name', 'filePath': '/full/path/to/image.png'}
```

Add getter near line 304:
```dart
List<Map<String, String>> get customBackgrounds => List.unmodifiable(_customBackgrounds);
```

Add setter methods near line 943 (after `setChatBackground`):
```dart
Future<void> addCustomBackground(String id, String name, String filePath) async {
  _customBackgrounds.add({'id': id, 'name': name, 'filePath': filePath});
  final encoded = _customBackgrounds.map((e) => jsonEncode(e)).toList();
  await _prefs?.setStringList(_k('custom_backgrounds'), encoded);
  notifyListeners();
}

Future<void> removeCustomBackground(String id) async {
  _customBackgrounds.removeWhere((e) => e['id'] == id);
  final encoded = _customBackgrounds.map((e) => jsonEncode(e)).toList();
  await _prefs?.setStringList(_k('custom_backgrounds'), encoded);
  notifyListeners();
}

/// Returns true if a custom background with this name already exists.
bool hasCustomBackgroundWithName(String name) {
  return _customBackgrounds.any((e) => e['name'] == name);
}
```

Add directory helper near `characterAvatarDir()` (line 73):
```dart
Directory customBackgroundDir() {
  final appDir = appDataDir();
  final dir = Directory('${appDir.path}/custom_backgrounds');
  return dir;
}
```

Load from prefs in `init()` near line 488:
```dart
final customBgsRaw = _prefs?.getStringList(_k('custom_backgrounds'));
if (customBgsRaw != null) {
  _customBackgrounds = customBgsRaw.map((s) => jsonDecode(s) as Map<String, String>).toList();
}
```

Ensure directory is created in `init()` (same pattern as other dirs).

### 2. `lib/ui/dialogs/background_settings_dialog.dart` — Custom tiles merged into grid

**What:** Custom background tiles are rendered alongside built-in backgrounds in the same grid. An "Add Custom" button at the top opens a name+file picker dialog.

**Changes:**

At the top of the grid area, before the built-in backgrounds, add an "Add Custom Background" button:
- Outlined button with `+` icon and text "Add Custom Background"
- On tap: show a dialog with:
  - Text field for the background name
  - File picker button (or drag-and-drop area) for the image
  - Submit button — validates name is not empty and not a duplicate, validates image extension
  - On success: copy image to `customBackgroundDir()` with UUID filename, call `addCustomBackground()`, call `setChatBackground(uuid)` to activate it immediately

After the built-in backgrounds list, iterate `storageService.customBackgrounds` and add a tile for each:
- Thumbnail rendered with `Image.file(File(entry['filePath']!), fit: BoxFit.cover)`
- Label shows the user-assigned `name`
- Blue border when selected (`storageService.chatBackground == entry['id']`)
- A small "x" delete button in the corner (with confirmation dialog)
- On delete: call `removeCustomBackground(id)`, optionally fall back to "none" if the deleted one was active

### 3. `lib/ui/pages/chat_page.dart` — Render custom background from file path

**What:** In the background rendering section (~line 366-485), add a branch for custom backgrounds.

**Changes:**

After the existing `bgAssets[bgKey]` lookup, add:

```dart
// Custom background check (after built-in asset check)
if (!bgPathExists && storageService.customBackgrounds.any((e) => e['id'] == bgKey)) {
  final customEntry = storageService.customBackgrounds.firstWhere((e) => e['id'] == bgKey);
  final customFile = File(customEntry['filePath']!);
  if (await customFile.exists()) {
    Positioned.fill(
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: FileImage(customFile),
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    ),
    Positioned.fill(
      child: IgnorePointer(
        child: Container(color: Colors.black.withValues(alpha: 0.45)),
      ),
    ),
  }
}
```

**Why `BoxFit.cover` handles resize:** `BoxFit.cover` always fills the container, maintaining aspect ratio. When the window resizes, Flutter automatically re-clips — no manual resize listener needed. This is identical to how built-in backgrounds work (they're also `Image.asset` with `BoxFit.cover`).

## Files Changed Summary

| File | Lines Changed (est.) | Type |
|------|---------------------|------|
| `lib/services/storage_service.dart` | ~40 | Add list field, getters, add/remove methods, dir helper, init load |
| `lib/ui/dialogs/background_settings_dialog.dart` | ~60 | Add "Add Custom" button, custom tiles in grid, delete with confirmation |
| `lib/ui/pages/chat_page.dart` | ~20 | Add custom background rendering branch |

## Verification Checklist

- [ ] "Add Custom Background" button appears at top of background settings grid
- [ ] Dialog prompts for name and image file
- [ ] User name is validated (not empty, not duplicate)
- [ ] File extension is validated (.jpg, .jpeg, .png, .webp, .gif, .bmp, .tiff)
- [ ] Uploaded image is copied to app data directory with UUID filename
- [ ] Custom background tiles appear in the grid alongside built-in backgrounds
- [ ] Custom background appears selected (blue border) in the grid
- [ ] Chat page renders the custom image as background
- [ ] Background covers full chat area regardless of source image dimensions
- [ ] Darkening overlay applies correctly to custom backgrounds
- [ ] Custom backgrounds persist across app restarts
- [ ] Delete button removes the tile and its file
- [ ] If custom image file is deleted externally, app falls back gracefully (no crash)
- [ ] No naming collision between custom and built-in backgrounds (separate namespaces)
- [ ] Duplicate custom names are prevented
- [ ] No type errors (`flutter analyze` clean)
- [ ] Works on Windows, macOS, Linux
