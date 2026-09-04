Talk UX TDD plan (worktree: feature/mvp-acceleration-copilot2)

Minimum coverage required for Copilot2 MVP:
- Microphone permission flow (granted / denied)
- Connect / disconnect lifecycle
- Transport state mapping: idle -> connecting -> connected; connecting -> failed
- Retry behavior: after failure, retry triggers connect again
- Clear, human-friendly error strings surfaced from transport failures

Suggested tests:
1) test_connect_updates_state_sequence
2) test_connect_failure_sets_error_and_allows_retry
3) test_disconnect_resets_state
4) test_permission_denied_blocks_connect

Notes:
- Use FakeRealtimeTransport to simulate success/failure and timing.
- Keep AVAudioSession and WebRTC code out of unit tests; exercise only ViewModel logic.
