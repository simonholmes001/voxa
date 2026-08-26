# Voxa Azure Infrastructure

Voxa starts with a deliberately small Azure footprint:

- Azure Functions Flex Consumption for the backend API and OpenAI Realtime client-secret issuance.
- Azure Storage for Function runtime and deployment package storage, reached privately by the backend.
- Azure Key Vault with RBAC for server-side secrets, reached privately by the backend.
- One small virtual network with separate subnets for Function outbound integration and private endpoints.
- Private DNS zones and private endpoints for Storage, Key Vault, and optional Cosmos DB.
- Application Insights and Log Analytics with short retention and a daily cap.
- Optional Cosmos DB Serverless, disabled by default until the first durable-store cost decision is made.

Container Apps and Azure Container Registry are intentionally not part of the MVP baseline. Add them only if the PRD upgrade triggers are met.

The Function App keeps public HTTPS ingress enabled for the mobile MVP so iPhone and iPad clients can reach the backend without adding a paid public edge. Data-plane resources default to public network access disabled. If Function ingress must also become private, set `enablePrivateFunctionIngress=true` and add an explicit public access pattern such as Front Door, API Management, App Gateway, or VPN.

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
- `rg-voxa-dev`
- `Contributor` assignment for the pipeline identity on `rg-voxa-dev`

Copy the deployment outputs into the repository secrets listed below.

Pull request infrastructure validation intentionally runs local guard tests and Bicep lint only. Azure-authenticated deployment runs after the repository secrets exist.

## Required Repository Secrets

Configure these as GitHub repository secrets:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_LOCATION`
- `AZURE_RESOURCE_GROUP`
- `OPENAI_API_KEY`

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
