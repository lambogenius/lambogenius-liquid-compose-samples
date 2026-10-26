# 07 · Recipes

One Logic App, one workflow per feature. Each is small enough to copy into your own project.

| Workflow | Template | What it shows |
|---|---|---|
| `liquid-essentials` | `essentials.liquid` | `assign`, `capture`, `if` / `elsif`, `case` / `when`, `for` with `limit`, `offset` and `reversed`, `forloop`, and the common filters (`Map`, `Join`, `Split`, `Truncate`, `Replace`, `Plus`, `Times`, `DividedBy`, `Round`) |
| `parameters` | `parameters.liquid` | values passed in `parameters` from an app setting, workflow parameters (`parameters.json`), a trigger header, the query string and expressions |
| `partials` | `partials-demo.liquid` | one partial used twice, and a partial that includes another |
| `template-versions` | `v1/receipt.liquid`, `v2/receipt.liquid` | the same `templateName` through two connections whose `templateFolder` is `v1` and `v2` |
| `xpath` | `xpath.liquid` | XPath on XML: attributes, positions, predicates, two namespaces, CDATA, and what you get when nothing matches |
| `tojson` | `tojson.liquid` | how `ToJson` writes strings, numbers, Booleans, null, arrays and objects |
| `error-handling` | `errors/*.liquid` | nine ways an action fails, and how a workflow reads the error code |

## Run it

See the [prerequisites](../README.md#prerequisites).

```powershell
./run.ps1      # Azurite, the GetCustomerName Function on 7075, the Logic App on http://localhost:7107
./demo.ps1     # in a second window: every recipe, checked
./send.ps1 xpath messages/shipment.xml
./send.ps1 parameters messages/order.json -Tenant contoso -Mode test
./send.ps1 error-handling messages/error-case.json -Case unknown-filter
```

## Notes on the recipes

**Filters are capitalized.** DotLiquid writes `Upcase`, `Default` and `Join`, not `upcase`. An unknown or lowercase
filter fails the action with `UnknownFilter` instead of being ignored.

**Whitespace.** A dash on the right of a tag (`-%}`) removes the whitespace and line break after it. Put line breaks
you want in the output before a tag, or in a variable (sample 03 passes `"\r\n"` as a parameter).

**Parameters.** A template sees `content` and `parameters`, nothing else. Pass what it needs from the workflow:

```json
"parameters": {
  "environment": "@appsetting('ENVIRONMENT_NAME')",
  "region": "@parameters('region')",
  "limits": "@parameters('limits')",
  "tenant": "@triggerOutputs()?['headers']?['x-tenant']",
  "mode": "@triggerOutputs()?['queries']?['mode']",
  "receivedAt": "@utcNow()"
}
```

Objects stay objects: the template reads `parameters.limits.discountPercent`. Don't pass secrets this way: action
inputs are kept in the run history.

**Template versions.** A connection's `templateFolder` is added to the template path. Two connections over one
template root let a workflow move from `v1/receipt.liquid` to `v2/receipt.liquid` by changing `connectionName`, and
let both run side by side while consumers move over.

**XPath.**
- `XmlValue` returns the first match, or `null`.
- `XmlValues` returns every match, or `[]`.
- Both accept node selections only: elements, attributes and text. Functions that return a number or a string,
  such as `count()`, are refused; use `XmlValues: '…' | Size`.
- Every namespace needs a prefix in `xmlNamespaces`, the default namespace too.

**ToJson.** Write values as `{{ value | ToJson }}`, never `"{{ value }}"`, which breaks on the first quote,
backslash or line break. `ToJson` writes:
- numbers, including a 20-digit integer, exactly as they arrived;
- `null` for null and for missing fields;
- arrays and objects as JSON.

## Error handling

The `error-handling` workflow takes `?case=<name>` and runs `errors/<name>.liquid`. Every case fails; the workflow
catches the failure (`runAfter: Failed, TimedOut`) and answers with the error code:

```json
"code": "@first(split(last(split(string(outputs('Compose_using_Liquid')?['body']?['message']), 'error message ''')), ':'))"
```

The connector's message starts with a stable error code, such as `FunctionHttpFailed: …`. The runtime wraps that
message in `The service provider action failed with error code '…' and error message '…'`, and the expression takes
the code back out.

| Case | Error code | Action status |
|---|---|---|
| `template-missing` | `TemplateNotFound` | 404 |
| `syntax-error` | `TemplateSyntaxError` | 400 |
| `unknown-filter` | `UnknownFilter` | 400 |
| `invalid-json-output` | `InvalidOutputJson` | 400 |
| `scripts-disabled` | `ScriptsDisabled` (the action has no `enableScripts`) | 403 |
| `helper-throws` | `ScriptExecutionFailed` | 400 |
| `slow-helper` | `TransformationTimeout` (deadline 5 s; the worker process is stopped) | 400 |
| `function-not-allowed` | `FunctionNotAllowed` (the alias isn't in `allowedFunctionAliases`) | 403 |
| `unknown-customer` | `FunctionHttpFailed` (the Function answered 404) | 424 |

**The deadline includes compiling.** `timeoutSeconds` covers the queue, compiling the C# block, rendering and Function
calls. The first run of a template with C# compiles it, which can take a few seconds on a fresh worker; later runs use
the compiled copy. Leave room for that: only `slow-helper` gets 5 seconds, every other case 30.
