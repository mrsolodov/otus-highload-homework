#!/usr/bin/env python3
"""Check Consul Raft, health-filtered DNS, and the two web endpoints."""
import argparse
import json
import random
import socket
import struct
import sys
from urllib.request import urlopen


WEB1 = "172.29.16.11"
WEB2 = "172.29.16.12"


def api(port, path):
    with urlopen(f"http://127.0.0.1:{port}/v1/{path}", timeout=5) as result:
        return json.load(result)


def dns(port):
    """Read A records from a direct UDP query, without an OS DNS cache."""
    identifier = random.randint(0, 65535)
    question = b"\x06portal\x07service\x06consul\x00" + struct.pack("!HH", 1, 1)
    packet = struct.pack("!HHHHHH", identifier, 0x0100, 1, 0, 0, 0) + question
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client:
        client.settimeout(5)
        client.sendto(packet, ("127.0.0.1", port))
        response, _ = client.recvfrom(4096)
    received_id, flags, questions, answers, _, _ = struct.unpack("!HHHHHH", response[:12])
    assert received_id == identifier and flags & 0x8000 and flags & 0x000F == 0, (flags, received_id)
    assert questions == 1, questions

    def skip_name(position):
        while True:
            length = response[position]
            if length == 0:
                return position + 1
            if length & 0xC0 == 0xC0:
                return position + 2
            position += length + 1

    cursor = skip_name(12) + 4
    addresses = set()
    for _ in range(answers):
        cursor = skip_name(cursor)
        record_type, record_class, _, length = struct.unpack("!HHIH", response[cursor:cursor + 10])
        cursor += 10
        if record_type == 1 and record_class == 1 and length == 4:
            addresses.add(socket.inet_ntoa(response[cursor:cursor + 4]))
        cursor += length
    return addresses


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--phase", choices=["initial", "web2-down", "restored", "consul1-down"], required=True)
    options = parser.parse_args()
    api_port, dns_port = (18501, 18601) if options.phase == "consul1-down" else (18500, 18600)
    leader = api(api_port, "status/leader")
    assert leader, "No elected Raft leader"
    peers = api(api_port, "operator/raft/configuration")["Servers"]
    assert len(peers) == 3 and all(peer["Voter"] for peer in peers), peers
    healthy = {entry["Service"]["Address"] for entry in api(api_port, "health/service/portal?passing=true")}
    records = dns(dns_port)
    expected = {WEB1} if options.phase == "web2-down" else {WEB1, WEB2}
    assert records == expected, f"DNS: {records}, expected: {expected}"
    assert healthy == expected, f"Healthy services: {healthy}, expected: {expected}"
    for address in expected:
        with urlopen(f"http://{address}/health", timeout=5) as response:
            assert response.status == 200
    print(f"{options.phase}: leader={leader}, raft voters=3, DNS={sorted(records)}, healthy={sorted(healthy)}", flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"Verification failed: {exc!r}", file=sys.stderr)
        sys.exit(1)
