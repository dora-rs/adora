"""Sender node: emits a fixed PyArrow array every 500ms."""

import pyarrow as pa
from adora import Node

node = Node()

for event in node:
    if event["type"] == "INPUT":
        node.send_output("data", pa.array([1, 2, 3, 4, 5]), event["metadata"])
    elif event["type"] == "STOP":
        break
