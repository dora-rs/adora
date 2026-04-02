"""Receiver node: consumes events using native async/await via node.recv_async()."""

import asyncio

from adora import Node


async def main():
    node = Node()
    for _ in range(100):
        event = await node.recv_async()
        print(event)
    print("done!")


if __name__ == "__main__":
    loop = asyncio.get_event_loop()
    loop.run_until_complete(main())
