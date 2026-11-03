#!/usr/bin/env python3
"""Verify index allocation and counts of Nginx events on both sources."""
import argparse
import json
import sys
from urllib.request import Request, urlopen


def request(path, query=None):
    body = json.dumps({"query": query}).encode() if query is not None else None
    req = Request(
        "http://127.0.0.1:19200" + path,
        data=body,
        headers={"Content-Type": "application/json"} if body else {},
    )
    with urlopen(req, timeout=10) as response:
        return json.load(response)


def count(host, uri=None):
    filters = [{"term": {"source_host": host}}]
    if uri:
        filters.append({"term": {"uri": uri}})
    return request(
        "/otus-web-*/_count", {"bool": {"filter": filters}}
    )["count"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--nodes", type=int, required=True)
    parser.add_argument("--minimum", type=int, required=True)
    parser.add_argument("--buffered", type=int, required=True)
    args = parser.parse_args()
    health = request("/_cluster/health/otus-web-*")
    assert health["status"] == "green", health
    assert health["number_of_nodes"] == args.nodes, health
    assert health["active_primary_shards"] >= 1, health
    assert health["active_shards"] >= 2, health
    request("/otus-web-*/_refresh")
    counts = {host: count(host) for host in ("web1", "web2")}
    buffered = {host: count(host, "/buffered") for host in ("web1", "web2")}
    assert all(value >= args.minimum for value in counts.values()), counts
    assert all(value == args.buffered for value in buffered.values()), buffered
    print(
        "Cluster: green, nodes={}, shards={}, counts={}, buffered={}".format(
            health["number_of_nodes"], health["active_shards"], counts, buffered
        ), flush=True
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print("Verification failed: {!r}".format(exc), file=sys.stderr)
        sys.exit(1)
