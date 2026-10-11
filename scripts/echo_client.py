#!/usr/bin/env python3
"""Test client for the echo servers in server/echo.goose.

    echo_client.py PORT ping            one short line, echoed back
    echo_client.py PORT cut [ROUNDS]    clients that hang up while the server writes
    echo_client.py PORT many N BYTES    N clients at once, BYTES random bytes each

Exits nonzero on the first mismatch, error, or timeout.
"""
import asyncio
import os
import socket
import sys
import time

HOST = "127.0.0.1"


def ping(port):
    with socket.create_connection((HOST, port), timeout=5) as s:
        s.sendall(b"ping\n")
        got = b""
        while len(got) < 5:
            chunk = s.recv(16)
            if not chunk:
                break
            got += chunk
    if got != b"ping\n":
        sys.exit(f"ping: got {got!r}")
    print("ping: ok")


def fill(s):
    """Sends until the kernel won't take more, and returns the byte count."""
    sent = 0
    block = b"x" * 65536
    while True:
        try:
            sent += s.send(block)
        except BlockingIOError:
            return sent


def cut(port, rounds):
    # Even rounds send without reading until both directions' buffers are
    # full, so the server is blocked in send or holding unsent bytes, then
    # close with unread data. That resets the connection under the server,
    # whose send fails with ECONNRESET.
    #
    # Odd rounds send 24 KB, two of the server's reads, and close before the
    # echo arrives. The close is a FIN, the server's first send draws a reset
    # in CLOSE_WAIT, and its second send fails with EPIPE: the one error that
    # raises SIGPIPE unless the server sends with MSG_NOSIGNAL.
    for i in range(rounds):
        s = socket.create_connection((HOST, port), timeout=5)
        if i % 2:
            sent = 24576
            s.sendall(b"x" * sent)
        else:
            s.setblocking(False)
            sent = fill(s)
            time.sleep(0.1)
            sent += fill(s)
        s.close()
        print(f"cut {i}: closed after sending {sent} bytes")
        time.sleep(0.1)
    ping(port)


async def one_client(port, size):
    payload = os.urandom(size)
    reader, writer = await asyncio.open_connection(HOST, port)

    async def send():
        for off in range(0, size, 65536):
            writer.write(payload[off:off + 65536])
            await writer.drain()

    async def receive():
        got = bytearray()
        while len(got) < size:
            chunk = await reader.read(65536)
            if not chunk:
                break
            got += chunk
        return bytes(got)

    _, got = await asyncio.gather(send(), receive())
    writer.close()
    await writer.wait_closed()
    return got == payload


async def many(port, n, size):
    start = time.monotonic()
    results = await asyncio.wait_for(
        asyncio.gather(*(one_client(port, size) for _ in range(n))), timeout=120)
    bad = results.count(False)
    took = time.monotonic() - start
    if bad:
        sys.exit(f"many: {bad} of {n} clients got a different echo")
    print(f"many: {n} clients x {size} bytes echoed in {took:.2f} s")


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    port, cmd, rest = int(sys.argv[1]), sys.argv[2], sys.argv[3:]
    if cmd == "ping":
        ping(port)
    elif cmd == "cut":
        cut(port, int(rest[0]) if rest else 6)
    elif cmd == "many":
        asyncio.run(many(port, int(rest[0]), int(rest[1])))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
