---
"voxa": patch
---

Pre-merge polish across three surfaces:

- **SessionDebriefView renders all four sections even when empty.** Short first sessions used to show only the summary and a big gap before the "recommended next" card because the assessor honestly returned empty lists for recurring mistakes / useful phrases / pronunciation notes. Now each section is always rendered, with a placeholder like *"Nothing to flag this time — try a longer session for more feedback."* No prompt change — the assessor still refuses to invent content.
- **Home progress line surfaces sub-minute practice.** A 30-second session used to display as *"0 of 15 minutes today"*, making it look like nothing was recorded. The label now says *"30 sec today (< 1 min)"* under one minute and *"12 of 15 minutes today"* from one minute onward, and the progress bar advances proportionally on seconds. New `secondsPracticedToday` field flows from `SessionSummary.durationSeconds` through the composition layer.
- **Custom language name auto-capitalises the first letter.** The onboarding target-language "Other…" text field now trims and capitalises the first letter of what the learner types or pastes, so *"russian"* becomes *"Russian"* and *"old norse"* becomes *"Old norse"*. Interior casing is preserved; this is not title-case.
