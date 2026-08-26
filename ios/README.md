# Voxa iOS/iPadOS

The iPhone and iPad app will live under this directory.

The TestFlight workflow is already present, but it skips until an Xcode project or workspace exists under `ios/`.

Expected repository secrets before enabling TestFlight uploads:

- `VOXA_APP_IDENTIFIER`
- `VOXA_APPLE_ID`
- `VOXA_ITC_TEAM_ID`
- `VOXA_TEAM_ID`
- `MATCH_GIT_URL`
- `MATCH_PASSWORD`
- `MATCH_KEYCHAIN_PASSWORD`
- `MATCH_GIT_BASIC_AUTHORIZATION`
- `APP_STORE_CONNECT_API_KEY_ID`
- `APP_STORE_CONNECT_API_ISSUER_ID`
- `APP_STORE_CONNECT_API_KEY_BASE64`
- `VOXA_XCODE_PROJECT` or `VOXA_XCODE_WORKSPACE`
- `VOXA_XCODE_SCHEME`
