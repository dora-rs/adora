"""Backward-compatible shim: ``from dora import Node`` works for dora-hub nodes.

This package re-exports the adora Python API under the ``dora`` namespace so
that existing dora-hub nodes and operators work without modification.
"""

from adora import *  # noqa: F401, F403
from adora import (
    Node,
    AdoraStatus,
    Ros2Context,
    Ros2Durability,
    Ros2Liveliness,
    Ros2Node,
    Ros2NodeOptions,
    Ros2Publisher,
    Ros2QosPolicies,
    Ros2Subscription,
    Ros2Topic,
)

# start_runtime is provided by the adora-cli package, not the node API.
try:
    from adora import start_runtime
except ImportError:
    pass

# Backward-compatible alias used by dora-hub operators.
DoraStatus = AdoraStatus
