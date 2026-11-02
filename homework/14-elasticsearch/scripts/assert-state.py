#!/usr/bin/env python3
"""Check cluster allocation and real requests from both frontends."""
import argparse
import json
import sys
from urllib.request import urlopen


def get(path):
    with urlopen("http://127.0.0.1:19200" + path, timeout=10) as response:
        return json.load(response)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--nodes", type=int, required=True)
    parser.add_argument("--minimum", type=int, required=True)
    args = parser.parse_args()
    health = get("/_cluster/health/otus-web-*")
    assert health["status"] == "green", health
    assert health["number_of_nodes"] == args.nodes, health
    assert health["active_primary_shards"] >= 1, health
    assert health["active_shards"] >= 2, health
    get("/otus-web-*/_refresh")
    counts = {}
    for host in ("web1", "web2"):
        result = get(
            "/otus-web-*/_count?q=source_host%3A" + host
        )
        counts[host] = result["count"]
        assert counts[host] >= args.minimum, (host, result)
    print(
        "Cluster: green, nodes={}, shards={}, web1={}, web2={}".format(
            health["number_of_nodes"],
            health["active_shards"],
            counts["web1"],
            counts["web2"],
        ),
        flush=True,
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print("Verification failed: {!r}".format(exc), file=sys.stderr)
        sys.exit(1)
