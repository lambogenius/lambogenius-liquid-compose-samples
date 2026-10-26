# 06 · SOAP service

A legacy CRM only speaks SOAP 1.1. The `update-customer` workflow takes a customer update as JSON, builds the SOAP
request, calls the service, and turns its SOAP response, or its SOAP Fault, back into JSON.

```
caller ──JSON──▶ update-customer
                   Liquid: JSON → SOAP envelope (text)
                   HTTP: POST, SOAPAction, basic auth ──────▶ legacy CRM :8106
                   Liquid: SOAP response or Fault (XML) → JSON
       ◀─JSON────  200 updated · 422 rejected by the CRM · 502 CRM error
```

## Run it

See the [prerequisites](../README.md#prerequisites). This sample also needs Python 3.

```powershell
./run.ps1      # Azurite, the stand-in CRM on 8106, the Logic App on http://localhost:7106
./demo.ps1     # in a second window
./send.ps1 messages/customer-update.json
```

## What the templates show

**`customer-to-soap.liquid`** (JSON → text): an XML document written as text.
- `Escape` on every value. The name `Initech "Québec" <Ltée> & Co` becomes
  `Initech &quot;Qu&#233;bec&quot; &lt;Lt&#233;e&gt; &amp; Co`, and the CRM reads it back unchanged.
- C# helpers write the CRM's formats: the phone number in E.164 (`(514) 555-0199` becomes `+15145550199`) and the
  credit limit as an `xs:decimal` with two places, whatever the server's culture.
- The SOAP header carries an application id from an app setting and the run id as a correlation id
  (`@{workflow()?['run']?['name']}`).
- Booleans are written with plain Liquid: `{% if c.active == false %}false{% else %}true{% endif %}`. `Default`
  turns values into strings, and C# helpers don't accept strings where they expect a number or a Boolean.

**`soap-response-to-json.liquid`** (XML → JSON): reads either answer.
- A successful response puts its elements in the CRM's namespace as the default namespace; the `crm` prefix in
  `xmlNamespaces` reaches them.
- A Fault's `faultcode` and `faultstring` have no namespace, so the XPath names them without a prefix:
  `/soap:Envelope/soap:Body/soap:Fault/faultcode`.
- `XmlValues` returns the warnings as an array: empty when there are none.

**The workflow**:
- The HTTP action posts the envelope with `Content-Type: text/xml` and the `SOAPAction` header. Basic
  authentication comes from the app settings `CRM_USERNAME` and `CRM_PASSWORD` (sample values; use Key Vault
  references in Azure).
- SOAP 1.1 services answer a Fault with HTTP 500, which fails the HTTP action, so the read action runs after
  `Succeeded` **or** `Failed`. The response status comes from what it read: 200, 422 for a `soap:Client` fault
  (the request was wrong), 502 for `soap:Server`.
- The XML body is passed as a string: `"content": "@{body('Call_the_CRM')}"`.

| Step | Message | Result |
|---|---|---|
| 1 | `customer-update.json` | 200, version 8. The CRM got the name, accents and both address lines intact |
| 2 | `customer-no-phone.json` | 200 with one warning |
| 3 | `customer-bad-email.json` | 422: `INVALID_EMAIL`, field `Email` |
| 3 | `customer-unknown.json` | 422: `CUSTOMER_NOT_FOUND` |
| 3 | CRM down (`POST /control/down`) | 502: `soap:Server`, `The customer database is not available` |
