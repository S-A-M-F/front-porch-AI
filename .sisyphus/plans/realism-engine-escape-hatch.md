# Plan: Realism Engine Escape Hatch

## TL;DR
> **Summary**: Add an escape hatch to cancel realism engine evaluation when the LLM falls into a logic loop. After cancel, user manually regenerates the response (which re-runs the realism eval).
> **Deliverables**: 
> - `_isCancellingRealismEval` flag in ChatService
> - `cancelRealismEval()` method that aborts streaming and resets state
> - Updated `_fireLLMEval` to check cancellation flag and exit gracefully
> - Cancel button on realism processing overlay UI
> - Logging for observability
> **Effort**: Short
> **Parallel**: YES - 2 waves (backend + UI)
> **Critical Path**: [1] Add flag + cancel method → [2] Update streaming loop → [3] Add Cancel button → [4] Drop to chat interface

## Context
### Original Request
"Currently there is no way to stop the realism engine when it is running its evaluation. This is a problem if the LLM falls into a logic loop. There needs to be an 'escape hatch' to cancel the processing so the user can just regen the response thus running the realism mode evaluation again."

### Interview Summary
- Escape hatch must work for both regular realism evals and greeting evals (post-greeting, retroactive)
- After cancel, user manually regenerates the response (which re-runs the realism eval)
- Cancel should reset `_realismEvalStreamText` and `_pendingRealismMetadata`
- No timeout fallback needed - Kobold already has 30s timeout on ensureServerIdle
- **User feedback (2025-05-04)**: Automatic restart defeats purpose if user wants to switch models. After cancel, drop back to chat interface for manual regenerate.

### Metis Review (gaps addressed)
1. Streaming loop must check `_isCancellingRealismEval` flag periodically and exit gracefully
2. `cancelRealismEval()` should await `abortGeneration()` completion
3. After cancel, drop back to chat interface - user manually regenerates (not automatic)
4. Add logging for observability: cancel requested, abort invoked, streaming terminated
5. Error handling: if `abortGeneration()` throws, catch and reset state gracefully
6. Idempotence: `cancelRealismEval()` should be safe to call multiple times
7. Edge case: cancellation near end of stream should still perform cleanup and allow manual regenerate

## Work Objectives
### Core Objective
Add escape hatch to cancel realism engine evaluation when LLM falls into a logic loop, allowing user to manually regenerate the response (which re-runs the realism eval).

### Deliverables
- Add `_isCancellingRealismEval` flag to ChatService
- Add `cancelRealismEval()` method to ChatService
- Update `_fireLLMEval` streaming loop to check cancellation flag
- Add Cancel button to realism processing overlay UI
- Add logging for cancel requests and abort outcomes
- After cancel, drop back to chat interface for manual regenerate

### Definition of Done (verifiable conditions with commands)
- [ ] `_isCancellingRealismEval` flag exists in ChatService (default false)
- [ ] `cancelRealismEval()` method exists and calls `llmService.abortGeneration()`
- [ ] `_fireLLMEval` checks `_isCancellingRealismEval` flag and exits gracefully
- [ ] Cancel button appears on realism processing overlay when `_isEvaluatingRealism` or `_isProcessingGreeting` is true
- [ ] After cancel, `_realismEvalStreamText` is reset to '' and `_pendingRealismMetadata` is cleared
- [ ] After cancel, UI drops back to chat interface (no automatic restart)
- [ ] User can manually regenerate to re-run realism eval
- [ ] Logging shows "Realism eval cancel requested" and "abortGeneration invoked" messages
- [ ] `flutter analyze` passes with no errors
- [ ] No regression in existing functionality for users who don't use escape hatch

### Must Have
- Escape hatch works for both regular realism evals and greeting evals
- After cancel, drop back to chat interface for manual regenerate
- Cancel button only appears when realism evaluation is actively streaming
- State reset: `_realismEvalStreamText = ''`, `_pendingRealismMetadata = null`
- Logging for observability
- Error handling: graceful fallback if `abortGeneration()` throws
- Idempotence: safe to call `cancelRealismEval()` multiple times

### Must NOT Have (guardrails, AI slop patterns, scope boundaries)
- No automatic restart after cancel (user must manually regenerate)
- No architectural refactors - keep changes limited to ChatService, realism overlay UI, and streaming loop
- No timeout fallback needed (Kobold already has 30s timeout)
- No separate UI state for "cancelling" - just show overlay with disabled state
- No breaking changes to existing API

## Verification Strategy
> ZERO HUMAN INTERVENTION - all verification is agent-executed.
- Test decision: tests-after (existing test infrastructure used)
- QA policy: Every task has agent-executed scenarios
- Evidence: .sisyphus/evidence/task-{N}-{slug}.{ext}

## Execution Strategy
### Parallel Execution Waves
> Target: 5-8 tasks per wave. <3 per wave (except final) = under-splitting.
> Extract shared dependencies as Wave-1 tasks for max parallelism.

Wave 1: [backend foundation - flag + cancel method + streaming loop update]
Wave 2: [UI foundation - Cancel button on realism processing overlay]
Wave 3: [integration - drop to chat interface after cancel]
Wave 4: [logging + error handling + edge cases]
Wave 5: [final verification - analyze + test + acceptance]

### Dependency Matrix (full, all tasks)
| Task | Blocks | Blocked By |
|------|--------|------------|
| T1: Add flag | T2, T3 | - |
| T2: Add cancel method | T3, T4, T5 | T1 |
| T3: Update streaming loop | T4, T5 | T1 |
| T4: Add Cancel button | - | T2, T3 |
| T5: Drop to chat interface | T6 | T2, T3, T4 |
| T6: Logging + error handling | T7 | T2, T3, T4, T5 |
| T7: Final verification | - | T6 |

### Agent Dispatch Summary (wave → task count → categories)
- Wave 1: 2 tasks (backend)
- Wave 2: 1 task (UI)
- Wave 3: 1 task (integration)
- Wave 4: 1 task (logging/error handling)
- Wave 5: 3 tasks (final verification - oracle, unspecified-high, unspecified-high)

## TODOs
> Implementation + Test = ONE task. Never separate.
> EVERY task MUST have: Agent Profile + Parallelization + QA Scenarios.

- [x] T1. Add `_isCancellingRealismEval` flag to ChatService

  **What to do**: 
  - Add `bool _isCancellingRealismEval = false;` to ChatService class (near line 348, after `_isEvaluatingRealism`)
  - Add getter: `bool get isCancellingRealismEval => _isCancellingRealismEval;`
  - Set default value to false in class initialization

  **Must NOT do**: 
  - Do not change any existing flags or methods
  - Do not add any logic to this task - just add the field

  **Recommended Agent Profile**:
  - Category: `quick` - Reason: Simple field addition, no complex logic
  - Skills: [`dart`] - Why: Must understand Dart class structure and Flutter state management
  - Omitted: [] - Why: No external dependencies needed

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: T2, T3 | Blocked By: -

  **References**:
  - Pattern: `lib/services/chat_service.dart:348` - Follow existing flag pattern for `_isEvaluatingRealism`
  - API/Type: `lib/services/chat_service.dart:639` - Reference existing getter pattern

  **Acceptance Criteria**:
  - [ ] `_isCancellingRealismEval` field exists in ChatService with default value false
  - [ ] `isCancellingRealismEval` getter exists and returns field value
  - [ ] `flutter analyze lib/services/chat_service.dart` passes with no errors

  **QA Scenarios**:
  ```
  Scenario: Flag exists with correct default
    Tool: Bash
    Steps: flutter analyze lib/services/chat_service.dart
    Expected: Exit code 0, no errors
    Evidence: .sisyphus/evidence/task-T1-analyze.txt

  Scenario: Getter returns correct value
    Tool: Bash
    Steps: grep -n "isCancellingRealismEval" lib/services/chat_service.dart | head -3
    Expected: Shows getter definition and field declaration
    Evidence: .sisyphus/evidence/task-T1-grep.txt
  ```

  **Commit**: YES | Message: `feat: add _isCancellingRealismEval flag to ChatService` | Files: `lib/services/chat_service.dart`

- [x] T2. Add `cancelRealismEval()` method to ChatService

  **What to do**: 
  - Add `cancelRealismEval()` method to ChatService class (after `_fireLLMEval`)
  - Method behavior:
    - If `_isEvaluatingRealism` is false AND `_isProcessingGreeting` is false, return early (no-op)
    - Set `_isCancellingRealismEval = true`
    - Call `await llmService.abortGeneration()` (await for completion)
    - Reset `_isCancellingRealismEval = false`
    - Reset UI/state: `_realismEvalStreamText = ''`, `_pendingRealismMetadata = null`
    - Reset eval flags: `_isEvaluatingRealism = false`, `_isProcessingGreeting = false`
    - Notify listeners
    - Log: "Realism eval cancel requested"
    - Log: "abortGeneration invoked"
    - Catch any exceptions from abortGeneration and log "abortGeneration failed: $e", then proceed to reset state

  **Must NOT do**: 
  - Do not change any existing methods or behavior
  - Do not add new parameters or return types
  - Do not modify the streaming loop in this task
  - Do NOT trigger automatic full flow restart after cancel

  **Recommended Agent Profile**:
  - Category: `quick` - Reason: Straightforward method implementation following existing patterns
  - Skills: [`dart`, `flutter`] - Why: Must understand ChatService state management and abort pattern
  - Omitted: [] - Why: No external dependencies needed

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: T3, T4, T5 | Blocked By: T1

  **References**:
  - Pattern: `lib/services/chat_service.dart:548` - Follow `abortGeneration()` pattern in KoboldService
  - Pattern: `lib/services/chat_service.dart:348-353` - Reference existing flag/field pattern
  - API/Type: `lib/services/chat_service.dart:640` - Reference existing getter pattern

  **Acceptance Criteria**:
  - [ ] `cancelRealismEval()` method exists and has correct signature
  - [ ] Method checks if eval is active before proceeding
  - [ ] Method calls `abortGeneration()` and awaits completion
  - [ ] Method resets all state fields after cancel
  - [ ] Method logs cancel request and abort outcome
  - [ ] Method handles exceptions gracefully (catch and log)
  - [ ] Method does NOT trigger automatic full flow restart
  - [ ] `flutter analyze lib/services/chat_service.dart` passes with no errors

  **QA Scenarios**:
  ```
  Scenario: Method exists with correct behavior
    Tool: Bash
    Steps: grep -A 30 "cancelRealismEval" lib/services/chat_service.dart | head -35
    Expected: Shows complete method implementation
    Evidence: .sisyphus/evidence/task-T2-method.txt

  Scenario: State reset after cancel
    Tool: Bash
    Steps: grep -E "_isCancellingRealismEval|_realismEvalStreamText|_pendingRealismMetadata|_isEvaluatingRealism|_isProcessingGreeting" lib/services/chat_service.dart | grep -E "cancelRealismEval|reset|clear"
    Expected: Shows all state reset operations in cancelRealismEval
    Evidence: .sisyphus/evidence/task-T2-state.txt

  Scenario: No automatic restart
    Tool: Bash
    Steps: grep -A 20 "cancelRealismEval()" lib/services/chat_service.dart | grep -E "await.*Call|evaluate|full.*flow"
    Expected: Should NOT show any eval calls after cancel
    Evidence: .sisyphus/evidence/task-T2-no-restart.txt
  ```

  **Commit**: YES | Message: `feat: add cancelRealismEval() method to ChatService` | Files: `lib/services/chat_service.dart`

- [x] T3. Update `_fireLLMEval` streaming loop to check cancellation flag

  **What to do**: 
  - Modify `_fireLLMEval` method (around line 6885) to check `_isCancellingRealismEval` flag inside the `await for` loop
  - Add check at the start of each iteration: if `_isCancellingRealismEval` is true, break out of loop gracefully
  - After breaking, perform cleanup: return null or empty string (not null to avoid metadata issues)
  - Log: "streaming terminated via cancel" when exit path is taken

  **Must NOT do**: 
  - Do not change any other logic in `_fireLLMEval`
  - Do not modify the retry loop or params construction
  - Do not change the return type or behavior for non-cancel cases

  **Recommended Agent Profile**:
  - Category: `quick` - Reason: Simple flag check added to existing loop
  - Skills: [`dart`, `flutter`] - Why: Must understand streaming patterns and ChatService state
  - Omitted: [] - Why: No external dependencies needed

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: T4, T5 | Blocked By: T1

  **References**:
  - Pattern: `lib/services/chat_service.dart:6885` - Reference existing streaming loop in `_fireLLMEval`
  - Pattern: `lib/services/chat_service.dart:6873` - Reference retry loop structure

  **Acceptance Criteria**:
  - [ ] `_fireLLMEval` checks `_isCancellingRealismEval` flag inside streaming loop
  - [ ] When flag is true, loop breaks gracefully without throwing exception
  - [ ] After break, cleanup is performed (return null or empty string)
  - [ ] Logging shows "streaming terminated via cancel" when exit path is taken
  - [ ] Non-cancel behavior is unchanged (existing tests should still pass)

  **QA Scenarios**:
  ```
  Scenario: Flag check in streaming loop
    Tool: Bash
    Steps: grep -B 2 -A 8 "await for.*chunk in llm.generateStream" lib/services/chat_service.dart | head -15
    Expected: Shows streaming loop with flag check
    Evidence: .sisyphus/evidence/task-T3-loop.txt

  Scenario: Graceful exit on cancel
    Tool: Bash
    Steps: grep -A 3 "isCancellingRealismEval.*true" lib/services/chat_service.dart | head -10
    Expected: Shows break/return after flag check
    Evidence: .sisyphus/evidence/task-T3-exit.txt
  ```

  **Commit**: YES | Message: `refactor: check cancellation flag in _fireLLMEval streaming loop` | Files: `lib/services/chat_service.dart`

- [x] T4. Add Cancel button to realism processing overlay UI

  **What to do**: 
  - Locate `_RealismProcessingOverlay` widget (around line 9714 in chat_page.dart)
  - Add Cancel button to the overlay (add to bottom section, near the content area)
  - Button should only appear when `_isEvaluatingRealism` or `_isProcessingGreeting` is true
  - Button should be disabled when `_isCancellingRealismEval` is true
  - Button should call `widget.chatService.cancelRealismEval()` on press
  - Button styling: Red accent color, consistent with overlay gradient theme

  **Must NOT do**: 
  - Do not change any existing buttons or layout
  - Do not add new UI state beyond the existing overlay
  - Do not modify the animation controllers or styling of existing elements

  **Recommended Agent Profile**:
  - Category: `visual-engineering` - Reason: UI widget modification with styling considerations
  - Skills: [`dart`, `flutter`, `ui`] - Why: Must understand Flutter widget tree and styling
  - Omitted: [] - Why: No complex logic needed

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: T5 | Blocked By: T2, T3

  **References**:
  - Pattern: `lib/ui/pages/chat_page.dart:9714` - Reference existing overlay widget structure
  - Pattern: `lib/ui/pages/chat_page.dart:9965-9972` - Reference circular progress indicator location

  **Acceptance Criteria**:
  - [ ] Cancel button appears on realism processing overlay when evaluating
  - [ ] Cancel button is disabled when `_isCancellingRealismEval` is true
  - [ ] Cancel button calls `chatService.cancelRealismEval()` on press
  - [ ] Button styling is consistent with overlay theme (red accent, gradient background)
  - [ ] `flutter analyze lib/ui/pages/chat_page.dart` passes with no errors

  **QA Scenarios**:
  ```
  Scenario: Cancel button appears during eval
    Tool: Bash
    Steps: grep -A 10 "Cancel" lib/ui/pages/chat_page.dart | head -15
    Expected: Shows Cancel button implementation
    Evidence: .sisyphus/evidence/task-T4-button.txt

  Scenario: Button calls cancelRealismEval
    Tool: Bash
    Steps: grep -B 5 "onPressed.*cancelRealismEval" lib/ui/pages/chat_page.dart | head -10
    Expected: Shows onPressed handler
    Evidence: .sisyphus/evidence/task-T4-handler.txt

  Scenario: Button disabled when cancelling
    Tool: Bash
    Steps: grep -B 2 "onPressed.*isCancellingRealismEval" lib/ui/pages/chat_page.dart | head -10
    Expected: Shows disabled condition
    Evidence: .sisyphus/evidence/task-T4-disabled.txt
  ```

  **Commit**: YES | Message: `feat: add Cancel button to realism processing overlay` | Files: `lib/ui/pages/chat_page.dart`

- [x] T5. Drop to chat interface after cancel (no automatic restart)

  **What to do**: 
  - After `cancelRealismEval()` completes, do NOT trigger any automatic flow
  - The UI should simply return to the chat interface state
  - User can manually regenerate the last message to re-run realism eval
  - Ensure no code paths automatically call generation or eval methods after cancel

  **Must NOT do**: 
  - Do NOT call any generation or eval methods after cancel
  - Do NOT trigger automatic full flow restart
  - Do NOT add any user interaction beyond the chat interface

  **Recommended Agent Profile**:
  - Category: `quick` - Reason: Simple no-op after cancel
  - Skills: [`dart`, `flutter`, `chat-service`] - Why: Must understand ChatService state management
  - Omitted: [] - Why: No external dependencies needed

  **Parallelization**: Can Parallel: YES | Wave 3 | Blocks: T6 | Blocked By: T2, T3, T4

  **References**:
  - Pattern: `lib/services/chat_service.dart:2859-2926` - Reference existing eval flow structure
  - Pattern: `lib/ui/pages/chat_page.dart:9714` - Reference existing overlay dismissal pattern

  **Acceptance Criteria**:
  - [ ] After cancel, no automatic generation or eval methods are called
  - [ ] UI drops back to chat interface state
  - [ ] User must manually regenerate to re-run realism eval
  - [ ] `flutter analyze lib/services/chat_service.dart` passes with no errors

  **QA Scenarios**:
  ```
  Scenario: No automatic eval calls after cancel
    Tool: Bash
    Steps: grep -A 20 "cancelRealismEval()" lib/services/chat_service.dart | grep -E "await.*Call|evaluate|generate"
    Expected: Should NOT show any eval/generate calls after cancel
    Evidence: .sisyphus/evidence/task-T5-no-eval.txt

  Scenario: Chat interface restored
    Tool: Bash
    Steps: grep -B 5 -A 10 "notifyListeners" lib/services/chat_service.dart | grep -A 10 "cancelRealismEval" | head -15
    Expected: Shows notifyListeners after state reset
    Evidence: .sisyphus/evidence/task-T5-notify.txt
  ```

  **Commit**: YES | Message: `refactor: drop to chat interface after cancel (no automatic restart)` | Files: `lib/services/chat_service.dart`

- [x] T6. Add logging for cancel requests and abort outcomes

  **What to do**: 
  - Add logging to `cancelRealismEval()`:
    - Log "Realism eval cancel requested" when method is called
    - Log "abortGeneration invoked" before calling abort
    - Log "abortGeneration completed" after abort
    - Log "abortGeneration failed: $e" if exception occurs
  - Add logging to `_fireLLMEval` streaming loop:
    - Log "streaming terminated via cancel" when exit path is taken
  - All logs should use `debugPrint()` with `[Realism:Cancel]` prefix

  **Must NOT do**: 
  - Do not change any existing logging
  - Do not add verbose logging that impacts performance
  - Do not add logging to production paths (only debugPrint)

  **Recommended Agent Profile**:
  - Category: `writing` - Reason: Documentation and logging additions
  - Skills: [`dart`, `flutter`, `logging`] - Why: Must understand logging patterns
  - Omitted: [] - Why: No external dependencies needed

  **Parallelization**: Can Parallel: YES | Wave 4 | Blocks: T7 | Blocked By: T2, T3, T4, T5

  **References**:
  - Pattern: `lib/services/chat_service.dart:7270` - Reference existing logging pattern in eval calls
  - Pattern: `lib/services/chat_service.dart:6876` - Reference retry logging pattern

  **Acceptance Criteria**:
  - [ ] All cancel requests logged with `[Realism:Cancel]` prefix
  - [ ] Abort invocation and completion logged
  - [ ] Exception logging for abort failures
  - [ ] Streaming termination logged when exit path taken
  - [ ] `flutter analyze lib/services/chat_service.dart` passes with no errors

  **QA Scenarios**:
  ```
  Scenario: Cancel request logged
    Tool: Bash
    Steps: grep "Realism:Cancel" lib/services/chat_service.dart | head -5
    Expected: Shows all cancel-related log statements
    Evidence: .sisyphus/evidence/task-T6-logs.txt

  Scenario: Abort outcomes logged
    Tool: Bash
    Steps: grep -E "abortGeneration.*invoked|abortGeneration.*completed|abortGeneration.*failed" lib/services/chat_service.dart
    Expected: Shows abort outcome logs
    Evidence: .sisyphus/evidence/task-T6-abort.txt
  ```

  **Commit**: YES | Message: `chore: add logging for cancel requests and abort outcomes` | Files: `lib/services/chat_service.dart`

- [x] F1. Plan Compliance Audit — oracle
- [x] F2. Code Quality Review — unspecified-high
- [x] F3. Real Manual QA — unspecified-high (+ playwright if UI)
- [x] F4. Scope Fidelity Check — deep

## Final Verification Wave (MANDATORY — after ALL implementation tasks)
> 4 review agents run in PARALLEL. ALL must APPROVE. Present consolidated results to user and get explicit "okay" before completing.
> **Do NOT auto-proceed after verification. Wait for user's explicit approval before marking work complete.**
> **Never mark F1-F4 as checked before getting user's okay.** Rejection or user feedback -> fix -> re-run -> present again -> wait for okay.
- [x] F1. Plan Compliance Audit — oracle
- [x] F2. Code Quality Review — unspecified-high
- [x] F3. Real Manual QA — unspecified-high (+ playwright if UI)
- [x] F4. Scope Fidelity Check — deep

## Commit Strategy
- Separate commits per task
- Follow existing commit message format: `type(scope): desc`
- Files: `lib/services/chat_service.dart`, `lib/ui/pages/chat_page.dart`

## Success Criteria
- Escape hatch works for both regular realism evals and greeting evals
- After cancel, drop back to chat interface for manual regenerate
- Cancel button only appears when realism evaluation is actively streaming
- State reset: `_realismEvalStreamText = ''`, `_pendingRealismMetadata = null`
- Logging shows cancel requests and abort outcomes
- No automatic restart after cancel (user must manually regenerate)
- No regression in existing functionality
- `flutter analyze` passes with no errors
