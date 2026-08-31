using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Voxa.Api.Configuration;

var host = new HostBuilder()
    .ConfigureFunctionsWorkerDefaults()
    .ConfigureServices(services =>
    {
        services.AddVoxaBackendServices();
    })
    .Build();

await host.RunAsync();
