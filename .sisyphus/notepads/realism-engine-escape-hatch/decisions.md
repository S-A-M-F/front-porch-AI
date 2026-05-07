## Design decisions
- Implemented cancelRealismEval() to provide an explicit cancellation path for Realism evaluations in ChatService.
- Chosen simple, explicit state reset path after abort attempt to avoid side effects from partial evaluations.
- No automatic full-flow restart is triggered after cancellation to preserve current session state and user context.
- Logging includes: Realism eval cancel requested and abortGeneration invoked; abort failures are captured and logged, but do not crash the cancellation flow.
