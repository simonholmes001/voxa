Copilot 2 — MVP Acceleration (local worktree)
Branch: feature/mvp-acceleration-copilot2
Base: main

Scope (Copilot 2 responsibilities)
- Repair Home/Today: resume, profile display, offline state, active "Start talking" flow, retry and sign-in recovery. Add tests for loading/success/empty/offline/unauth.
- Talk UX completion: connection lifecycle states, mic & remote audio verification on device, use selected language profile (no hard-coded settings), device-test instructions, automated state tests.
- Implement Learn, Review, More pages: navigable, explicit loading/empty/error/populated states. No placeholders.

Constraints / Rules
- Do NOT push, open PRs, or merge without explicit approval.
- Do not invent backend API shapes. Coordinate with Copilot 1 and wait for multi-profile contract before wiring network code.
- Use clearly isolated fakes/protocols for any profile/settings dependencies until contracts exist.
- Use assigned label: mvp-acceleration. Record issue mappings here (do not invent numbers).

Priority (per user):
1. Home/Today reliability
2. Talk UX and selected-profile wiring
3. Learn, Review, More

Immediate next steps (local, non-pushing):
- Create TDD-friendly scaffolding and tests for Home resume and active-profile plumbing (fakes + protocols).
- Add Talk UX state tests and device-test checklist placeholder.
- Open a local TODO list mapping planned commits to mvp-acceleration tasks (no issue numbers until provided).

Coordination notes
- Waiting for backend multi-profile API contract from Codex/Copilot 1. Will pause integration at that boundary and switch fakes to real interfaces after contract is available.

If this is correct, reply with a one-word "Proceed" and I will create the initial TDD scaffold (tests + fake protocols) in this worktree. If you want different ordering or extra constraints, tell me now.