"""
Stand-in accounts payable (AP) API for the supplier-invoice sample. Standard library only.

  POST /ap/invoices      an invoice as JSON. 201 {"apInvoiceId": ...} when it is accepted; 409 when the supplier
                         already sent this invoice number; 422 {"problems": [...]} when it doesn't add up or names an
                         unknown purchase order.
  GET  /received         what was accepted, and how often each path was called (for demo.ps1)
  POST /control/reset    forget everything

Usage: python app.py [--port 8104]
"""

import argparse
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

OPEN_PURCHASE_ORDERS = {"PO-2026-0457", "PO-2026-0458"}

lock = threading.Lock()
state = {}


def reset():
    state.clear()
    state.update({"invoices": [], "calls": {}, "next": 5001})


def problems_of(invoice):
    problems = []
    for field in ("supplierInvoiceNumber", "purchaseOrder", "invoiceDate", "currency", "lines", "subtotal", "tax", "total"):
        if invoice.get(field) in (None, "", []):
            problems.append(f"{field} is missing")
    if problems:
        return problems
    if invoice["purchaseOrder"] not in OPEN_PURCHASE_ORDERS:
        problems.append(f"purchase order {invoice['purchaseOrder']} is not open")
    numbers = [invoice["subtotal"], invoice["tax"], invoice["total"]] + [line.get("amount") for line in invoice["lines"]]
    if not all(isinstance(n, (int, float)) and not isinstance(n, bool) for n in numbers):
        return problems + ["amounts must be numbers"]
    lines = round(sum(line["amount"] for line in invoice["lines"]), 2)
    if lines != round(invoice["subtotal"], 2):
        problems.append(f"the lines add up to {lines:.2f}, not the subtotal {invoice['subtotal']:.2f}")
    if round(invoice["subtotal"] + invoice["tax"], 2) != round(invoice["total"], 2):
        problems.append(f"subtotal + tax is {invoice['subtotal'] + invoice['tax']:.2f}, not the total {invoice['total']:.2f}")
    return problems


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(f"{self.command} {self.path} -> {args[1] if len(args) > 1 else ''}", flush=True)

    def reply(self, status, body):
        data = json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/received":
            with lock:
                return self.reply(200, state)
        self.reply(404, {"error": "not found"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length)
        with lock:
            state["calls"][self.path] = state["calls"].get(self.path, 0) + 1
            if self.path == "/control/reset":
                reset()
                return self.reply(200, {"reset": True})
            if self.path != "/ap/invoices":
                return self.reply(404, {"error": "not found"})
            try:
                invoice = json.loads(raw)
            except ValueError:
                return self.reply(400, {"error": "the body is not JSON"})
            problems = problems_of(invoice)
            if problems:
                return self.reply(422, {"problems": problems})
            supplier = (invoice.get("supplier") or {}).get("taxId")
            for known in state["invoices"]:
                if known["invoice"]["supplierInvoiceNumber"] == invoice["supplierInvoiceNumber"] and (known["invoice"].get("supplier") or {}).get("taxId") == supplier:
                    return self.reply(409, {"error": "already received", "apInvoiceId": known["apInvoiceId"]})
            ap_id = f"AP-{state['next']}"
            state["next"] += 1
            state["invoices"].append({"apInvoiceId": ap_id, "invoice": invoice})
            return self.reply(201, {"apInvoiceId": ap_id, "status": "awaiting approval"})


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8104)
    port = parser.parse_args().port
    reset()
    print(f"AP stand-in on http://127.0.0.1:{port}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
