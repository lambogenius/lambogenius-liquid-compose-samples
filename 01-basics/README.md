# 01 · Basics

One HTTP-triggered workflow per thing to learn. Each runs one Compose using Liquid action and returns the result.

| Workflow | Mode | What it shows | Request |
|---|---|---|---|
| `order-to-sales-order` | JSON → JSON | a C# helper (`CallCSharp`), an Azure Function lookup (`CallFunction`), action parameters, and typed output that a later action reads | `requests/order-to-sales-order.json` |
| `plain-order-summary` | JSON → JSON | plain Liquid, a total with `Plus`, and a partial (`{% include 'partials/line.liquid' %}`) | `requests/plain-order-summary.json` |
| `order-to-text` | JSON → text | exact text output, whitespace kept | `requests/order-to-text.json` |
| `xml-order-to-json` | XML → JSON | `XmlValue` and `XmlValues` with a namespace prefix | `requests/xml-order-to-json.xml` |
| `xml-order-to-text` | XML → text | XML to plain text | `requests/xml-order-to-text.xml` |
| `inline-csharp-helpers` | JSON → JSON | a template inside the workflow definition (`templateSource: inline`) with `string`, `double` and `bool` helpers | `requests/inline-csharp-helpers.json` |

## Run it

See the [prerequisites](../README.md#prerequisites).

```powershell
./run.ps1      # Azurite, the GetCustomerName Function on 7075, the Logic App on http://localhost:7101
./demo.ps1     # in a second window: every workflow, checked
./send.ps1 order-to-sales-order
./send.ps1 xml-order-to-text -File my-order.xml
```

`order-to-sales-order` answers:

```json
{
  "salesOrder": {
    "orderNumber": "ORD-100",
    "customerName": "Acme Supplies",
    "currency": "CAD",
    "lines": [ { "sku": "ABC-01", "quantity": 2 }, { "sku": "XYZ-02", "quantity": 1 } ]
  },
  "orderNumber": "ORD-100",
  "firstSku": "ABC-01",
  "templateHash": "ff5eeaed…",
  "functionCallCount": 1
}
```

- `customerName` comes from the Function. Try `"customerId": "C200"` (Globex Corporation), or `"C999"`: the
  Function answers 404, the action fails with `FunctionHttpFailed`, and the workflow returns HTTP 500 with the
  error.
- `orderNumber` and `firstSku` are read after the Liquid action, by a Compose action and by the Response:
  `@body('Compose_using_Liquid')?['result']?['lines']?[0]?['sku']`. In JSON mode, `result` is the parsed value,
  not a string.

## The template

`Artifacts/LiquidTemplates/order-to-sales-order.liquid`:

```liquid
{% csharp %}
public string NormalizeCode(string value)
{
    return (value ?? "").Trim().ToUpperInvariant();
}
{% endcsharp %}
{
  "orderNumber": {{ content.order.number | CallCSharp: 'NormalizeCode' | ToJson }},
  "customerName": {{ content.order.customerId | CallFunction: 'GetCustomerName' | ToJson }},
  "currency": {{ parameters.currency | ToJson }},
  "lines": [
    {% for line in content.order.lines %}
    {
      "sku": {{ line.sku | CallCSharp: 'NormalizeCode' | ToJson }},
      "quantity": {{ line.quantity | ToJson }}
    }{% unless forloop.last %},{% endunless %}
    {% endfor %}
  ]
}
```

- `content` is the action's `content` input; `parameters` is its `parameters` input.
- The `{% csharp %}` block comes first. Its public methods take and return one `string`, `double` or `bool`. The
  action needs `"enableScripts": true`, and the app needs `LiquidCompose__AllowScripts=true`.
- `CallFunction: 'GetCustomerName'` posts `{"value": "C100"}` to the Function named in `functions.json`. The action
  must list the alias in `allowedFunctionAliases`.
- `ToJson` writes each value as valid JSON, so no quotes around `{{ }}`.
