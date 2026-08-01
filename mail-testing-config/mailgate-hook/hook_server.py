#!/usr/bin/env python3
"""Stalwart MTA Hook endpoint that pipes messages into odoo-mailgate.py."""

from __future__ import annotations

import json
import logging
import os
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
LOG = logging.getLogger("mailgate-hook")

EX_TEMPFAIL = 75
EX_CONFIG = 78


def odoo_domains() -> set[str]:
    raw = os.environ.get("ODOO_RECEIVING_DOMAINS", "manmanufacturing.com")
    return {d.strip().lower() for d in raw.split(",") if d.strip()}


def recipient_domains(envelope: dict) -> set[str]:
    domains: set[str] = set()
    for rcpt in envelope.get("to") or []:
        addr = (rcpt.get("address") or "").lower()
        if "@" in addr:
            domains.add(addr.rsplit("@", 1)[-1])
    return domains


def build_rfc822(message: dict) -> bytes:
    lines = [
        f"{header[0]}: {header[1]}"
        for key in ("headers", "serverHeaders")
        for header in (message.get(key) or [])
        if len(header) >= 2
    ]
    body = message.get("contents") or ""
    if not body.endswith("\r\n"):
        body = body.replace("\n", "\r\n")
        if not body.endswith("\r\n"):
            body += "\r\n"
    lines.extend(("", body))
    return "\r\n".join(lines).encode("utf-8", errors="replace")


def run_mailgate(raw_message: bytes) -> int:
    db = os.environ.get("ODOO_DB", "")
    user = os.environ.get("ODOO_USER_ID", "")
    password = os.environ.get("ADMIN_PASSWORD", "")
    host = os.environ.get("ODOO_HOST", "odoo")
    port = os.environ.get("ODOO_PORT", "8069")
    script = os.environ.get("MAILGATE_SCRIPT", "/mailgate/odoo-mailgate.py")

    if not all([db, user, password]):
        LOG.error("Missing ODOO_DB, ODOO_USER_ID, or ADMIN_PASSWORD")
        return EX_CONFIG

    cmd = [
        sys.executable,
        script,
        "-d",
        db,
        "-u",
        user,
        "-p",
        password,
        "--host",
        host,
        "--port",
        port,
    ]
    proc = subprocess.run(cmd, input=raw_message, capture_output=True)
    if proc.stdout:
        LOG.info(proc.stdout.decode(errors="replace").strip())
    if proc.stderr:
        LOG.warning(proc.stderr.decode(errors="replace").strip())
    return proc.returncode


class MtaHookHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:  # noqa: A003
        LOG.info("%s - %s", self.address_string(), fmt % args)

    def do_POST(self) -> None:  # noqa: N802
        if self.path.rstrip("/") != "/mta-hook":
            self.send_error(404)
            return

        length = int(self.headers.get("Content-Length", "0"))
        payload = json.loads(self.rfile.read(length).decode("utf-8"))
        domains = recipient_domains(payload.get("envelope") or {})
        if not domains.intersection(odoo_domains()):
            self._json_response({"action": "accept"})
            return

        raw = build_rfc822(payload.get("message") or {})
        code = run_mailgate(raw)
        if code == 0:
            self._json_response({"action": "discard"})
            return
        if code in (EX_TEMPFAIL, 69, 70):
            self._json_response(
                {
                    "action": "reject",
                    "response": {
                        "status": 451,
                        "enhancedStatus": "4.3.0",
                        "message": "Odoo mailgate temporary failure",
                        "disconnect": False,
                    },
                }
            )
            return
        self._json_response(
            {
                "action": "reject",
                "response": {
                    "status": 550,
                    "enhancedStatus": "5.3.0",
                    "message": "Odoo mailgate permanent failure",
                    "disconnect": False,
                },
            }
        )

    def _json_response(self, body: dict) -> None:
        data = json.dumps(body).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def main() -> None:
    port = int(os.environ.get("PORT", "8765"))
    server = HTTPServer(("0.0.0.0", port), MtaHookHandler)
    LOG.info("Listening on :%s", port)
    server.serve_forever()


if __name__ == "__main__":
    main()
