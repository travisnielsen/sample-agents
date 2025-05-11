using DotNetEnv;
using Microsoft.Agents.Builder;
using Microsoft.Agents.Hosting.AspNetCore;
using Microsoft.Agents.Storage;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.SemanticKernel;
using System;
using System.Threading;
using WeatherBot;

WebApplicationBuilder builder = WebApplication.CreateBuilder(args);

Env.Load();

string azureOpenAIKey = Environment.GetEnvironmentVariable("AZURE_OPENAI_API_KEY") ?? string.Empty;
if (string.IsNullOrEmpty(azureOpenAIKey))
    throw new InvalidOperationException("AZURE_OPENAI_API_KEY environment variable is not set.");

string clientSecret = Environment.GetEnvironmentVariable("CLIENT_SECRET") ?? string.Empty;
if (string.IsNullOrEmpty(clientSecret))
    throw new InvalidOperationException("CLIENT_SECRET environment variable is not set.");

string targetPort = Environment.GetEnvironmentVariable("TARGET_PORT") ?? string.Empty;
if (string.IsNullOrEmpty(targetPort))
    throw new InvalidOperationException("TARGET_PORT environment variable is not set.");


if (builder.Environment.IsDevelopment())
{
    builder.Configuration.AddUserSecrets<Program>();
}

builder.Services.AddControllers();
builder.Services.AddHttpClient();

// Register Semantic Kernel
builder.Services.AddKernel();

// Register the AI service of your choice. AzureOpenAI and OpenAI are demonstrated...
if (builder.Configuration.GetSection("AIServices").GetValue<bool>("UseAzureOpenAI"))
{
    builder.Services.AddAzureOpenAIChatCompletion(
        deploymentName: builder.Configuration.GetSection("AIServices:AzureOpenAI").GetValue<string>("DeploymentName"),
        endpoint: builder.Configuration.GetSection("AIServices:AzureOpenAI").GetValue<string>("Endpoint"),
        apiKey: azureOpenAIKey);
}
else
{
    builder.Services.AddOpenAIChatCompletion(
        modelId: builder.Configuration.GetSection("AIServices:OpenAI").GetValue<string>("ModelId"),
        apiKey: builder.Configuration.GetSection("AIServices:OpenAI").GetValue<string>("ApiKey"));
}

builder.Services.AddAgentAspNetAuthentication(builder.Configuration);
builder.AddAgentApplicationOptions();
builder.AddAgent<MyAgent>();
builder.Services.AddSingleton<IStorage, MemoryStorage>();
WebApplication app = builder.Build();

app.UseRouting();
app.MapPost("/api/messages", async (HttpRequest request, HttpResponse response, IAgentHttpAdapter adapter, IAgent agent, CancellationToken cancellationToken) =>
{
    await adapter.ProcessAsync(request, response, agent, cancellationToken);
})
    .AllowAnonymous();

app.Urls.Add($"http://*:{targetPort}");
app.Run();