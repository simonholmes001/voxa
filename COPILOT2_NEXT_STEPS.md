Copilot2 MVP worktree — next steps and checklist

Completed in this iteration:
- Added ProfileProvider & RealtimeTransport test-support types in VoxaRealtime.TestSupport
- Added FakeProfileProvider and FakeRealtimeTransport
- Added XCTest cases exercising resume and transport lifecycle behaviors
- Created test-plan docs for Home resume, Talk UX, and placeholders
- Committed all changes to feature/mvp-acceleration-copilot2 worktree (local only)

Immediate next tasks:
- Wire existing HomeViewModel to accept ProfileProvider via initializer (TDD) and add failing tests to drive implementation.
- Add TalkSessionViewModel tests that inject FakeRealtimeTransport to fully exercise UI state transitions.
- Prepare device-test checklist (requires VOXA_API_BASE_URL and physical device).

Blockers / constraints:
- Do not wire real networking until backend multi-profile API contract is published.
- Do not push or open PRs without explicit approval.

When ready to proceed to integration (requires Codex/Copilot1):
1. Obtain agreed ProfileService contract and endpoint.
2. Replace FakeProfileProvider with real provider behind the protocol.
3. Run device tests with VOXA_API_BASE_URL set and verify WebRTC SDP flow on iPhone/iPad.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>