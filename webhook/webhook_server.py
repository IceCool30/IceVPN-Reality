#!/usr/bin/env python3
"""
webhook_server.py - BTCPay -> tier-manager renew bridge.

Listens for BTCPay Server webhook POSTs, verifies the signature, and on a
settled/confirmed invoice calls tier-manager.sh renew <orderId> to clear the
user's used traffic and extend their expiry.

WHY PYTHON STDLIB ONLY: it runs anywhere the panel runs with no pip installs.
Keep it that way so deployment is copy-and-run.

RUN
    export BTCPAY_SECRET='your-webhook-secret'
    export ICEVPN_PANEL='http://127.0.0.1:PANELPORT/PATH'
    export ICEVPN_TOKEN='your-api-token'
    export ICEVPN_INBOUND=1
    export LISTEN_HOST=127.0.0.1
    export LISTEN_PORT=8321
    python3 webhook_server.py

Then point your BTCPay store webhook at http://YOUR_SERVER:8321/btcpay (or put it
behind a reverse proxy / Cloudflare Tunnel with TLS). Create each invoice with
metadata.orderId = the user's handle/email so we know who to renew.

SECURITY
  - Bind to 127.0.0.1 by default and front it with TLS (reverse proxy or tunnel).
    Never expose it raw to the internet without TLS and signature checks.
  - The signature check is mandatory. Bad/missing signature => 401, no action.
  - We only act on InvoiceSettled / InvoiceConfirmed by default.
"""

import os
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

import btcpay_verify

SECRET = os.environ.get("BTCPAY_SECRET", "")
LISTEN_HOST = os.environ.get("LISTEN_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("LISTEN_PORT", "8321"))
DELIVER_EVENTS = set(
    filter(None, os.environ.get("DELIVER_EVENTS", "InvoiceSettled,InvoiceConfirmed").split(","))
)
TIER_MANAGER = os.environ.get("TIER_MANAGER", os.path.join(os.path.dirname(__file__), "..", "scripts", "tier-manager.sh"))
LOG_FILE = os.environ.get("WEBHOOK_LOG", "")


def log(msg):
    line = f"[webhook] {msg}"
    print(line, flush=True)
    if LOG_FILE:
        try:
            with open(LOG_FILE, "a") as fh:
                fh.write(line + "\n")
        except OSError:
            pass


def run_renew(order_id):
    """Call tier-manager.sh renew <order_id>. Returns (ok, output)."""
    if not order_id:
        return False, "no orderId in metadata"
    cmd = ["bash", TIER_MANAGER, "renew", order_id]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        return proc.returncode == 0, (proc.stdout + proc.stderr).strip()
    except (OSError, subprocess.SubprocessError) as exc:
        return False, f"renew failed: {exc}"


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body=""):
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        if body:
            self.wfile.write(body.encode("utf-8"))

    def do_GET(self):  # health check
        if self.path.rstrip("/") in ("", "/health", "/btcpay"):
            self._send(200, "ok")
        else:
            self._send(404, "not found")

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length) if length else b""

        sig = self.headers.get("BTCPay-Sig", "")
        if not btcpay_verify.verify_signature(SECRET, body, sig):
            log(f"REJECTED bad/missing signature from {self.client_address}")
            self._send(401, "invalid signature")
            return

        try:
            event = btcpay_verify.parse_event(body)
        except ValueError as exc:
            log(f"REJECTED bad JSON: {exc}")
            self._send(400, "invalid json")
            return

        etype = event.get("type", "?")
        if not btcpay_verify.should_deliver(event, DELIVER_EVENTS):
            # Acknowledge so BTCPay stops retrying, but take no action.
            log(f"IGNORED event type={etype} (not in deliver set)")
            self._send(200, "ignored")
            return

        order_id = btcpay_verify.extract_order_id(event)
        log(f"DELIVER event type={etype} invoiceId={event.get('invoiceId')} orderId={order_id}")
        ok, out = run_renew(order_id)
        if ok:
            log(f"RENEWED {order_id}: {out}")
            self._send(200, "renewed")
        else:
            # 500 makes BTCPay retry later. Good for a transient tier-manager error.
            log(f"RENEW FAILED {order_id}: {out}")
            self._send(500, "renew failed")

    def log_message(self, fmt, *args):  # silence default noisy logging
        log(fmt % args)


def main():
    if not SECRET:
        print("ERROR: set BTCPAY_SECRET (the webhook secret from BTCPay). Refusing to run without it.", file=sys.stderr)
        sys.exit(2)
    server = HTTPServer((LISTEN_HOST, LISTEN_PORT), Handler)
    log(f"listening on http://{LISTEN_HOST}:{LISTEN_PORT}/btcpay  deliver_events={sorted(DELIVER_EVENTS)}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log("shutting down")
        server.server_close()


if __name__ == "__main__":
    main()