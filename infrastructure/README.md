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

## Required GitHub Environment Variables

Configure these as GitHub environment variables for `dev`, `staging`, and `production` as needed:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_LOCATION`
- `AZURE_RESOURCE_GROUP`

Configure this as a GitHub environment secret:

- `OPENAI_API_KEY`

Do not configure Azure client secrets. The deployment workflows use GitHub OIDC with a user-assigned managed identity.

## Local Validation

```bash
AZURE_CONFIG_DIR=/tmp/voxa-azure ./infrastructure/scripts/validate.sh dev --lint-only
```

Full validation and what-if require Azure login:

```bash
AZURE_RESOURCE_GROUP=rg-voxa-dev \
AZURE_LOCATION=westeurope \
AZURE_CONFIG_DIR=/tmp/voxa-azure \
./infrastructure/scripts/validate.sh dev --what-if
```
