---
"voxa": patch
---

Forces manual signing at gym build time so match's installed profile is actually used.

`ios/project.yml` ships `CODE_SIGN_STYLE=Automatic` (correct for local Xcode work). Match installs a specifically-named manual profile (`match AppStore com.simonholmes.voxa`) into the CI keychain — but with Automatic signing, Xcode ignores the match profile at archive time and gym dies immediately.

Fix: `Fastfile` now passes `CODE_SIGN_STYLE=Manual`, `DEVELOPMENT_TEAM`, `CODE_SIGN_IDENTITY="Apple Distribution"`, and `PROVISIONING_PROFILE_SPECIFIER="match AppStore <app id>"` via `gym`'s `xcargs`. These are build-only overrides — `project.yml` and the pbxproj stay untouched, so local Xcode automatic-signing still works.

Team id and app identifier come from the existing `VOXA_TEAM_ID` and `VOXA_APP_IDENTIFIER` secrets already required by the workflow.
