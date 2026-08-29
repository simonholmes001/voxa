# Voxa Backend

The backend is a .NET modular monolith deployed first on Azure Functions Flex Consumption.

The initial skeleton targets `net9.0` so it can be built and tested with the SDK currently installed locally. CI uses the .NET 10 SDK and can still build this target framework. Move the target framework to `net10.0` once the local developer SDK baseline is upgraded.

## Project Layout

- `src/Voxa.Domain`: domain identifiers, learner state, and domain exceptions.
- `src/Voxa.Application`: use cases, repository ports, and mobile-facing DTO contracts.
- `src/Voxa.Infrastructure`: adapter implementations for persistence and other infrastructure concerns.
- `src/Voxa.Api`: HTTP/API boundary, request validation, response/error shapes, and configuration validation.
- `tests/*`: unit tests by layer.

## Local Tests

```bash
DOTNET_CLI_HOME=/tmp/voxa-dotnet dotnet test backend/Voxa.sln --verbosity minimal
```

Tests do not require deployed Azure resources.
