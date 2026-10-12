"""Checks a REST benchmark server's answers against the generator's dataset
files (task 021), before its load runs, as HttpArena's validate.sh does.

    python3 bench/rest/check.py PORT DATADIR [TIER]    (TIER: a, the default)

Tier A, HttpArena's production-stack: items and users by id, each with
servedAt within 2 s of now, 404 and 401 where the id or the user is missing,
and writes answered 204, or 422 for a body that isn't an object of name,
price, and quantity. Exits non-zero with a message on the first failure.
"""

import http.client
import json
import os
import random
import sys
import time

# A 147-byte token, as long as HttpArena's data/jwt-token.txt.
TOKEN = "Bearer " + "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI0MiIsImV4cCI6MTc5MDAwMDAwMH0" + "." + "x" * 70


def fail(msg):
    print(f"FAIL: {msg}")
    sys.exit(1)


class Server:
    def __init__(self, port):
        self.conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)

    def ask(self, method, path, body=None, headers=None):
        h = {"Authorization": TOKEN, "Accept-Encoding": "br;q=1, gzip;q=0.8"}
        h.update(headers or {})
        if body is not None:
            h["Content-Type"] = "application/json"
        self.conn.request(method, path, body=body, headers=h)
        r = self.conn.getresponse()
        return r.status, r.getheader("content-type"), r.read()


def record(status, ctype, body, want, what):
    """The response's record, checked against want with servedAt aside."""
    if status != 200 or not (ctype or "").startswith("application/json"):
        fail(f"{what}: {status} {ctype}")
    got = json.loads(body)
    served = got.pop("servedAt", None)
    if not isinstance(served, int) or abs(served - time.time()) > 2:
        fail(f"{what}: servedAt {served!r}")
    if got != want:
        fail(f"{what}: {got} != {want}")


def tier_a(port, data):
    items = json.load(open(os.path.join(data, "arena-items.json")))
    users = json.load(open(os.path.join(data, "arena-users.json")))
    s = Server(port)
    rng = random.Random(1)
    for i in [1, len(items)] + [rng.randint(1, len(items)) for _ in range(200)]:
        record(*s.ask("GET", f"/api/items/{i}"), items[i - 1], f"/api/items/{i}")
    for i in [1, len(users)] + [rng.randint(1, len(users)) for _ in range(50)]:
        record(*s.ask("GET", "/api/me", headers={"X-User-Id": str(i)}), users[i - 1], f"/api/me as {i}")
    for path, headers, want in [(f"/api/items/{len(items) + 1}", {}, 404), ("/api/items/0", {}, 404),
                                ("/api/items/x", {}, 404), ("/api/me", {}, 401),
                                ("/api/me", {"X-User-Id": str(len(users) + 1)}, 401)]:
        status, _, _ = s.ask("GET", path, headers=headers)
        if status != want:
            fail(f"GET {path} {headers}: {status}, want {want}")
    for body, want in [('{"name":"bench-updated","price":250,"quantity":10}', 204), ('{"price":1}', 204),
                       ("{}", 204), ('{"name":5}', 422), ('{"price":"x"}', 422), ("[1]", 422), ("{", 422)]:
        status, _, _ = s.ask("POST", "/api/items/7", body=body)
        if status != want:
            fail(f"POST /api/items/7 {body}: {status}, want {want}")
    print("tier a: ok")


def main():
    port, data = int(sys.argv[1]), sys.argv[2]
    tier = sys.argv[3] if len(sys.argv) > 3 else "a"
    {"a": tier_a}[tier](port, data)


if __name__ == "__main__":
    main()
