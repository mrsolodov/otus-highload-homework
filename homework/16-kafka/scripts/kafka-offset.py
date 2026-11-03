#!/usr/bin/env python3
"""Read the total end offset of the three Kafka partitions."""
import subprocess
import sys

result = subprocess.run(
    [
        "docker", "compose", "exec", "-T", "kafka",
        "kafka-get-offsets", "--bootstrap-server", "kafka:9092",
        "--topic", "otus-web-logs",
    ],
    check=True, capture_output=True, text=True,
)
offsets = [int(line.rsplit(":", 1)[-1]) for line in result.stdout.splitlines()]
if len(offsets) != 3:
    raise RuntimeError("Expected three partitions: " + result.stdout)
total = sum(offsets)
if len(sys.argv) == 2 and total < int(sys.argv[1]):
    raise RuntimeError("Kafka offset {} is below {}".format(total, sys.argv[1]))
print(total)
