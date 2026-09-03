Copilot 2 - feature/copilot2-ownership

Starting issue: #81 Fix Talk authenticated Realtime session start path

Goals (TDD-first):
- Add unit tests verifying bearer token/session propagation into RealtimeSessionService
- Fix TalkSessionViewModel/start flow to read current auth state after sign-in
- Improve transport/error messages to make failures diagnosable
- Add placeholder states for Learn/Review/More (follow-on #83)

Next actions:
1. Add failing tests for missing token propagation and session start
2. Implement minimal code changes to satisfy tests
3. Run all iOS unit tests

Branch created from main. Do not push without review (user indicated no auto-push).
