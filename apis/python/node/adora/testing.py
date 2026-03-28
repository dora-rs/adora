"""Test utilities for adora Python nodes.

Provides MockNode, a drop-in replacement for adora.Node that works
without a running daemon. Use it to unit test node logic with
deterministic inputs and captured outputs.

Usage:
    from adora.testing import MockNode
    import pyarrow as pa

    def test_my_node():
        node = MockNode([("tick", pa.array([0]))])
        for event in node:
            if event["type"] == "INPUT":
                node.send_output("result", pa.array([42]))
        assert node.outputs["result"][0].to_pylist() == [42]
"""

from __future__ import annotations

from typing import Any

import pyarrow as pa


class MockNode:
    """Drop-in replacement for adora.Node usable in unit tests.

    Args:
        inputs: List of (input_id, pyarrow.Array) tuples. Each becomes an
            INPUT event. A STOP event is automatically appended.
        metadata: Optional dict of metadata to attach to each input event.
    """

    def __init__(
        self,
        inputs: list[tuple[str, pa.Array]],
        metadata: dict[str, Any] | None = None,
    ):
        events: list[dict[str, Any]] = []
        for input_id, data in inputs:
            events.append(
                {
                    "type": "INPUT",
                    "id": input_id,
                    "value": data,
                    "metadata": metadata or {},
                }
            )
        events.append({"type": "STOP"})
        self._events = iter(events)
        self.outputs: dict[str, list[pa.Array]] = {}

    def __iter__(self):
        return self

    def __next__(self) -> dict[str, Any]:
        return next(self._events)

    def next(self, timeout: float = None) -> dict[str, Any] | None:
        """Return the next event, or None if exhausted."""
        try:
            return next(self._events)
        except StopIteration:
            return None

    def send_output(
        self,
        output_id: str,
        data: pa.Array,
        metadata: dict[str, Any] | None = None,
    ) -> None:
        """Capture an output for later assertion."""
        self.outputs.setdefault(output_id, []).append(data)
