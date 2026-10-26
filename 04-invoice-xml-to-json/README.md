# 04 · Supplier invoice

A supplier sends a [UBL 2.1](https://docs.oasis-open.org/ubl/UBL-2.1.html) invoice as XML. The `supplier-invoice`
workflow maps it to the JSON that the accounts-payable (AP) API accepts, posts it, and tells the supplier what
happened.

```
supplier ──UBL XML──▶ supplier-invoice
                        Liquid: XML → AP invoice (JSON)
                        HTTP: POST /ap/invoices ──────────▶ accounts payable :8104
         ◀─JSON──────   201 accepted · 409 duplicate · 422 rejected or not mapped
```

## Run it

See the [prerequisites](../README.md#prerequisites). This sample also needs Python 3.

```powershell
./run.ps1      # Azurite, the stand-in AP API on 8104, the Logic App on http://localhost:7104
./demo.ps1     # in a second window
./send.ps1 messages/invoice.xml
```

## What the map shows

`Artifacts/LiquidTemplates/ubl-invoice-to-ap.liquid`:

- **Namespaces.** UBL puts the invoice in a default namespace and its components in two prefixed ones. XPath needs a
  prefix for every namespace, including the default one, so the action declares all three:
  ```json
  "xmlNamespaces": {
    "inv": "urn:oasis:names:specification:ubl:schema:xsd:Invoice-2",
    "cac": "urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2",
    "cbc": "urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2"
  }
  ```
  The template then reads `/inv:Invoice/cac:LegalMonetaryTotal/cbc:PayableAmount`.
- **Attributes.** `/inv:Invoice/cac:InvoiceLine/cbc:InvoicedQuantity/@unitCode` selects each line's unit code (`EA`,
  `HUR`). A C# helper turns those into the AP system's names.
- **Repeating lines.** `XmlValues` returns one array per field (IDs, SKUs, quantities…). The `for` loop walks them
  together with `forloop.index0`.
- **Types.** XML values are strings; the `Number` helper writes amounts as JSON numbers.
- **Computed values.** `TermsDays` works out the payment terms from the issue and due dates. Helpers take one
  argument, so the template joins the two dates: `issued | Append: '|' | Append: due`.
- **Required fields.** `Required` throws when the invoice number or the purchase-order reference is empty, so the
  action fails and nothing is sent. Values that can be missing go through `Default: ''` first: a helper refuses a
  null input.
- **Entities.** `&amp;` and `&lt;on site&gt;` in the XML arrive as `&` and `<on site>` in the JSON.

## The steps

| Step | Message | Result |
|---|---|---|
| 1 | `invoice.xml` | 201 with `AP-5001`. AP got numbers, units `each` and `hour`, 30-day terms |
| 2 | `invoice.xml` again | 409 from AP, with the AP id it already has |
| 3 | `invoice-missing-po.xml` | 422 `ScriptExecutionFailed` from the `Required` helper. AP got no call |
| 4 | `invoice-unknown-po.xml` | 422 from AP: `purchase order PO-1999-0001 is not open` |
| 4 | `invoice-wrong-total.xml` | 422 from AP: `subtotal + tax is 1497.25, not the total 1479.25` |

The stand-in AP API is in `backends/app.py`; `GET http://127.0.0.1:8104/received` shows what it accepted.
