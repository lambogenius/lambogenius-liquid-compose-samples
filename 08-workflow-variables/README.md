# 08 · Workflow variables

Workflow variables in and out of Compose using Liquid: variables of every type passed to a template as parameters,
a typed result read back into variables, a loop that collects results in variables, a variable that picks the
template, and a Switch on a template's answer.

| Workflow | Template | What it shows |
|---|---|---|
| `variables-as-parameters` | `quote.liquid` | `string`, `integer`, `float`, `boolean`, `array` and `object` variables as `parameters`; the JSON result's fields set a `float` and an `integer` variable |
| `batch-loop` | `order-summary.liquid`, `batch-report.liquid` | a sequential For each with one Liquid action per order; Append to array, Increment (integer and float), a Condition that skips cancelled orders; then the array variable as the `content` of a text report |
| `dynamic-template` | `formats/order-json.liquid`, `order-csv.liquid`, `order-text.liquid` | `templateName` and `outputFormat` from variables chosen by `?format=`; an unknown format fails with `TemplateNotFound` |
| `approval-routing` | `expense-decision.liquid` | rules from an app setting and workflow parameters, a one-word text result (`auto`, `review`, `reject`) and a Switch on it |

## Run it

See the [prerequisites](../README.md#prerequisites).

```powershell
./run.ps1      # Azurite and the Logic App on http://localhost:7108
./demo.ps1     # in a second window: every workflow, checked
./send.ps1 variables-as-parameters messages/order.json -MaxLines 4 -Exclude GIFT-WRAP -Expedite
./send.ps1 variables-as-parameters messages/order.json -Currency usd -TaxRate 0.05
./send.ps1 batch-loop messages/batch.json
./send.ps1 dynamic-template messages/order.json -Format csv
./send.ps1 approval-routing messages/expense-travel.json
```

## Variables as parameters

The workflow fills six variables from the request, then hands them to the template:

```json
"Initialize_the_quote_settings": {
  "type": "InitializeVariable",
  "inputs": { "variables": [
    { "name": "currency",     "type": "string",  "value": "@{toUpper(coalesce(triggerOutputs()?['queries']?['currency'], 'CAD'))}" },
    { "name": "maxLines",     "type": "integer", "value": "@int(coalesce(triggerOutputs()?['queries']?['maxLines'], '10'))" },
    { "name": "taxRate",      "type": "float",   "value": "@float(coalesce(triggerOutputs()?['queries']?['taxRate'], '0.15'))" },
    { "name": "expedite",     "type": "boolean", "value": "@equals(toLower(coalesce(triggerOutputs()?['headers']?['x-expedite'], 'false')), 'true')" },
    { "name": "excludedSkus", "type": "array",   "value": "@if(empty(coalesce(triggerOutputs()?['queries']?['exclude'], '')), json('[]'), split(triggerOutputs()?['queries']?['exclude'], ','))" },
    { "name": "shipTo",       "type": "object",  "value": "@triggerBody()?['shipTo']" }
  ] }
},
"Quote_the_order": {
  "type": "ServiceProvider",
  "inputs": {
    "parameters": {
      "inputFormat": "json", "outputFormat": "json", "content": "@triggerBody()",
      "templateSource": "deployed", "templateName": "quote.liquid",
      "parameters": {
        "currency": "@variables('currency')",
        "maxLines": "@variables('maxLines')",
        "taxRate": "@variables('taxRate')",
        "expedite": "@variables('expedite')",
        "excludedSkus": "@variables('excludedSkus')",
        "shipTo": "@variables('shipTo')"
      }
    },
    …
  }
}
```

Each value keeps its type in the template:

| Variable | In the template |
|---|---|
| `string` | a string: `{{ parameters.currency }}` |
| `integer` | a whole number: `{% for line in content.lines limit: parameters.maxLines %}` |
| `float` | a number: `subtotal \| Times: parameters.taxRate \| Round: 2` |
| `boolean` | `true` or `false`: `{% if parameters.expedite %}` |
| `array` | a list: `Join`, `Size`, `First`, `for` |
| `object` | fields: `parameters.shipTo.city` |

In JSON mode the result is typed, so a Set variable action takes a number straight from it:
`"value": "@body('Quote_the_order')?['result']?['total']"`.

**`contains` and arrays.** `contains` tests text: `{% if 'GIFT-WRAP' contains 'GIFT' %}`. It doesn't find an item in
an array that came from JSON. To test membership, join the array and look for the item between separators, as
`quote.liquid` does:

```liquid
{% assign excluded = parameters.excludedSkus | Join: '|' | Prepend: '|' | Append: '|' %}
{% assign key = line.sku | Prepend: '|' | Append: '|' %}
{% unless excluded contains key %} … {% endunless %}
```

## A loop with variables

`batch-loop` posts a batch of four orders, one of them cancelled:

```
Batch B-20261025-01: 3 orders, 1337.97 CAD
1. SO-2026-0821  Northwind Traders  2 line(s)  148.98
2. SO-2026-0823  Fabrikam Inc.  1 line(s)  987
3. SO-2026-0824  Adventure Works  3 line(s)  201.99
Skipped (cancelled): SO-2026-0822
```

- The For each runs one iteration at a time (`"runtimeConfiguration": { "concurrency": { "repetitions": 1 } }`):
  iterations that change the same variables must not overlap.
- Each order's position comes from the counter, `"position": "@add(variables('orderCount'), 1)"`, before Increment
  adds 1.
- Increment works on `float` variables too: `batchTotal` grows by each order's `result.total`.
- After the loop, `"content": "@variables('summaries')"` passes the whole array; the report template loops over
  `content`.
- The response headers come from variables: `x-order-count`, `x-batch-total`
  (`formatNumber(variables('batchTotal'), '0.00', 'en-US')`) and `x-skipped`.

## A variable picks the template

```json
{ "name": "templateName", "type": "string", "value": "@{concat('formats/order-', variables('format'), '.liquid')}" },
{ "name": "outputFormat", "type": "string", "value": "@{if(equals(variables('format'), 'json'), 'json', 'text')}" }
```

`templateName` and `outputFormat` take expressions like any other input. `?format=pdf` names a template that doesn't
exist: the action fails with `TemplateNotFound`, and the workflow answers 400 with that code.

## A Switch on the template's answer

`expense-decision.liquid` writes one word and nothing else, on one line and with no line break at the end. The
workflow trims it anyway, stores it in a variable and switches on it:

| Message | Decision | Route |
|---|---|---|
| `expense-meal.json` (42.80, receipt) | `auto` | `payments` |
| `expense-no-receipt.json` (42.80, no receipt) | `review` | `manager-review` |
| `expense-travel.json` (740.00) | `review` | `manager-review` |
| `expense-gift.json` (category `gifts`) | `reject` | `returned-to-employee` |
| `expense-large.json` (6,400.00) | `reject` | `returned-to-employee` |

The rules come from two places: `autoApproveLimit` (100) from the app setting `AUTO_APPROVE_LIMIT`, `reviewLimit`
(5000) and `blockedCategories` from the workflow parameter `approval` in `parameters.json`. Change either and the
same template decides differently.
