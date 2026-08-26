# Voxa Azure Infrastructure

Voxa starts with a deliberately small Azure footprint:

- Azure Functions Flex Consumption for the backend API and OpenAI Realtime client-secret issuance.
- Azure Storage for Function runtime and deployment package storage.
- Azure Key Vault with RBAC for server-side secrets.
- Application Insights and Log Analytics with short retention and a daily cap.
- Optional Cosmos DB Serverless, disabled by default until the first durable-store cost decision is made.

Container Apps and Azure Container Registry are intentionally not part of the MVP baseline. Add them only if the PRD upgrade triggers are met.

## Required GitHub Environment Variables

Configure these as GitHub environment variables for `dev`, `staging`, and `production` as needed:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_LOCATION`
- `AZURE_RESOURCE_GROUP`

Configure this as a GitHub environment secret:

- `OPENAI_API_KEY`

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
