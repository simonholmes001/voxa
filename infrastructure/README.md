# Voxa Azure Infrastructure

Voxa starts with a deliberately small Azure footprint:

- Azure Functions Flex Consumption for the backend API and OpenAI Realtime client-secret issuance.
- Azure Storage for Function runtime state, reached privately by the backend.
- A separate minimal deployment artifact storage account for Flex Consumption Function packages. It has public network reachability for GitHub-hosted deployment tooling, but disables blob public access and shared keys.
- Azure Key Vault with RBAC for server-side secrets, reached privately by the backend.
- One small virtual network with separate subnets for Function outbound integration and private endpoints, deployed to a dedicated network resource group.
- Private DNS zones, private endpoints, and generated private endpoint NICs in the network resource group.
- Application Insights and Log Analytics with short retention and a daily cap.
- Optional Cosmos DB Serverless, disabled by default until the first durable-store cost decision is made.

Container Apps and Azure Container Registry are intentionally not part of the MVP baseline. Add them only if the PRD upgrade triggers are met.

The Function App keeps public HTTPS ingress enabled for the mobile MVP so iPhone and iPad clients can reach the backend without adding a paid public edge. Data-plane resources default to public network access disabled. If Function ingress must also become private, set `enablePrivateFunctionIngress=true` and add an explicit public access pattern such as Front Door, API Management, App Gateway, or VPN.

Flex Consumption code packages are stored separately from runtime data because GitHub-hosted deployment tooling cannot reach a storage account that is fully locked behind private endpoints. The deployment artifact account stores only Function release packages; learner/session runtime data remains in the private runtime storage account. The deployment artifact account still uses managed identity/RBAC, disables shared key access, and disables anonymous blob access.

## One-Time Azure Bootstrap

The GitHub Actions deployment identity is also managed through Bicep. Run the bootstrap deployment once from an Azure CLI session that has permission to create resource groups, managed identities, federated credentials, and role assignments:

```bash
az login
az account set --subscription "<subscription-id>"

AZURE_SUBSCRIPTION_ID="<subscription-id>" \
./scripts/setup-azure-auth-for-pipeline.sh dev
```

The bootstrap deployment creates:

- `rg-voxa-pipeline-identity`
- `id-voxa-github-actions`
- GitHub OIDC federated credential for `refs/heads/main` using GitHub's immutable owner/repository subject format
- `rg-voxa-network-dev`
- `rg-voxa-dev`
- `Contributor` and `Private DNS Zone Contributor` assignments for the pipeline identity on `rg-voxa-network-dev`
- `Contributor` and `Role Based Access Control Administrator` assignments for the pipeline identity on `rg-voxa-dev`

Copy the deployment outputs into the repository secrets listed below.

The network template preserves the original workload resource naming seed so moving the VNet and private DNS zones into `rg-voxa-network-dev` does not change the expected Azure resource names. Existing environments still need an explicit migration decision for old network resources that already exist in `rg-voxa-dev`; this repository does not hide cleanup or destructive moves in the deployment path.

Private endpoint subnet assignment is immutable in Azure. During the split from workload-owned networking to `rg-voxa-network-dev`, private endpoints are deployed from a separate network-scoped Bicep template after workload resources exist. This places the private endpoints and their generated NICs in `rg-voxa-network-dev`. Old private endpoints and NICs in `rg-voxa-dev` should be removed only through an explicit cleanup PR/runbook after the split deployment succeeds.

Pull request infrastructure validation intentionally runs local guard tests and Bicep lint only. Azure-authenticated deployment runs after the repository secrets exist.

## Required Repository Secrets

Configure these as GitHub repository secrets:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_LOCATION`
- `AZURE_RESOURCE_GROUP`
- `AZURE_NETWORK_RESOURCE_GROUP`
- `OPENAI_API_KEY`
- `APP_SESSION_SIGNING_KEY`
- `APPLE_CLIENT_ID`
- `APPLE_TEAM_ID`
- `APPLE_KEY_ID`
- `APPLE_PRIVATE_KEY`

Do not configure Azure client secrets. The deployment workflows use GitHub OIDC with a user-assigned managed identity.

## Local Validation

```bash
AZURE_CONFIG_DIR=/tmp/voxa-azure ./infrastructure/scripts/validate.sh dev --lint-only
```

Full validation and what-if require Azure login:

```bash
AZURE_CONFIG_DIR=/tmp/voxa-azure \
./infrastructure/scripts/validate.sh dev --what-if
```
