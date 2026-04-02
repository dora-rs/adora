"""Sender node: emits nanosecond timestamps at 10ms intervals (synchronous)."""

import time

import numpy as np
import pyarrow as pa
from adora import Node

node = Node()

i = 0
for event in node:
    if event["type"] == "INPUT":
        if i == 100:
            break
        i += 1
        now = time.perf_counter_ns()
        node.send_output("data", pa.array([np.uint64(now)]))
    elif event["type"] == "STOP":
        break
