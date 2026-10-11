"""Test clients for the HTTP server, run by scripts/test-http.sh.

    http_client.py PORT tfb         TechEmpower's plaintext and JSON checks
    http_client.py PORT pipeline    pipelined requests and request bodies
    http_client.py PORT large       responses larger than the write buffer
    http_client.py PORT chunked     chunked request bodies, and HttpArena's /baseline11
    http_client.py PORT keepalive   keep-alive, Connection: close, HTTP/1.0
    http_client.py PORT hostile     malformed and oversized requests
    http_client.py PORT slow        slow clients, against the server's timeouts
    http_client.py PORT many N      N connections at once, each pipelining
    http_client.py PORT emfile N    N connections to a server with fewer fds

Each check exits non-zero with a message on the first failure. SERVER_NAME
is the Server field tfb expects (goose), for checking the servers in bench/.
"""

import asyncio
import email.utils
import json
import os
import socket
import sys
import threading
import time

HOST = "127.0.0.1"
SERVER_NAME = os.environ.get("SERVER_NAME", "goose")
# The server's request_ms and idle_ms (Config, src/app.goose), in seconds.
REQUEST_TIMEOUT = 10
# What TechEmpower's load generator sends with each request.
TFB_HEADERS = (
    b"Host: tfb-server\r\n"
    b"Accept: text/plain,text/html;q=0.9,application/xhtml+xml;q=0.9,"
    b"application/xml;q=0.8,*/*;q=0.7\r\n"
    b"Connection: keep-alive\r\n"
)


def fail(msg):
    print(f"FAIL: {msg}")
    sys.exit(1)


def request(path, method=b"GET", extra=b"", version=b"HTTP/1.1"):
    return method + b" " + path + b" " + version + b"\r\n" + TFB_HEADERS + extra + b"\r\n"


class Response:
    def __init__(self, status, headers, body):
        self.status = status
        self.headers = headers  # lowercased names, in order
        self.body = body

    def header(self, name):
        values = [v for n, v in self.headers if n == name]
        if len(values) != 1:
            fail(f"{len(values)} {name} fields in {self.headers}")
        return values[0]


class Conn:
    """A blocking connection that reads responses one at a time."""

    def __init__(self, port, timeout=5, rcvbuf=0):
        self.sock = socket.socket()
        # Before connecting, so that the window starts small.
        if rcvbuf:
            self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, rcvbuf)
        self.sock.settimeout(timeout)
        self.sock.connect((HOST, port))
        self.buf = b""

    def send(self, data):
        self.sock.sendall(data)

    def fill(self):
        chunk = self.sock.recv(65536)
        if not chunk:
            fail(f"connection closed with {len(self.buf)} bytes unparsed")
        self.buf += chunk

    def response(self, head_only=False):
        while b"\r\n\r\n" not in self.buf:
            self.fill()
        head, self.buf = self.buf.split(b"\r\n\r\n", 1)
        lines = head.split(b"\r\n")
        version, status, _ = lines[0].split(b" ", 2)
        if version != b"HTTP/1.1":
            fail(f"status line {lines[0]!r}")
        headers = []
        for line in lines[1:]:
            name, value = line.split(b":", 1)
            headers.append((name.decode().lower(), value.strip().decode()))
        r = Response(int(status), headers, b"")
        n = 0 if head_only else int(r.header("content-length"))
        while len(self.buf) < n:
            self.fill()
        r.body, self.buf = self.buf[:n], self.buf[n:]
        return r

    def closed(self):
        """Whether the server closes the connection, sending nothing more."""
        try:
            while True:
                chunk = self.sock.recv(65536)
                if not chunk:
                    return not self.buf
                self.buf += chunk
        except (socket.timeout, TimeoutError):
            return False
        except ConnectionResetError:
            return not self.buf

    def close(self):
        self.sock.close()


def check_tfb(r, ctype, now):
    """The response checks of TechEmpower's verifier for both tests."""
    if r.status != 200:
        fail(f"status {r.status}")
    if r.header("server") != SERVER_NAME:
        fail(f"Server {r.header('server')}")
    if r.header("content-type") != ctype:
        fail(f"Content-Type {r.header('content-type')}")
    if int(r.header("content-length")) != len(r.body):
        fail("Content-Length doesn't match the body")
    date = r.header("date")
    parsed = email.utils.parsedate_to_datetime(date)
    if email.utils.format_datetime(parsed, usegmt=True) != date:
        fail(f"Date isn't an IMF-fixdate: {date}")
    if abs(parsed.timestamp() - now) > 2:
        fail(f"Date is {parsed.timestamp() - now:.0f} s off: {date}")


def tfb(port):
    c = Conn(port)
    c.send(request(b"/plaintext"))
    r = c.response()
    check_tfb(r, "text/plain", time.time())
    if r.body != b"Hello, World!":
        fail(f"plaintext body {r.body!r}")
    c.send(request(b"/json"))
    r = c.response()
    check_tfb(r, "application/json", time.time())
    if json.loads(r.body) != {"message": "Hello, World!"}:
        fail(f"json body {r.body!r}")
    # The Date field moves on with the clock.
    first = r.header("date")
    time.sleep(1.1)
    c.send(request(b"/json"))
    if c.response().header("date") == first:
        fail("Date didn't change after a second")
    c.close()
    print("tfb: ok")


def pipeline(port):
    # 16 requests in one write, as TechEmpower's plaintext test sends them,
    # answered in order.
    c = Conn(port)
    paths = [b"/plaintext", b"/json", b"/nope"] * 5 + [b"/plaintext"]
    c.send(b"".join(request(p) for p in paths))
    for p in paths:
        r = c.response()
        want = {b"/plaintext": 200, b"/json": 200, b"/nope": 404}[p]
        if r.status != want:
            fail(f"{p} answered {r.status}")
    # A request split at every byte, and bodies, small and large, read and
    # dropped between pipelined requests.
    for b in request(b"/plaintext"):
        c.send(bytes([b]))
    if c.response().status != 200:
        fail("byte-at-a-time request")
    body = bytes(range(256)) * 2000
    c.send(request(b"/json", b"POST", b"Content-Length: 5\r\n") + b"hello" +
           request(b"/json", b"POST", b"Content-Length: %d\r\n" % len(body)))
    for i in range(0, len(body), 30000):
        c.send(body[i:i + 30000])
    c.send(request(b"/plaintext"))
    for want in (405, 405, 200):
        r = c.response()
        if r.status != want:
            fail(f"after a body: {r.status}, want {want}")
    # More pipelined responses than the write buffer holds at once.
    c.send(request(b"/json") * 500)
    for i in range(500):
        if c.response().status != 200:
            fail("500 pipelined requests")
    c.close()
    # A client that sends all its requests, then reads the responses only
    # after the server's send has blocked: the server goes on once the
    # socket takes more, with no request left to wake it. Blocking it takes
    # megabytes on loopback, where the receive buffers grow, and the requests
    # must fit the server's, or the client blocks too: it starts reading
    # after 2 s either way.
    n = 20000
    c = Conn(port, rcvbuf=4096)
    sender = threading.Thread(target=c.send, args=(request(b"/json") * n,))
    sender.start()
    sender.join(2)
    for i in range(n):
        if c.response().status != 200:
            fail("a client that reads late")
    sender.join()
    c.close()
    print("pipeline: ok")


def large(port):
    def check(r, n):
        if r.status != 200:
            fail(f"/bytes?n={n} answered {r.status}")
        want = (b"0123456789" * (n // 10 + 1))[:n]
        if r.body != want:
            fail(f"/bytes?n={n}: {len(r.body)} bytes, not the ones sent")

    # Responses larger than the server's 8 KB write buffer: alone, and
    # pipelined between small ones, answered in order.
    c = Conn(port)
    for n in (5000, 8192, 8193, 100000):
        c.send(request(b"/bytes?n=%d" % n))
        check(c.response(), n)
    sizes = [None, 6000, None, 300000, 20000, None]
    c.send(b"".join(request(b"/plaintext") if n is None else request(b"/bytes?n=%d" % n)
                    for n in sizes))
    for n in sizes:
        r = c.response()
        if n is None:
            if r.status != 200 or r.body != b"Hello, World!":
                fail(f"/plaintext between large responses: {r.status} {r.body!r}")
        else:
            check(r, n)
    c.close()
    # 4 MB to a client that starts reading only after the server's send has
    # blocked, and a request after it on the same connection.
    c = Conn(port, rcvbuf=4096)
    c.send(request(b"/bytes?n=4000000") + request(b"/json"))
    time.sleep(1)
    check(c.response(), 4000000)
    if c.response().status != 200:
        fail("a request after a 4 MB response")
    c.close()
    print("large: ok")


def chunked(port):
    def te(body):
        return request(b"/json", b"POST", b"Transfer-Encoding: chunked\r\n") + body

    # Chunked bodies, with an extension and a trailer field, dropped between
    # pipelined requests, and one sent a byte at a time.
    c = Conn(port)
    c.send(te(b"5\r\nhello\r\n0\r\n\r\n") +
           te(b"3;x=y\r\nabc\r\nA\r\n0123456789\r\n0\r\nT: v\r\n\r\n") +
           request(b"/plaintext"))
    for want in (405, 405, 200):
        r = c.response()
        if r.status != want:
            fail(f"after a chunked body: {r.status}, want {want}")
    for b in te(b"2\r\nhi\r\n0\r\n\r\n"):
        c.send(bytes([b]))
    if c.response().status != 405:
        fail("byte-at-a-time chunked body")
    # HttpArena's baseline: a + b, plus the body of a POST, whichever framing.
    for req, want in (
        (request(b"/baseline11?a=13&b=42"), b"55"),
        (request(b"/baseline11?b=-2&a=5&c=9"), b"3"),
        (request(b"/baseline11?a=13&b=42", b"POST", b"Content-Length: 2\r\n") + b"20", b"75"),
        (request(b"/baseline11?a=13&b=42", b"POST", b"Transfer-Encoding: chunked\r\n") +
         b"1\r\n2\r\n1\r\n0\r\n0\r\n\r\n", b"75"),
    ):
        c.send(req)
        r = c.response()
        if r.status != 200 or r.body != want:
            fail(f"{req!r}: {r.status} {r.body!r}, want {want!r}")
    c.close()
    print("chunked: ok")


def keepalive(port):
    c = Conn(port)
    c.send(b"GET /plaintext HTTP/1.0\r\n\r\n")
    r = c.response()
    if r.status != 200 or r.header("connection") != "close" or not c.closed():
        fail("HTTP/1.0 without keep-alive stayed open")
    c = Conn(port)
    for _ in range(2):
        c.send(b"GET /plaintext HTTP/1.0\r\nConnection: keep-alive\r\n\r\n")
        r = c.response()
        if r.status != 200 or r.header("connection") != "keep-alive":
            fail("HTTP/1.0 keep-alive")
    c.close()
    c = Conn(port)
    c.send(request(b"/plaintext") + request(b"/json", extra=b"Connection: close\r\n") +
           request(b"/plaintext"))
    c.response()
    if c.response().header("connection") != "close" or not c.closed():
        fail("Connection: close left the connection open, or answered past it")
    c = Conn(port)
    c.send(b"HEAD /plaintext HTTP/1.1\r\nHost: x\r\n\r\n")
    r = c.response(head_only=True)
    if r.status != 200 or r.header("content-length") != "13":
        fail("HEAD")
    c.send(request(b"/json"))
    if c.response().status != 200:
        fail("a request after HEAD")
    print("keepalive: ok")


def hostile(port):
    big = b"x" * 20000
    cases = [
        ("bare LF", b"GET /plaintext HTTP/1.1\nHost: x\n\n", 400),
        ("bare LF after the headers", b"GET /plaintext HTTP/1.1\r\nHost: x\r\n\n", 400),
        ("missing version", b"GET /plaintext\r\n\r\n", 400),
        ("missing target", b"GET HTTP/1.1\r\nHost: x\r\n\r\n", 400),
        ("no Host", b"GET /plaintext HTTP/1.1\r\n\r\n", 400),
        ("NUL in a value", b"GET / HTTP/1.1\r\nHost: x\r\nX: a\x00b\r\n\r\n", 400),
        ("space before a colon", b"GET / HTTP/1.1\r\nHost : x\r\n\r\n", 400),
        ("folded line", b"GET / HTTP/1.1\r\nHost: x\r\nX: a\r\n b\r\n\r\n", 400),
        ("bad Content-Length", b"POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 1a\r\n\r\n", 400),
        ("two Content-Lengths",
         b"POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\nab", 400),
        ("binary", bytes(range(256)), 400),
        ("TLS hello", b"\x16\x03\x01\x02\x00\x01\x00\x01\xfc\x03\x03" + b"\x00" * 40, 400),
        ("HTTP/2 preface", b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n", 505),
        ("gzip coding", b"POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: gzip, chunked\r\n\r\n"
                        b"5\r\nhello\r\n0\r\n\r\n", 501),
        ("chunked and Content-Length",
         b"POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nContent-Length: 5\r\n\r\n"
         b"0\r\n\r\n", 400),
        ("bad chunk size", b"POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n"
                           b"5x\r\nhello\r\n0\r\n\r\n", 400),
        ("chunked body past the buffer",
         b"POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n"
         b"4000\r\n" + b"x" * 0x4000 + b"\r\n0\r\n\r\n", 413),
        ("huge body", b"POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 2000000000\r\n\r\n", 413),
        ("long target", b"GET /" + big + b" HTTP/1.1\r\nHost: x\r\n\r\n", 414),
        ("huge header", b"GET / HTTP/1.1\r\nHost: x\r\nX: " + big + b"\r\n\r\n", 431),
        ("huge header count",
         b"GET / HTTP/1.1\r\nHost: x\r\n" + b"X: y\r\n" * 5000 + b"\r\n", 431),
        ("endless empty lines", b"\r\n" * 10000, 431),
    ]
    for name, data, want in cases:
        c = Conn(port)
        c.send(data)
        r = c.response()
        if r.status != want:
            fail(f"{name}: {r.status}, want {want}")
        if r.header("connection") != "close" or not c.closed():
            fail(f"{name}: the connection stayed open")
        c.close()
        print(f"hostile: {name}: {want}")
    # A refused request after good ones still gets the good ones answered.
    c = Conn(port)
    c.send(request(b"/plaintext") + b"GET /\r\n\r\n" + request(b"/plaintext"))
    if c.response().status != 200 or c.response().status != 400 or not c.closed():
        fail("a refusal in a pipeline")
    print("hostile: ok")


def slow(port):
    """Runs the slow clients at once, so the run takes one timeout."""
    errors = []
    t0 = time.time()

    def slowloris():
        # The first bytes of a request, then nothing: 408 once the request
        # timeout has passed since the first byte, however the bytes trickle.
        c = Conn(port, timeout=REQUEST_TIMEOUT + 5)
        c.send(b"GET /plaintext HTTP/1.1\r\n")
        for _ in range(3):
            time.sleep(2)
            c.send(b"X: y\r\n")
        r = c.response()
        took = time.time() - t0
        if r.status != 408 or not c.closed() or not REQUEST_TIMEOUT - 1 < took < REQUEST_TIMEOUT + 3:
            errors.append(f"slowloris: {r.status} after {took:.1f} s")

    def silent():
        # A connection that sends nothing is closed after the request timeout.
        c = Conn(port, timeout=REQUEST_TIMEOUT + 5)
        if not c.closed():
            errors.append("silent connection left open")
        took = time.time() - t0
        if not REQUEST_TIMEOUT - 1 < took < REQUEST_TIMEOUT + 3:
            errors.append(f"silent connection closed after {took:.1f} s")

    def steady():
        # A slow client that finishes a request every 3 s is never cut off.
        c = Conn(port)
        for _ in range(5):
            c.send(request(b"/plaintext"))
            if c.response().status != 200:
                errors.append("steady client refused")
            time.sleep(3)

    def no_reader():
        # Pipelines without reading. The server stops reading once its
        # buffers and the socket's are full, and closes it after the timeout.
        c = Conn(port, timeout=REQUEST_TIMEOUT + 5)
        sent = 0
        try:
            while time.time() - t0 < REQUEST_TIMEOUT + 4:
                sent += c.sock.send(request(b"/plaintext") * 1000)
            errors.append(f"no-reader still open after {sent} bytes")
        except (socket.timeout, TimeoutError):
            errors.append(f"no-reader still open after {sent} bytes")
        except (BrokenPipeError, ConnectionResetError):
            pass

    def counted(f):
        # A client that dies before its checks is a failure too.
        def run():
            try:
                f()
            except (Exception, SystemExit) as e:
                errors.append(f"{f.__name__}: {e!r}")
        return run

    threads = [threading.Thread(target=counted(f)) for f in (slowloris, silent, steady, no_reader)]
    for t in threads:
        t.start()
    # Others are served meanwhile.
    time.sleep(1)
    c = Conn(port)
    c.send(request(b"/json"))
    if c.response().status != 200:
        fail("a client during the slow ones")
    for t in threads:
        t.join()
    if errors:
        fail("; ".join(errors))
    print("slow: ok")


def emfile(port, n):
    """For a server with a low fd limit: n clients, more than it can hold.
    Those past the limit wait in the listen backlog until others close."""
    conns = [Conn(port, timeout=1) for _ in range(n)]
    for c in conns:
        c.send(request(b"/plaintext"))
    served = 0
    try:
        for c in conns:
            c.response()
            served += 1
    except (socket.timeout, TimeoutError):
        pass
    if not 0 < served < n:
        fail(f"{served} of {n} served before any closed")
    for c in conns[:served]:
        c.close()
    for c in conns[served:]:
        c.sock.settimeout(5)
        if c.response().status != 200:
            fail("a client from the backlog")
        c.close()
    print(f"emfile: {served} served at the fd limit, then the other {n - served}")


def many(port, n):
    async def client(i):
        reader, writer = await asyncio.open_connection(HOST, port)
        path = b"/json" if i % 2 else b"/plaintext"
        writer.write(request(path) * 4)
        await writer.drain()
        for _ in range(4):
            head = await reader.readuntil(b"\r\n\r\n")
            # The reason phrase means nothing (RFC 9112 §4), and servers differ in it.
            if head.split(b" ", 2)[:2] != [b"HTTP/1.1", b"200"]:
                fail(f"client {i}: {head[:40]!r}")
            length = [l for l in head.split(b"\r\n") if l.lower().startswith(b"content-length:")]
            await reader.readexactly(int(length[0].split(b":")[1]))
        return writer

    async def run():
        # All connections open at once before any closes.
        writers = await asyncio.gather(*(client(i) for i in range(n)))
        for w in writers:
            w.close()

    asyncio.run(run())
    print(f"many: {n} connections ok")


def main():
    port = int(sys.argv[1])
    mode = sys.argv[2]
    if mode in ("many", "emfile"):
        {"many": many, "emfile": emfile}[mode](port, int(sys.argv[3]))
    else:
        {"tfb": tfb, "pipeline": pipeline, "large": large, "chunked": chunked, "keepalive": keepalive,
         "hostile": hostile, "slow": slow}[mode](port)


if __name__ == "__main__":
    main()
