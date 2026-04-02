"""Echo node: forwards any incoming value and metadata unchanged."""

from adora import Node

node = Node()

for event in node:
    if event["type"] == "INPUT":
        node.send_output("data", event["value"], event["metadata"])
    elif event["type"] == "STOP":
        break
