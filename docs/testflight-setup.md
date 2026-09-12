# TestFlight setup

End-to-end guide to turn on the `main` → tag → TestFlight pipeline
(`.github/workflows/ios-testflight.yml`) for voxa AI.

## Pipeline recap

- A merge to `main` with `.changeset/*.md` files triggers
  `.github/workflows/release.yml`, which computes the next semver
  bump, creates a `v<semver>` tag, and pushes it to the origin.
- That tag push triggers `.github/workflows/ios-testflight.yml`,
  which:
  - Resolves the marketing version by stripping the `v` prefix
    from the tag (`v0.20.0` → `0.20.0`).
  - Uses `github.run_number` as the CFBundleVersion (build number)
    — monotonic across runs, guaranteed unique.
  - Uses fastlane `match` for signing (certs stored in a private
    git repo).
  - Uploads via `pilot` (App Store Connect API key auth).
- Manual dispatch is also available for hotfix re-uploads.

## Prerequisites

- Apple Developer account (paid) — team id `2PA85SU4UQ` on Simon's
  setup.
- The **voxa AI** app record in App Store Connect (already created).
- A **private GitHub repo** for `match` to store certificates in.
  Suggested name: `simonholmes001/voxa-certificates`. Empty at
  creation is fine; `match` populates it.
- An **App Store Connect API key** with the Developer role. Create
  one at https://appstoreconnect.apple.com/access/api → **Keys**
  tab → **+**. Give it the "Developer" role (not "Admin"). Download
  the `AuthKey_XXXX.p8` file — it is offered exactly **once**.

## One-time local setup

### 1. Initialise `match` (populates the private cert repo)

From `ios/`:

```bash
bundle install
```

Then, with your Apple ID logged in to Xcode and the private cert
repo created:

```bash
export VOXA_APP_IDENTIFIER="com.simonholmes.voxa"
export VOXA_APPLE_ID="<your apple id email>"
export VOXA_ITC_TEAM_ID="<App Store Connect team id>"
export VOXA_TEAM_ID="2PA85SU4UQ"
export MATCH_GIT_URL="git@github.com:simonholmes001/voxa-certificates.git"
export MATCH_PASSWORD="<a strong passphrase — remember it>"

bundle exec fastlane match appstore
```

Answer the prompts. Fastlane generates a distribution certificate
and an App Store provisioning profile for `com.simonholmes.voxa`,
encrypts them with `MATCH_PASSWORD`, and pushes them to your
private repo. CI reuses these read-only.

### 2. Encode the App Store Connect API key for CI

```bash
base64 -i /path/to/AuthKey_XXXX.p8 | pbcopy
```

The base64 blob is what you paste into
`APP_STORE_CONNECT_API_KEY_BASE64`.

### 3. Prepare a GitHub personal access token for `match`

`match` in CI clones the private cert repo over HTTPS. It needs a
token that can read the repo. Create a fine-grained PAT at
https://github.com/settings/tokens?type=beta with only the private
cert repo selected and `Contents: Read` scope.

Then build the basic-auth string CI uses:

```bash
printf '%s:%s' "simonholmes001" "<the PAT>" | base64 | pbcopy
```

That base64 is `MATCH_GIT_BASIC_AUTHORIZATION`.

## GitHub Actions secrets

Add these under **Settings → Secrets and variables → Actions** on
the `voxa` repo:

| Secret | Value | Where it comes from |
|---|---|---|
| `VOXA_APP_IDENTIFIER` | `com.simonholmes.voxa` | Bundle id |
| `VOXA_APPLE_ID` | your Apple ID email | The account that owns the app |
| `VOXA_ITC_TEAM_ID` | e.g. `123456789` | App Store Connect → Users → your name → Team ID |
| `VOXA_TEAM_ID` | `2PA85SU4UQ` | developer.apple.com → Membership |
| `VOXA_XCODE_SCHEME` | `Voxa` | The `Voxa` scheme in `Voxa.xcodeproj` |
| `VOXA_XCODE_PROJECT` | `Voxa.xcodeproj` | Path relative to `ios/` |
| `MATCH_GIT_URL` | `git@github.com:simonholmes001/voxa-certificates.git` | The private cert repo you created |
| `MATCH_PASSWORD` | the passphrase you chose in step 1 | Encrypts certs in the private repo |
| `MATCH_KEYCHAIN_PASSWORD` | any strong random string | Ephemeral CI keychain — never reused |
| `MATCH_GIT_BASIC_AUTHORIZATION` | the base64 from step 3 | Lets CI clone the private cert repo |
| `APP_STORE_CONNECT_API_KEY_ID` | e.g. `ABCDEF1234` | ASC Access → Keys → the key row |
| `APP_STORE_CONNECT_API_ISSUER_ID` | UUID at the top of the Keys tab | ASC Access → Keys → "Issuer ID" |
| `APP_STORE_CONNECT_API_KEY_BASE64` | the base64 from step 2 | The `.p8` file, encoded |

The workflow refuses to start if any of these are missing — see
`Validate required secrets` in the workflow file.

## First upload

Two paths:

### Path A — one-off manual dispatch (recommended for the very first upload)

There is no `v*` tag yet on `main`. Manually dispatch the workflow
with a starting marketing version:

1. GitHub → Actions → **iOS TestFlight** → **Run workflow**.
2. Marketing version: `0.1.0` (the current `MARKETING_VERSION` in
   `ios/project.yml` — pick any semver you like for the first
   build).
3. Run.

Once the upload completes and TestFlight processing finishes
(~15 min), the build is available for internal testers you add to
the app in App Store Connect.

### Path B — release-driven (steady state)

Merge a PR to `main` with a `.changeset/*.md` file whose
frontmatter includes a bump (`patch` / `minor` / `major`).

- `release.yml` sees the changeset → creates and pushes tag
  `v<next>`.
- `ios-testflight.yml` sees the tag → uploads with
  `MARKETING_VERSION=<next>`.

No manual step required after the initial secret configuration.

## Adding testers (in App Store Connect)

Once the first build finishes processing:

1. **Internal testers** (up to 100, no Beta App Review):
   - App Store Connect → **Users and Access** → invite each
     tester by email with role "Developer" or "App Manager".
     They must accept.
   - Then TestFlight → **Internal Testing** → **+** → create a
     group → assign the build. Testers get an email and install
     via the TestFlight iOS app.
2. **External testers** (up to 10,000, requires Beta App Review
   the first time):
   - TestFlight → **External Testing** → **+** → create a group.
   - Add testers by email or generate a public link.
   - Submit the build for Beta App Review (~24h).

## Troubleshooting

- **"No profiles for `com.simonholmes.voxa` were found"** —
  `match` didn't find profiles in the private repo. Run
  `bundle exec fastlane match appstore --readonly false` locally
  once to seed them.
- **"Authentication credentials are missing"** on `pilot upload` —
  `APP_STORE_CONNECT_API_KEY_BASE64` is malformed. Re-encode with
  `base64 -i AuthKey.p8` (no line breaks on macOS; use
  `base64 --wrap 0` on Linux).
- **Build number rejected as duplicate** — happens if a previous
  upload already used the current `github.run_number` for the same
  marketing version. Bump the marketing version (new changeset →
  new tag) or trigger a fresh workflow run.
- **CI clones cert repo over HTTPS but PAT expired** —
  `MATCH_GIT_BASIC_AUTHORIZATION` needs to be regenerated. Fine-
  grained PATs expire every 12 months by default.
