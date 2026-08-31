using Azure;
using Azure.Data.Tables;
using Voxa.Infrastructure.Persistence;

namespace Voxa.Infrastructure.Tests;

public sealed class AzureRefreshSessionTableTests
{
    [Fact]
    public async Task DeleteTreatsMissingEntityAsSuccess()
    {
        var table = new AzureRefreshSessionTable(new MissingEntityTableClient());

        await table.DeleteAsync("refresh", "missing-token", CancellationToken.None);
    }

    private sealed class MissingEntityTableClient : TableClient
    {
        public override Task<Response> DeleteEntityAsync(
            string partitionKey,
            string rowKey,
            ETag ifMatch = default,
            CancellationToken cancellationToken = default)
        {
            throw new RequestFailedException(404, "The specified entity does not exist.");
        }
    }
}
