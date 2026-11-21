import hashlib
import json
import logging
import os
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import psycopg


logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
CREDS_FILE = Path(os.environ.get("NOMAD_SECRETS_DIR", "/secrets")) / "db.json"
lock = threading.Lock()
current = None


def reload_credentials():
    global current
    try:
        data = json.loads(CREDS_FILE.read_text(encoding="utf-8"))
        username, password = data["username"], data["password"]
        if not username or not password:
            raise ValueError("empty credential")
        fingerprint = hashlib.sha256(username.encode()).hexdigest()[:12]
        with lock:
            if current and current[1:] == (username, password):
                return
            current = (fingerprint, username, password)
        logging.info("db credentials loaded user_fingerprint=%s", fingerprint)
    except (OSError, ValueError, KeyError, json.JSONDecodeError):
        logging.exception("could not load db credentials")


def watch_credentials():
    while True:
        reload_credentials()
        time.sleep(2)


def db_query(write_visit):
    with lock:
        creds = current
    if creds is None:
        raise RuntimeError("credentials unavailable")
    fingerprint, username, password = creds
    with psycopg.connect(
        host=os.environ["DB_HOST"],
        port=int(os.environ.get("DB_PORT", "5432")),
        dbname=os.environ["DB_NAME"],
        user=username,
        password=password,
        connect_timeout=3,
    ) as conn:
        with conn.cursor() as cursor:
            if write_visit:
                cursor.execute("INSERT INTO visits DEFAULT VALUES RETURNING id")
                visit_id = cursor.fetchone()[0]
            else:
                cursor.execute("SELECT 1")
                visit_id = None
    return fingerprint, visit_id


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path not in ("/", "/health"):
            self.send_error(404)
            return
        try:
            fingerprint, visit_id = db_query(self.path == "/")
        except (psycopg.Error, RuntimeError, KeyError):
            logging.exception("database request failed")
            self.send_error(503, "database unavailable")
            return
        if self.path == "/health":
            body = b"ok\n"
            content_type = "text/plain; charset=utf-8"
        else:
            body = (f"<h1>OTUS portal</h1><p>Visit #{visit_id}</p>"
                    f"<p>DB user fingerprint: {fingerprint}</p>").encode()
            content_type = "text/html; charset=utf-8"
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


threading.Thread(target=watch_credentials, daemon=True).start()
ThreadingHTTPServer(("0.0.0.0", int(os.environ.get("PORT", "8080"))), Handler).serve_forever()
