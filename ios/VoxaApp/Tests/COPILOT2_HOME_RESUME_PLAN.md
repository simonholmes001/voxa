Home resume TDD plan (worktree: feature/mvp-acceleration-copilot2)

Goal:
- Add unit tests that reproduce the cross-device resume problem and lock a ProfileProvider contract.

Test cases to create:
1) test_resume_returns_profile: with FakeProfileProvider.resumeResult set, verify HomeViewModel.resumedProfile equals resumeResult after calling resumeFlow()
2) test_resume_defaults_not_overwrite: when resumeResult includes explicit goal/minutes, ensure no defaulting happens in the Home resume flow
3) test_resume_failure_shows_error: when resume throws, HomeViewModel reports a resumable error state

Notes:
- Use the ProfileProvider protocol in production code; tests should inject FakeProfileProvider above.
- Keep network wiring out of these tests; assert only ViewModel state transitions.
- After backend multi-profile contract stabilizes, replace the fake with the real provider in integration branch.
