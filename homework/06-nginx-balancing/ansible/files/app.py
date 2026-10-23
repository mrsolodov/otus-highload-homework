"""Tiny WSGI app used to identify the frontend that handled a request."""

import json
import socket


def application(environ, start_response):
    payload = {
        "status": "ok",
        "node": socket.gethostname(),
        "path": environ.get("PATH_INFO", "/"),
    }
    body = (json.dumps(payload, ensure_ascii=False) + "\n").encode("utf-8")
    start_response(
        "200 OK",
        [
            ("Content-Type", "application/json; charset=utf-8"),
            ("Content-Length", str(len(body))),
            ("Cache-Control", "no-store"),
        ],
    )
    return [body]
