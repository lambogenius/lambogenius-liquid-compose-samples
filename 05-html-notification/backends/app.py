"""
Stand-in mail API for the shipment-notification sample. Standard library only.

  POST /mail/messages             {"to", "subject", "text", "html"} -> 202 {"messageId": "MSG-1"}; 422 when a field
                                  is missing or the HTML holds a <script> element
  GET  /mail/messages/<id>.html   the HTML body, to look at in a browser
  GET  /mail/messages/<id>.txt    the plain-text body
  GET  /received                  every message, for demo.ps1
  POST /control/reset             forget everything

Usage: python app.py [--port 8105]
"""

import argparse
import json
import re
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

lock = threading.Lock()
state = {}


def reset():
    state.clear()
    state.update({"messages": [], "next": 1})


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(f"{self.command} {self.path} -> {args[1] if len(args) > 1 else ''}", flush=True)

    def reply(self, status, body, content_type="application/json; charset=utf-8"):
        data = body.encode("utf-8") if isinstance(body, str) else json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        with lock:
            if self.path == "/received":
                return self.reply(200, state)
            match = re.fullmatch(r"/mail/messages/(MSG-\d+)\.(html|txt)", self.path)
            message = next((m for m in state["messages"] if match and m["messageId"] == match.group(1)), None)
            if message:
                if match.group(2) == "html":
                    return self.reply(200, message["html"], "text/html; charset=utf-8")
                return self.reply(200, message["text"], "text/plain; charset=utf-8")
        self.reply(404, {"error": "not found"})

    def do_POST(self):
        raw = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        with lock:
            if self.path == "/control/reset":
                reset()
                return self.reply(200, {"reset": True})
            if self.path != "/mail/messages":
                return self.reply(404, {"error": "not found"})
            try:
                message = json.loads(raw)
            except ValueError:
                return self.reply(400, {"error": "the body is not JSON"})
            problems = [f"{f} is missing" for f in ("to", "subject", "text", "html") if not message.get(f)]
            if re.search(r"<\s*script", message.get("html") or "", re.I):
                problems.append("the HTML holds a <script> element")
            if problems:
                return self.reply(422, {"problems": problems})
            message["messageId"] = f"MSG-{state['next']}"
            state["next"] += 1
            state["messages"].append(message)
            return self.reply(202, {"messageId": message["messageId"], "status": "queued"})


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8105)
    port = parser.parse_args().port
    reset()
    print(f"Mail stand-in on http://127.0.0.1:{port}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
