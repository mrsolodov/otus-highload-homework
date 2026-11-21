#!/usr/bin/env python3
"""Observe successful portal requests across at least one Vault credential change."""

import argparse
import datetime as dt
import re
import time
import urllib.error
import urllib.request


parser = argparse.ArgumentParser()
parser.add_argument("url", help="URL of one portal allocation, for example http://127.0.0.1:20000/")
parser.add_argument("--seconds", type=int, default=270)
args = parser.parse_args()
if args.seconds < 130:
    parser.error("use at least 130 seconds to cover one 120-second lease")

fingerprints = []
deadline = time.monotonic() + args.seconds
while time.monotonic() < deadline:
    stamp = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")
    try:
        with urllib.request.urlopen(args.url, timeout=5) as response:
            body = response.read().decode("utf-8")
            match = re.search(r"DB user fingerprint: ([0-9a-f]{12})", body)
            if not match:
                raise ValueError("fingerprint missing from portal response")
            fingerprint = match.group(1)
            fingerprints.append(fingerprint)
            print(f"{stamp} status={response.status} fingerprint={fingerprint}", flush=True)
    except (urllib.error.URLError, ValueError) as exc:
        print(f"{stamp} request_failed={type(exc).__name__}", flush=True)
    time.sleep(min(10, max(0, deadline - time.monotonic())))

if len(set(fingerprints)) < 2:
    raise SystemExit("FAIL: no credential change observed")
print(f"PASS: observed {len(set(fingerprints))} distinct DB users with successful requests", flush=True)
