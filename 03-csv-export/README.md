# 03 · CSV and bank files

Two flat files that other systems read byte by byte, made with JSON → text templates:

| Workflow | Template | Output |
|---|---|---|
| `orders-to-csv` | `orders-to-csv.liquid` | an [RFC 4180](https://www.rfc-editor.org/rfc/rfc4180) CSV of the day's orders for finance, returned as `text/csv` with a file name |
| `payments-to-bank-file` | `payments-to-bank-file.liquid` | a payment file in a bank's fixed-width layout: a header, one 80-character record per payment and a trailer with the count and total |

`demo.ps1` compares both files with `expected/orders.csv` and `expected/payments.txt`, byte for byte.

## Run it

See the [prerequisites](../README.md#prerequisites).

```powershell
./run.ps1      # Azurite and the Logic App on http://localhost:7103
./demo.ps1     # in a second window
./send.ps1 orders-to-csv messages/orders.json -OutFile orders.csv
./send.ps1 payments-to-bank-file messages/payments.json
```

## The CSV

```
order_number,placed_on,customer,email,status,total,currency,note
1001,2026-10-20,Acme Supplies,orders@acme.example,PAID,129.90,CAD,
1002,2026-10-20,"Globex, Corporation",ap@globex.example,PAID,1250.00,USD,"Leave at the ""back"" door"
1003,2026-10-21,"Initech ""Québec"" Ltée",,REFUNDED,45.50,CAD,"Two lines:
first, then second"
```

- **Quoting.** The C# helper `Csv` quotes a field only when it holds a comma, a quote or a line break, and doubles
  the quotes inside it.
- **Line endings.** Every record ends with CRLF, as RFC 4180 asks. The template writes `{{ nl }}`, which the
  workflow passes as `"parameters": { "newline": "\r\n" }`. The template's own line breaks are removed by the dash in
  `-%}`, which trims the whitespace after a tag.
- **Values.** `Money` writes two decimals with a dot (`"129.9"` becomes `129.90`), and `Day` keeps the order's local
  date. A missing email or note becomes an empty field (`Default: ''`), and a missing currency becomes the app
  setting `DEFAULT_CURRENCY`.

## The bank file

```
H20261023LAMBO00042
D000012345678ACME SUPPLIES                 000000125000INV-2026-0411
D000000998877INITECH "QUEBEC" LTEE         000000008995INV-2026-0412
D000005550001GLOBEX CORPORATION OF NORTH AM000000000005CREDIT-MEMO-2026
T00000300000000134000
```

Every line is padded to 80 characters and ends with CRLF. The C# helpers turn values into fixed-width fields:
- account numbers keep their digits only and are zero-padded to 12;
- payee names are folded to ASCII (`Ltée` becomes `LTEE`) and cut or padded to 30;
- amounts are in cents, zero-padded to 12, and summed in the trailer;
- invoice references are cut to 16.

The workflow adds `Content-Disposition: attachment; filename="PAY20261023.txt"` and an `x-record-count` header.

**A bad account number** (`messages/payments-bad-account.json`): the `Account` helper throws, the action fails with
`ScriptExecutionFailed`, and the workflow returns 422 instead of a file with a bad record. Nothing partial is ever
returned: the file exists only when the whole template succeeds.
