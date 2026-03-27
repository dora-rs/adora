"""Python receiver for cross-language test. Validates i64 Arrow arrays from Rust sender."""

import sys

from adora import Node


def main():
    node = Node()
    received_count = 0

    for event in node:
        if event["type"] == "INPUT" and event["id"] == "values":
            values = event["value"].to_pylist()
            if len(values) != 1:
                print(f"python-receiver: ERROR expected 1 element, got {len(values)}")
                sys.exit(1)
            expected = received_count * 10
            if values[0] != expected:
                print(f"python-receiver: ERROR expected {expected}, got {values[0]}")
                sys.exit(1)
            print(f"python-receiver: validated value {values[0]}")
            received_count += 1
        elif event["type"] == "STOP":
            break

    if received_count < 5:
        print(f"python-receiver: ERROR got only {received_count} messages from Rust sender (expected >= 5)")
        sys.exit(1)

    print(f"python-receiver: SUCCESS - validated {received_count} messages")


if __name__ == "__main__":
    main()
