using System.Net;
using System.Text;
using System.Text.Json;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;

namespace Lambogenius.Samples.GetCustomerName;

/// <summary>
/// Looks up a customer name. Request: <c>{"value": "C100"}</c>. Response: 200 <c>text/plain; charset=utf-8</c> with
/// the name, 400 when the body is not a JSON object with a string <c>value</c>, 404 for unknown customers.
/// It is a pure lookup, so repeated calls (workflow retries, loops) are harmless.
/// </summary>
public sealed class GetCustomerNameFunction
{
    private const int MaxRequestBytes = 64 * 1024;

    private static readonly Dictionary<string, string> Customers = new(StringComparer.Ordinal)
    {
        ["C100"] = "Acme Supplies",
        ["C200"] = "Globex Corporation",
        ["C300"] = "Initech \"Québec\" Ltée",
    };

    [Function("GetCustomerName")]
    public async Task<HttpResponseData> Run([HttpTrigger(AuthorizationLevel.Function, "post")] HttpRequestData request)
    {
        var buffer = new byte[MaxRequestBytes + 1];
        var length = 0;
        int read;
        while (length < buffer.Length && (read = await request.Body.ReadAsync(buffer.AsMemory(length))) > 0)
        {
            length += read;
        }

        if (length > MaxRequestBytes)
        {
            return await Text(request, HttpStatusCode.BadRequest, "Request body too large.");
        }

        string? value;
        try
        {
            using var document = JsonDocument.Parse(buffer.AsMemory(0, length));
            value = document.RootElement.ValueKind == JsonValueKind.Object
                && document.RootElement.TryGetProperty("value", out var property)
                && property.ValueKind == JsonValueKind.String
                    ? property.GetString()
                    : null;
        }
        catch (JsonException)
        {
            value = null;
        }

        if (value is null)
        {
            return await Text(request, HttpStatusCode.BadRequest, "Expected a JSON object with a string property 'value'.");
        }

        return Customers.TryGetValue(value, out var name)
            ? await Text(request, HttpStatusCode.OK, name)
            : await Text(request, HttpStatusCode.NotFound, "Unknown customer.");
    }

    private static async Task<HttpResponseData> Text(HttpRequestData request, HttpStatusCode status, string text)
    {
        var response = request.CreateResponse(status);
        response.Headers.Add("Content-Type", "text/plain; charset=utf-8");
        await response.Body.WriteAsync(Encoding.UTF8.GetBytes(text));
        return response;
    }
}
