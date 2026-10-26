"""Stand-in ERP and warehouse APIs for the orders-to-ERP scenario (Python standard library only).

ERP
  POST /erp/salesorders        JSON sales order -> 201 {"id": "SO-000101", ...}
                               200 with the existing id when externalOrderId was seen before (idempotent)
                               422 when a required field is missing or a quantity/price is not positive
                               503 while the ERP is switched down
Warehouse
  POST /warehouse/picklists    text/plain pick list, header X-Sales-Order-Id -> 201 (503 while switched down)
Demo
  GET  /received               everything accepted so far, and how many calls each endpoint got
  POST /control/erp-down       the ERP answers 503 from now on
  POST /control/erp-up         back to normal
  POST /control/warehouse-down the warehouse answers 503 from now on
  POST /control/warehouse-up   back to normal
  POST /control/reset          forget everything, both up

Usage: python app.py [--port 8102]
"""

import argparse
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

REQUIRED = ("externalOrderId", "channel", "orderDate", "customer", "shipTo", "taxCode", "currency", "lines")

lock = threading.Lock()
state = {}


def reset():
    state.update(erp_up=True, warehouse_up=True, next_id=101, orders={}, pick_lists=[], calls={})


def validate(order):
    problems = [f"'{name}' is required" for name in REQUIRED if order.get(name) in (None, "", [])]
    if not (order.get("customer") or {}).get("name"):
        problems.append("'customer.name' is required")
    for line in order.get("lines") or []:
        if not isinstance(line.get("quantity"), (int, float)) or line["quantity"] <= 0:
            problems.append(f"line {line.get('lineNo')}: quantity must be a positive number")
        if not isinstance(line.get("unitPrice"), (int, float)) or line["unitPrice"] < 0:
            problems.append(f"line {line.get('lineNo')}: unitPrice must be a number >= 0")
    return problems


class Handler(BaseHTTPRequestHandler):
    def _send(self, status, body):
        data = json.dumps(body, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _body(self):
        return self.rfile.read(int(self.headers.get("Content-Length") or 0))

    def do_GET(self):
        if self.path == "/received":
            with lock:
                return self._send(200, {"salesOrders": list(state["orders"].values()), "pickLists": state["pick_lists"], "calls": state["calls"]})
        self._send(404, {"error": "not found"})

    def do_POST(self):
        body = self._body()
        with lock:
            if not self.path.startswith("/control/"):
                state["calls"][self.path] = state["calls"].get(self.path, 0) + 1
            if self.path == "/control/erp-down":
                state["erp_up"] = False
                return self._send(200, {"erp": "down"})
            if self.path == "/control/erp-up":
                state["erp_up"] = True
                return self._send(200, {"erp": "up"})
            if self.path == "/control/warehouse-down":
                state["warehouse_up"] = False
                return self._send(200, {"warehouse": "down"})
            if self.path == "/control/warehouse-up":
                state["warehouse_up"] = True
                return self._send(200, {"warehouse": "up"})
            if self.path == "/control/reset":
                reset()
                return self._send(200, {"reset": True})
            if self.path == "/erp/salesorders":
                return self._sales_order(body)
            if self.path == "/warehouse/picklists":
                if not state["warehouse_up"]:
                    return self._send(503, {"error": "warehouse system is offline"})
                order_id = self.headers.get("X-Sales-Order-Id") or ""
                text = body.decode("utf-8")
                if not order_id or not text.startswith("PICK LIST"):
                    return self._send(400, {"error": "expected a text/plain pick list and an X-Sales-Order-Id header"})
                state["pick_lists"].append({"salesOrderId": order_id, "text": text})
                return self._send(201, {"salesOrderId": order_id, "lines": len(text.splitlines())})
        self._send(404, {"error": "not found"})

    def _sales_order(self, body):
        if not state["erp_up"]:
            return self._send(503, {"error": "ERP is down for maintenance"})
        try:
            order = json.loads(body)
        except ValueError:
            return self._send(400, {"error": "body is not JSON"})
        problems = validate(order)
        if problems:
            return self._send(422, {"error": "sales order rejected", "problems": problems})
        existing = state["orders"].get(order["externalOrderId"])
        if existing:
            return self._send(200, {"id": existing["id"], "externalOrderId": order["externalOrderId"], "duplicate": True})
        order_id = f"SO-{state['next_id']:06d}"
        state["next_id"] += 1
        state["orders"][order["externalOrderId"]] = {"id": order_id, "order": order}
        return self._send(201, {"id": order_id, "externalOrderId": order["externalOrderId"], "duplicate": False})

    def log_message(self, format, *args):
        print(f"{self.command} {self.path} -> {args[1] if len(args) > 1 else ''}", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8102)
    port = parser.parse_args().port
    reset()
    print(f"ERP and warehouse stand-ins on http://127.0.0.1:{port}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
