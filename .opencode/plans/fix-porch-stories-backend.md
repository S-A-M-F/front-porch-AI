# Fix: Porch Stories Respects Global Backend Setting

## Problem
Porch Stories feature tries to connect to `127.0.0.1:8001` (KoboldCPP) even when the user doesn't have KoboldCpp running and has selected a different backend (OpenRouter, Nano-GPT, LM Studio, etc.) in the global settings.

## Root Cause
The default backend type in `storage_service.dart:112` is set to `'kobold'`:
```dart
String _backendType = 'kobold'; // 'kobold' or 'openRouter'
```

When no backend preference has been saved (new users or first-time users), the `LLMProvider` defaults to `BackendType.kobold`, which makes `llmProvider.activeService` return the `KoboldService`. The `StoryPipelineService` correctly uses `llmProvider.activeService`, but since the default is Kobold, it tries to connect to the local KoboldCPP server.

## Architecture (Already Correct)
The code architecture already respects the global backend setting:
- `LLMProvider.activeService` returns the correct service based on `_activeBackend`
- `StoryPipelineService` is created with `llmProvider.activeService` in `main.dart:382,398`
- `LLMProvider._syncFromStorage()` reads the persisted backend type from `StorageService`

The only issue is the **default value**.

## Fix

### Primary Fix: `lib/main.dart` lines 387-402

The `update` function in the `ChangeNotifierProxyProvider2` for `StoryPipelineService` always returns the existing instance, never recreating it with the new backend. **Remove the early return** so the service is rebuilt with the correct `activeService`:

```dart
// Before (lines 387-402):
update: (context, llmProvider, storage, previous) {
  if (previous != null) return previous;  // ← BUG: never updates
  final sidecar = Provider.of<EmbeddingSidecar>(context, listen: false);
  ...
  return StoryPipelineService(repo, llmProvider.activeService, memoryService, db);
},

// After:
update: (context, llmProvider, storage, previous) {
  final sidecar = Provider.of<EmbeddingSidecar>(context, listen: false);
  final embeddingService = EmbeddingService(sidecar);
  final memoryService = MemoryService(embeddingService, storage, db);
  final repo = Provider.of<StoryRepository>(context, listen: false);
  return StoryPipelineService(
    repo,
    llmProvider.activeService,  // ← Now gets the CURRENT active backend
    memoryService,
    db,
  );
},
```

## Impact
- **Backend switches**: `StoryPipelineService` will now correctly use whatever backend is currently active (Kobold, OpenRouter, Nano-GPT, LM Studio)
- **No breaking changes**: The service is recreated on any LLMProvider/StorageService change, which is the correct behavior for a `ChangeNotifierProxyProvider2`
- **Existing users**: Backend switching will now work as expected for Porch Stories

## Files to Change
1. `lib/main.dart` lines 387-402 — remove early return in `update` function
