# Feature Branch Testing

Run these commands from the feature worktree. They copy the ignored local iOS
backend configuration from the primary checkout and derive the federated
credential name from the current branch.

```bash
cd /Users/simonholmes/Projects/Applications/Voxa/.worktrees/language-management-realtime-websocket
./scripts/prepare-feature-branch-test.sh dev
```

The script sets:

- `GITHUB_REF=refs/heads/<branch>`
- `GITHUB_FEDERATED_CREDENTIAL_NAME=github-<branch-with-slashes-replaced>`

It also copies `ios/Voxa/Config/Debug.local.xcconfig` from the primary
checkout. This file is git-ignored and contains `VOXA_API_BASE_URL`; it must
never be committed.

## Azure Pipeline Identity

After logging into Azure and selecting the Voxa subscription, configure the
feature branch's federated identity with the command printed by the script.
The subscription ID must be supplied explicitly when the CLI has no active
account:

```bash
az login
az account set --subscription fe22eeb1-ae19-41df-9b8a-b9fca568253b
AZURE_SUBSCRIPTION_ID=fe22eeb1-ae19-41df-9b8a-b9fca568253b \
GITHUB_REF=refs/heads/feature/language-management-realtime-websocket \
GITHUB_FEDERATED_CREDENTIAL_NAME=github-feature-language-management-realtime-websocket \
./scripts/setup-azure-auth-for-pipeline.sh dev
```

This bootstraps or updates the branch-specific Azure federated credential. It
does not deploy application code. Run the backend deployment workflow after
the feature branch is pushed. Infrastructure only needs redeployment when
the Bicep/bootstrap configuration or branch federated credential changes.
