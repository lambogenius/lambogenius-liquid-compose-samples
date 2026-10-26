# 02 · Orders to ERP

Orders arrive in two shapes: a webshop posts JSON webhooks, and a B2B partner posts XML purchase orders. The Logic
App maps both to the ERP's sales-order format with Compose using Liquid, creates the order in the ERP, sends the
warehouse a printable pick list, and answers each channel in its own format.

```
webshop ──JSON────▶ webshop-order                        submit-sales-order
                      Liquid: JSON → sales order ──┐       HTTP: create the order ──────▶ ERP        :8102
                                                   ├────▶  Liquid: sales order → pick list
partner ──XML─────▶ partner-order                  │       HTTP: send the pick list ────▶ warehouse  :8102
        ◀─XML ack──   Liquid: XML → sales order ───┘
                      Liquid: result → acknowledgement

Both maps look up the customer's name with CallFunction → GetCustomerName Function :7075
```

| Template | Mode | What it shows |
|---|---|---|
| `webshop-to-erp.liquid` | JSON → JSON | C# helpers for cleanup: money strings to numbers, the local order date, postal codes, province to tax code. `CallFunction` for the customer name. `Default` with a value from the workflow |
| `partner-po-to-erp.liquid` | XML → JSON | `XmlValue` / `XmlValues` with a namespace prefix, repeating elements read as parallel arrays, XML strings to JSON numbers |
| `erp-pick-list.liquid` | JSON → text | a fixed-width pick list for the warehouse printer, with C# column padding and a running total |
| `erp-to-partner-ack.liquid` | JSON → text (XML) | the partner's XML acknowledgement, values escaped with `Escape` |

The two maps produce the same ERP shape from different inputs, so everything after them is shared, in the
`submit-sales-order` child workflow.

## Run it

See the [prerequisites](../README.md#prerequisites). This sample also needs Python 3.

```powershell
./run.ps1      # Azurite, the Function on 7075, the stand-in ERP and warehouse on 8102, the Logic App on 7102
./demo.ps1     # in a second window: the 8 steps below, checked
```

Or step by step:

```powershell
./send.ps1 webshop-order messages/webshop-order.json
./send.ps1 partner-order messages/partner-po.xml
Invoke-RestMethod http://127.0.0.1:8102/received | ConvertTo-Json -Depth 10     # what the ERP and warehouse got
```

1. **A webshop order.** HTTP 201 with `erpOrderId` `SO-000101` and `customerName` `Acme Supplies`. The ERP got
   postal code `M5X 1A9`, tax code `HST13`, SKU `ABC-01` and `9.99` as a number. The warehouse got:
   ```
   PICK LIST SO-000101
   Order:   WEB-1001 (webshop, 2026-10-20)
   Ship to: Jane Doe
            100 King St W
            Toronto ON M5X 1A9 CA
   ------------------------------------------------
     10  ABC-01         x2  Widget, blue
     20  XYZ-02         x1  Gadget "Pro"
   ------------------------------------------------
   Lines: 2   Units: 3
   ```
   The order date is the shop's local date: `2026-10-20T21:32:05-04:00` is already the 21st in UTC.
2. **A partner purchase order.** HTTP 201 and an XML acknowledgement with `SO-000102` and three lines.
3. **The same webshop order again.** The ERP recognizes `WEB-1001`: HTTP 200, `"status": "already received"`, no
   duplicate.
4. **A Québec order.** The name `Initech "Québec" Ltée` arrives intact; the tax code is `GST-QST`.

## When things go wrong

| Step | What happens | The caller gets |
|---|---|---|
| **5.** Unknown customer | `GetCustomerName` answers 404, so the map fails with `FunctionHttpFailed`. Nothing reaches the ERP | 422 with the error |
| **6.** Zero quantity | the map succeeds; the ERP rejects the order | 422 with the ERP's reasons |
| **7.** ERP down (`POST /control/erp-down`) | the ERP call is tried 3 times, 5 seconds apart | 503 after about 17 s: send again later |
| **8.** Warehouse down after the ERP accepted the order | the pick list fails after 3 tries; the ERP order exists | 502 with `erpOrderId`. Sending again returns the same ERP order and delivers the pick list |

Turn a system back on with `/control/erp-up` or `/control/warehouse-up`, or reset with `/control/reset`.

## Design notes

- **Only the HTTP calls retry**, and both are safe to repeat: the ERP deduplicates on `externalOrderId`, and a
  second pick list is harmless. The Liquid actions have `retryPolicy: none`: a mapping failure is a data problem,
  and a retry would repeat the Function lookups. The `Workflow` action has `retryPolicy: none` too, or a 5xx from
  the child would start the child again.
- **`retryPolicy` goes inside `inputs`.** Next to `inputs`, it is ignored and the default policy applies: 4 retries
  with exponential backoff, about 80 s for a system that is down. The shortest interval is 5 seconds.
- **The caller can always send again.** Every failure answer says whether the ERP order exists, and the ERP
  deduplicates.
- **Settings, not literals.** Endpoints come from `@appsetting('ERP_BASE_URL')` and `@appsetting('WAREHOUSE_BASE_URL')`;
  the default currency reaches the template through the action's `parameters`.
