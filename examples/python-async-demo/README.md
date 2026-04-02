# Python Async Demo

Minimal example showing how to consume Adora events using native `async/await` via `node.recv_async()`.

## Architecture

```
timer (10ms) --> send_data --> data --> receive_data_with_sleep (async)
```

## Nodes

**send_data** (`send_data.py`) — Synchronous sender. Triggered every 10 ms by the built-in timer, sends 100 messages each containing a `uint64` nanosecond timestamp. Uses the standard `for event in node` loop.

**receive_data_with_sleep** (`receive_data.py`) — Asynchronous receiver. Calls `await node.recv_async()` inside an `asyncio` event loop to consume events without blocking the loop. Reads 100 events then prints `done!` and exits.

```python
async def main():
    node = Node()
    for _ in range(100):
        event = await node.recv_async()
        print(event)
    print("done!")
```

## Prerequisites

```bash
pip install adora-rs numpy pyarrow
```

> **Note:** The PyPI package is `adora-rs`, not `adora`.

## Run

```bash
adora run dataflow.yaml
```

## When to Use `recv_async()`

Use `recv_async()` when your node needs to:
- Perform async I/O (HTTP, gRPC, database) alongside event processing
- Run multiple concurrent tasks with `asyncio.gather`
- Integrate with async libraries (`aiohttp`, `asyncpg`, etc.)

For simple sequential processing the synchronous `for event in node` loop is simpler and preferred.

## What This Demonstrates

| Feature | Where |
|---------|-------|
| `await node.recv_async()` | Receiver |
| asyncio event loop integration | Receiver |
| Mixed sync sender + async receiver | Both nodes |
| `np.uint64` timestamp serialization | Sender |
