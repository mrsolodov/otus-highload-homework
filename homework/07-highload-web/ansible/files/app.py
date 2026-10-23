"""Minimal database-backed WSGI application for the five-VM lab."""

import json
import os
from contextlib import closing

import psycopg2


STATIC = "/srv/otus-static/index.html"


def application(environ, start_response):
    path = environ.get("PATH_INFO", "/")
    if path == "/static/index.html":
        try:
            with open(STATIC, "rb") as page:
                body = page.read()
        except OSError:
            start_response("503 Service Unavailable", [("Content-Type", "text/plain")])
            return [b"Shared static storage is unavailable\n"]
        start_response("200 OK", [("Content-Type", "text/html; charset=utf-8"), ("X-Backend", os.uname().nodename)])
        return [body]

    if path != "/health":
        start_response("404 Not Found", [("Content-Type", "text/plain")])
        return [b"Not found\n"]

    try:
        with open("/opt/otus-web/db-password", encoding="utf-8") as secret:
            password = secret.read().strip()
        with closing(psycopg2.connect(host="192.168.56.30", dbname="otusapp", user="otusapp", password=password, connect_timeout=3)) as connection:
            with connection:
                with connection.cursor() as cursor:
                    cursor.execute("INSERT INTO requests (backend) VALUES (%s) RETURNING id", (os.uname().nodename,))
                    request_id = cursor.fetchone()[0]
        if not os.path.isfile(STATIC):
            raise OSError("GFS2 static content missing")
        body = json.dumps({"backend": os.uname().nodename, "request_id": request_id, "database": "ok", "static": "gfs2"}).encode()
        start_response("200 OK", [("Content-Type", "application/json"), ("Content-Length", str(len(body))), ("X-Backend", os.uname().nodename)])
        return [body]
    except (OSError, psycopg2.Error):
        start_response("503 Service Unavailable", [("Content-Type", "application/json")])
        return [b'{"error":"database or shared storage unavailable"}']
