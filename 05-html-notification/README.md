# 05 · Shipping email

When an order ships, the `shipment-notification` workflow turns the event into an email with two bodies and sends
it through a mail API:

```
shipment event ──JSON──▶ shipment-notification
                           Liquid: JSON → HTML body       (deployed template + 2 partials)
                           Liquid: JSON → to, subject, text   (inline template)
                           HTTP: POST /mail/messages ──────────▶ mail API :8105
               ◀─JSON────  202 queued, with a preview link
```

The customer's `language` picks English or French. Open the `preview` link from the response in a browser to see the
email.

## Run it

See the [prerequisites](../README.md#prerequisites). This sample also needs Python 3.

```powershell
./run.ps1      # Azurite, the stand-in mail API on 8105, the Logic App on http://localhost:7105
./demo.ps1     # in a second window
./send.ps1 messages/shipment-fr.json
```

## What the templates show

**`shipment-email.liquid`** (JSON → text, HTML):
- **Escaping.** Every value from the order goes through `Escape`. The gift message in `shipment-en.json` is
  `<script>alert('hi')</script>Happy birthday!`; the email shows it as text, and the stand-in mail API refuses any
  HTML with a `<script>` element. `NewlineToBr` keeps the message's line break.
- **Partials.** `partials/item-row.liquid` renders each item, and `partials/footer.liquid` the footer. Partials see
  the template's variables (`lang`, `item`) and its `parameters`.
- **Language.** `lang` is set once from `customer.language` (`FR` and `fr` both work; anything else is English), and
  each text has both versions.
- **C# helpers.** `TrackingUrl` builds the carrier's tracking link with the number URL-encoded. `LongDate` writes
  the delivery date with the language's culture: `Saturday, October 24, 2026` or `mardi 27 octobre 2026`.
- **Settings.** The shop name and support address come from app settings through the action's `parameters`.

**The inline template** (JSON → JSON, in `shipment-notification/workflow.json`) builds `to`, `subject` and the
plain-text body. The text is assembled with `capture` and written with `ToJson`, which escapes the line breaks and
quotes, so the result is always valid JSON. The plain text keeps the gift message as written: it is not HTML.

The HTTP call to the mail API retries twice, 5 seconds apart: queueing an email twice is a risk you'd handle with an
idempotency key in a real mail API.
