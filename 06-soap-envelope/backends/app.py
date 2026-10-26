"""
Stand-in legacy CRM with a SOAP 1.1 service, for the update-customer sample. Standard library only.

  POST /crm/CustomerService.asmx   SOAPAction "urn:example:legacy-crm:2009/UpdateCustomer", HTTP basic auth.
                                   200 with an UpdateCustomerResponse, or 500 with a SOAP Fault: soap:Client for
                                   requests it rejects, soap:Server when it is "down".
  GET  /received                   the envelopes it accepted, parsed, and the raw XML (for demo.ps1)
  POST /control/down | /control/up | /control/reset

The basic-auth user and password are the sample values in local.settings.sample.json (CRM_USERNAME, CRM_PASSWORD).

Usage: python app.py [--port 8106]
"""

import argparse
import base64
import json
import threading
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from xml.sax.saxutils import escape

SOAP = "http://schemas.xmlsoap.org/soap/envelope/"
CRM = "urn:example:legacy-crm:2009"
ACTION = "urn:example:legacy-crm:2009/UpdateCustomer"
USER, PASSWORD = "logicapp", "sample-only-password"
CUSTOMERS = {"C100": 1, "C200": 4, "C300": 7}

lock = threading.Lock()
state = {}


def reset():
    state.clear()
    state.update({"down": False, "updates": [], "versions": dict(CUSTOMERS)})


def fault(code, text, error_code=None, field=None):
    detail = ""
    if error_code:
        detail = (f"<detail><crm:ValidationError><crm:Code>{escape(error_code)}</crm:Code>"
                  f"<crm:Field>{escape(field or '')}</crm:Field></crm:ValidationError></detail>")
    return (f'<?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:soap="{SOAP}" xmlns:crm="{CRM}"><soap:Body>'
            f"<soap:Fault><faultcode>soap:{code}</faultcode><faultstring>{escape(text)}</faultstring>{detail}</soap:Fault>"
            "</soap:Body></soap:Envelope>")


def success(customer_id, version, warnings):
    items = "".join(f"<Warning>{escape(w)}</Warning>" for w in warnings)
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return (f'<?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:soap="{SOAP}"><soap:Body>'
            f'<UpdateCustomerResponse xmlns="{CRM}"><UpdateCustomerResult><CustomerId>{customer_id}</CustomerId>'
            f"<Version>{version}</Version><UpdatedAt>{now}</UpdatedAt><Warnings>{items}</Warnings>"
            "</UpdateCustomerResult></UpdateCustomerResponse></soap:Body></soap:Envelope>")


def text(element, path):
    found = element.find(path, {"crm": CRM})
    return found.text if found is not None and found.text is not None else ""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(f"{self.command} {self.path} -> {args[1] if len(args) > 1 else ''}", flush=True)

    def reply(self, status, body, content_type="text/xml; charset=utf-8"):
        data = body.encode("utf-8") if isinstance(body, str) else json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/received":
            with lock:
                return self.reply(200, state, "application/json; charset=utf-8")
        self.reply(404, {"error": "not found"}, "application/json")

    def do_POST(self):
        raw = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        with lock:
            if self.path.startswith("/control/"):
                what = self.path.rsplit("/", 1)[1]
                if what == "reset":
                    reset()
                elif what in ("down", "up"):
                    state["down"] = what == "down"
                return self.reply(200, {"down": state["down"]}, "application/json")
            if self.path != "/crm/CustomerService.asmx":
                return self.reply(404, {"error": "not found"}, "application/json")

            expected = "Basic " + base64.b64encode(f"{USER}:{PASSWORD}".encode()).decode()
            if self.headers.get("Authorization") != expected:
                return self.reply(401, fault("Client", "Authentication failed."))
            if self.headers.get("SOAPAction", "").strip('"') != ACTION:
                return self.reply(500, fault("Client", f"Unknown SOAPAction {self.headers.get('SOAPAction')!r}."))
            if state["down"]:
                return self.reply(500, fault("Server", "The customer database is not available. Try again later."))
            try:
                envelope = ET.fromstring(raw)
            except ET.ParseError as error:
                return self.reply(500, fault("Client", f"The request is not well-formed XML: {error}"))

            customer = envelope.find(f"{{{SOAP}}}Body/{{{CRM}}}UpdateCustomer/{{{CRM}}}Customer")
            if customer is None:
                return self.reply(500, fault("Client", "The body has no crm:UpdateCustomer/crm:Customer."))
            customer_id = text(customer, "crm:CustomerId")
            if customer_id not in state["versions"]:
                return self.reply(500, fault("Client", f"Customer {customer_id} does not exist.", "CUSTOMER_NOT_FOUND", "CustomerId"))
            email = text(customer, "crm:Email")
            if "@" not in email:
                return self.reply(500, fault("Client", "The email address is not valid.", "INVALID_EMAIL", "Email"))
            warnings = []
            if not text(customer, "crm:Phone"):
                warnings.append("No phone number; the account manager will be asked to add one.")

            state["versions"][customer_id] += 1
            state["updates"].append({
                "customerId": customer_id,
                "name": text(customer, "crm:Name"),
                "email": email,
                "phone": text(customer, "crm:Phone"),
                "lines": [line.text for line in customer.findall("crm:Address/crm:Line", {"crm": CRM})],
                "city": text(customer, "crm:Address/crm:City"),
                "creditLimit": text(customer, "crm:CreditLimit"),
                "active": text(customer, "crm:Active"),
                "applicationId": text(envelope, f"{{{SOAP}}}Header/crm:ClientInfo/crm:ApplicationId"),
                "xml": raw.decode("utf-8"),
            })
            return self.reply(200, success(customer_id, state["versions"][customer_id], warnings))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8106)
    port = parser.parse_args().port
    reset()
    print(f"Legacy CRM stand-in on http://127.0.0.1:{port}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
