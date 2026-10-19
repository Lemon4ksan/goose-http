#!/usr/bin/env python3
"""Counts what h2c clients spend of h2.goose's flood budgets.

A proxy: it listens on LISTEN_PORT, passes each connection on to the server's
h2c port, and reads the frames both ways. For each client connection it
counts the frames that spend H2_CONTROL_* (PING and SETTINGS without ACK,
PRIORITY, DATA with no payload and no END_STREAM, and CONTINUATION with no
payload and no END_HEADERS) and those that spend H2_RESET_* (RST_STREAM on a
stream the server hadn't sent HEADERS on, an approximation of h2.goose's
"not answered"). At each close it prints a line: the frames by type, both
counts in all, and the most of each within any one second. Ctrl+C, or
SIGTERM, prints the most over every connection and stops.

    python3 bench/h2frames.py LISTEN_PORT SERVER_PORT
"""
import asyncio
import collections
import signal
import sys
import time

NAMES = {0: "DATA", 1: "HEADERS", 2: "PRIORITY", 3: "RST_STREAM", 4: "SETTINGS",
         5: "PUSH_PROMISE", 6: "PING", 7: "GOAWAY", 8: "WINDOW_UPDATE", 9: "CONTINUATION"}
PREFACE = b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
ACK, END_STREAM, END_HEADERS = 0x1, 0x1, 0x4

totals = {"connections": 0, "control": 0, "control_1s": 0, "resets": 0, "resets_1s": 0}


def frames(buf):
    """The whole frames at the front of buf, and the bytes they took."""
    out, at = [], 0
    while len(buf) - at >= 9:
        n = int.from_bytes(buf[at:at + 3], "big")
        if len(buf) - at < 9 + n:
            break
        kind, flags = buf[at + 3], buf[at + 4]
        sid = int.from_bytes(buf[at + 5:at + 9], "big") & 0x7FFFFFFF
        out.append((kind, flags, sid, n))
        at += 9 + n
    return out, at


def peak(times):
    """The most of times within any one second."""
    best, lo = 0, 0
    for hi, t in enumerate(times):
        while t - times[lo] > 1.0:
            lo += 1
        best = max(best, hi - lo + 1)
    return best


class Conn:
    def __init__(self):
        self.kinds = collections.Counter()
        self.control, self.resets = [], []
        self.answered = set()

    def client(self, kind, flags, sid, n):
        self.kinds[NAMES.get(kind, f"type{kind}")] += 1
        spends = (kind in (4, 6) and not flags & ACK) or kind == 2 or \
            (kind == 0 and n == 0 and not flags & END_STREAM) or \
            (kind == 9 and n == 0 and not flags & END_HEADERS)
        if spends:
            self.control.append(time.monotonic())
        if kind == 3 and sid not in self.answered:
            self.resets.append(time.monotonic())

    def server(self, kind, sid):
        if kind == 1:
            self.answered.add(sid)

    def report(self):
        c1, r1 = peak(self.control), peak(self.resets)
        totals["connections"] += 1
        for k, v in (("control", len(self.control)), ("control_1s", c1),
                     ("resets", len(self.resets)), ("resets_1s", r1)):
            totals[k] = max(totals[k], v)
        kinds = " ".join(f"{k}={v}" for k, v in sorted(self.kinds.items()))
        print(f"control {len(self.control)} (1 s: {c1}), resets {len(self.resets)} (1 s: {r1}); {kinds}",
              flush=True)


async def pipe(reader, writer, conn, from_client):
    buf = bytearray()
    started = not from_client
    try:
        while data := await reader.read(65536):
            writer.write(data)
            buf += data
            if not started:
                if len(buf) < len(PREFACE):
                    continue
                del buf[:len(PREFACE)]
                started = True
            got, used = frames(buf)
            del buf[:used]
            for kind, flags, sid, n in got:
                if from_client:
                    conn.client(kind, flags, sid, n)
                else:
                    conn.server(kind, sid)
            await writer.drain()
    except (ConnectionError, asyncio.IncompleteReadError):
        pass
    finally:
        writer.close()


async def main(listen, upstream):
    async def accept(cr, cw):
        try:
            sr, sw = await asyncio.open_connection("127.0.0.1", upstream)
        except OSError:
            cw.close()
            return
        conn = Conn()
        await asyncio.gather(pipe(cr, sw, conn, True), pipe(sr, cw, conn, False))
        conn.report()

    server = await asyncio.start_server(accept, "127.0.0.1", listen, backlog=4096)
    stop = asyncio.Event()
    for s in (signal.SIGINT, signal.SIGTERM):
        asyncio.get_running_loop().add_signal_handler(s, stop.set)
    print(f"h2frames: on {listen}, to {upstream}", flush=True)
    async with server:
        await stop.wait()
    print("most per connection: " + ", ".join(f"{k} {v}" for k, v in totals.items()), flush=True)


if __name__ == "__main__":
    asyncio.run(main(int(sys.argv[1]), int(sys.argv[2])))
