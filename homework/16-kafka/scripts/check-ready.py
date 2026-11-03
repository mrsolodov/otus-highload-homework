#!/usr/bin/env python3
"""Readiness probe used by the lab's bounded polling loops."""
import json
import sys
from urllib.request import urlopen

kind = sys.argv[1]
if kind == "cluster":
    expected = int(sys.argv[2])
    with urlopen(
        "http://127.0.0.1:19200/_cluster/health"
        "?wait_for_nodes={}&wait_for_status=green&timeout=3s".format(expected),
        timeout=8,
    ) as response:
        health = json.load(response)
    assert health["number_of_nodes"] == expected, health
    assert health["status"] == "green", health
elif kind == "kibana":
    with urlopen("http://127.0.0.1:15601/api/status", timeout=8) as response:
        status = json.load(response)
    assert status["status"]["overall"]["level"] == "available", status
else:
    raise ValueError(kind)
