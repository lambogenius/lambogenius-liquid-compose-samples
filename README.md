# Compose using Liquid: samples

Complete, runnable Azure Logic Apps (Standard) projects that use **Compose using Liquid**, the Lambogenius
built-in action that renders Liquid templates: JSON or XML in, JSON or any text out. Beyond standard Liquid, it adds
C# helper methods in the template, calls to Azure Functions, XPath on XML input and safe JSON output.

Each sample folder holds:
- a NuGet-based Logic App project with its workflows and templates;
- a stand-in for every system it talks to (Python, standard library only);
- test messages;
- `run.ps1`, which starts everything, and `demo.ps1`, which runs each step and checks the result.

Documentation: <https://docs.lambogenius.com/liquid-compose>

| Sample | What it shows | Modes |
|---|---|---|
| [01 · Basics](01-basics) | One workflow per mode, a C# helper, a Function lookup, a partial and an inline template | all four |
| [02 · Orders to ERP](02-orders-to-erp) | Webshop JSON and partner XML orders mapped to one ERP format, a printable pick list, an XML acknowledgement. Retries, duplicates and outages | JSON → JSON, XML → JSON, JSON → text |
| [03 · CSV and bank files](03-csv-export) | Orders to an RFC 4180 CSV for finance, and payments to a bank's 80-column fixed-width file, checked byte for byte | JSON → text |
| [04 · Supplier invoice](04-invoice-xml-to-json) | A UBL 2.1 invoice (default namespace plus `cac` and `cbc`) to the JSON an accounts-payable API takes; attributes, required fields, rejections | XML → JSON |
| [05 · Shipping email](05-html-notification) | An HTML email (with partials) and a plain-text alternative from one event, in English or French; everything from the order HTML-escaped | JSON → text (HTML), JSON → JSON |
| [06 · SOAP service](06-soap-envelope) | A SOAP 1.1 request for a legacy CRM built from JSON, and its response or SOAP Fault read back into JSON | JSON → text (XML), XML → JSON |
| [07 · Recipes](07-recipes) | One feature per workflow: Liquid essentials, parameters, partials, template versions, XPath, `ToJson`, and every kind of failure with its error code | JSON → JSON, XML → JSON |
| [08 · Workflow variables](08-workflow-variables) | Variables of every type as template parameters, a typed result back into variables, a For each that collects results in variables, a variable that picks the template, and a Switch on a template's answer | JSON → JSON, JSON → text |

## Prerequisites

1. **Windows** (the samples are tested on Windows 11) with:
   - the [.NET SDK 8](https://dotnet.microsoft.com/download/dotnet/8.0);
   - [Azure Functions Core Tools 4](https://learn.microsoft.com/azure/azure-functions/functions-run-local): `npm install -g azure-functions-core-tools@4`;
   - [Azurite](https://learn.microsoft.com/azure/storage/common/storage-use-azurite): `npm install -g azurite`;
   - [PowerShell 7](https://aka.ms/powershell);
   - [Python 3](https://www.python.org/downloads/) for the stand-in systems (samples 02 and 04–06).
2. **The Compose using Liquid package.** Sign in at <https://lambogenius.com/app/downloads/liquid-compose>, download
   `Lambogenius.LiquidCompose.LogicApps.0.1.0.nupkg`, and save it in [`packages/`](packages). Every sample's project
   finds it there through the repository's `nuget.config`.
3. **No license to run the samples.** Under Azure Functions Core Tools (`func start`, which `run.ps1` uses) the action
   runs without one and logs a reminder. Anywhere else, Azure included, it needs a license token: a free
   [developer license](https://lambogenius.com/app/licensing?start=liquid-compose-developer) for development and
   testing, or the [30-day trial](https://lambogenius.com/app/licensing?start=liquid-compose-trial) or a paid license
   for production.

Every sample starts the same way:

```powershell
cd 02-orders-to-erp
./run.ps1          # builds the project, starts Azurite and the stand-ins, then the Logic App
# in a second window:
./demo.ps1         # every step, checked; exits with 1 when a check fails
```

Clone to a short path, such as `C:\src\liquid-samples`. The builds write files up to about 165 characters below the
clone folder. A clone folder path longer than about 90 characters exceeds the Windows 260-character path limit. The
build then fails, for the Azure Function with `MSB3030: Could not copy the file …
Microsoft.Azure.Functions.Worker.Extensions.dll`.

The first build restores NuGet packages and takes a few minutes. The Logic App is ready when its log shows
`Host lock lease acquired`. **Ctrl+C** stops it and everything `run.ps1` started.

Each sample has its own port, so several can run at once:

| Sample | Logic App | Stand-in | Function |
|---|---|---|---|
| 01 | 7101 | | 7075 |
| 02 | 7102 | 8102 | 7075 |
| 03 | 7103 | | |
| 04 | 7104 | 8104 | |
| 05 | 7105 | 8105 | |
| 06 | 7106 | 8106 | |
| 07 | 7107 | | 7075 |
| 08 | 7108 | | |

Samples 01, 02 and 07 call the `GetCustomerName` Azure Function ([`shared/functions/GetCustomerName`](shared/functions/GetCustomerName)),
which `run.ps1` builds and starts on port 7075. All samples share one Azurite on ports 10000–10002. If another program
holds one of those ports (VS Code sometimes holds 10001), `run.ps1` starts Azurite on free ports and points the
Logic App at them.

## How a sample is put together

| File | What it is |
|---|---|
| `LogicApp.csproj` | references `Microsoft.Azure.Workflows.WebJobs.Extension` 1.170.91 and `Lambogenius.LiquidCompose.LogicApps`. It also removes `extensionBundle` from the `host.json` the runtime uses, so the host loads the built-in connectors from this project's packages |
| `connections.json` | the `lamboLiquidCompose` connection. Keep `"templateFolder": ""`: the runtime refuses an empty `parameterValues` |
| `local.settings.sample.json` | app settings; `run.ps1` copies it to `local.settings.json` (ignored by git) on the first run |
| `functions.json` | the Function registry, in samples that call Functions |
| `Artifacts/LiquidTemplates/` | the templates the workflows name with `templateSource: deployed` |
| `<workflow>/workflow.json` | the workflows |
| `messages/` | test messages |
| `backends/app.py` | the stand-in systems |

A Compose using Liquid action in a workflow:

```json
"Map_the_order": {
  "type": "ServiceProvider",
  "runAfter": {},
  "inputs": {
    "parameters": {
      "inputFormat": "json",
      "outputFormat": "json",
      "content": "@triggerBody()",
      "templateSource": "deployed",
      "templateName": "webshop-to-erp.liquid",
      "parameters": { "defaultCurrency": "@appsetting('DEFAULT_CURRENCY')" },
      "enableScripts": true,
      "allowedFunctionAliases": [ "GetCustomerName" ],
      "timeoutSeconds": 30
    },
    "serviceProviderConfiguration": {
      "connectionName": "lamboLiquidCompose",
      "operationId": "ComposeLiquid",
      "serviceProviderId": "/serviceProviders/lamboLiquidCompose"
    },
    "retryPolicy": { "type": "none" }
  }
}
```

In JSON mode, `body('Map_the_order')?['result']` is the parsed value, so later actions can use its fields. In text
mode, it is the text. `retryPolicy` goes **inside** `inputs`: placed next to `inputs`, it is ignored and the runtime's
default policy applies.

## Running in Azure

The samples run locally. To deploy one:
1. Run `dotnet publish -c Release`.
2. Zip-deploy the publish folder to a Logic App (Standard) on a **Windows** plan (WS1 or larger).
3. Set the app settings from `local.settings.sample.json`, with real endpoints, and set `LAMBOGENIUS_LICENSE` to a
   license token from the [Licensing page](https://lambogenius.com/app/licensing). Without it, the action fails with
   403 `LicenseRequired`.
4. Move Function calls to HTTPS with `FunctionKey` or `ManagedIdentity` authentication, and remove
   `LiquidCompose__Development__AllowLocalhostHttp`.

See [Deployment](https://docs.lambogenius.com/liquid-compose/deployment).

## Support

Questions and bug reports: <hello@lambogenius.com>. The Compose using Liquid package is not part of this repository;
its license terms are on <https://lambogenius.com/products/liquid-compose>.
