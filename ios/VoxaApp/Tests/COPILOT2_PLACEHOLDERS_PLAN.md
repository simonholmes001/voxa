Learn/Review/More placeholders TDD plan

Objectives:
- Provide minimal views that expose loading/empty/error/populated states so device testing can exercise navigation and basic UX.

Tests to add:
1) test_learn_placeholder_shows_loading_then_empty
2) test_review_placeholder_shows_error_state
3) test_more_placeholder_navigation_hook

Notes:
- Keep placeholders lightweight. They should not depend on profile contract or backend until those APIs are agreed.
- Implement real content in follow-up iterations once backend contracts are available.
