"""Offers a REST tier's requests at a fixed rate with zrk (task 021), one zrk
process per route, each at its route's share of the tier's wrk mix, and
writes each process's JSON report.

    python3 bench/rest/rate.py ZRK URL DATADIR TIER RATE DURATION CPUS OUT

zrk sends one request per process, so each route repeats one request: the
dataset's first user, token, week, and ids. Tier B's timer start and stop,
4% of tier-b.lua's mix, which pair up per user, go to its PATCH instead. TIER
c is also the mixed run's reads, against a server with TIER=d. The
connections, 256 in all, and zrk's threads, 12 in all, go by share, at least
8 connections and 1 thread each. OUT is a path prefix: OUT.ROUTE.json.
"""

import subprocess
import sys
import time

CONNS = 256
THREADS = 12

TOKEN_A = ("Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
           "eyJzdWIiOiI0MiIsImV4cCI6MTc5MDAwMDAwMH0." + "x" * 70)


def load(path):
    with open(path) as f:
        return [line.rstrip("\n").split("\t") for line in f if line.strip()]


def tier_a(data):
    h = {"Authorization": TOKEN_A, "Accept-Encoding": "br;q=1, gzip;q=0.8"}
    body = '{"name":"bench-updated","price":250,"quantity":10}'
    return [
        ("item", 78, "GET", "/api/items/4242", h, None),
        ("me", 16, "GET", "/api/me", dict(h, **{"X-User-Id": "42"}), None),
        ("write", 6, "POST", "/api/items/7", dict(h, **{"Content-Type": "application/json"}), body),
    ]


def tier_b(data):
    cookie, user, org, entry, start, end = load(f"{data}/snow-load.txt")[0][:6]

    def h(kind, body=False):
        d = {"Cookie": cookie, "Accept": "*/*", "Origin": "https://time.bench.example.com",
             "Sec-Fetch-Site": "same-origin", "User-Agent": "snowtime-bench (k6)",
             "CF-Connecting-IP": "10.0.0.0", "X-Bench-Kind": kind + " api", "X-Bench-Step": "steady"}
        if body:
            d["Content-Type"] = "application/json"
        return d

    return [
        ("session", 25, "GET", "/api/v1/session", h("return"), None),
        ("timer", 25, "GET", "/api/v1/timer", h("return"), None),
        ("entries", 25, "GET", f"/api/v1/organizations/{org}/entries?from={start}&to={end}&userId={user}",
         h("return"), None),
        ("projects", 15, "GET", f"/api/v1/organizations/{org}/projects?includeArchived=true", h("sign-in"), None),
        ("patch", 10, "PATCH", f"/api/v1/organizations/{org}/entries/{entry}", h("edit", True),
         '{"description":"Benchmark edit"}'),
    ]


def tier_c(data):
    rows = load(f"{data}/heavy-load.txt")
    token = next(r[1] for r in rows if r[0] == "token")
    week = next(r[1:3] for r in rows if r[0] == "week")
    epoch = int(next(r[1] for r in rows if r[0] == "version0"))
    ranges = {r[0]: (int(r[1]), int(r[2])) for r in rows if r[0] in ("encounters", "history", "clients")}
    enc = sum(ranges["encounters"]) // 2
    client = ranges["history"][0] + 41
    other = ranges["clients"][0] + 6
    since = int((time.time() * 1000 - epoch) // 60000) - 1
    staff = "1,2,3,4,5,6,7,8,9,10"

    def h(referer):
        return {
            "Authorization": "Bearer " + token,
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
                          "(KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36",
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "et-EE,et;q=0.9,en-US;q=0.8,en;q=0.7",
            "Accept-Encoding": "gzip, deflate, br, zstd",
            "Origin": "https://clinic.bench.example.com",
            "Referer": "https://clinic.bench.example.com" + referer,
            "sec-ch-ua": '"Google Chrome";v="141", "Not?A_Brand";v="8", "Chromium";v="141"',
            "sec-ch-ua-mobile": "?0",
            "sec-ch-ua-platform": '"macOS"',
            "sec-fetch-dest": "empty",
            "sec-fetch-mode": "cors",
            "sec-fetch-site": "same-site",
        }

    view = f"/schedule/week/{week[0]}?staff={staff}"
    q = f"start={week[0]}&end={week[1]}&staff={staff}"
    return [
        ("poll", 55, "GET", f"/api/v2/schedule/version?since={since}", h(view), None),
        ("bookings", 9, "GET", f"/api/v2/schedule/bookings?{q}", h(view), None),
        ("shifts", 9, "GET", f"/api/v2/schedule/shifts?{q}", h(view), None),
        ("encounter", 12, "GET", f"/api/v2/encounters/{enc}", h(f"/encounters/{enc}"), None),
        ("history", 12, "GET", f"/api/v2/clients/{client}/encounters?limit=20", h(f"/clients/{client}"), None),
        ("client", 3, "GET", f"/api/v2/clients/{other}", h(f"/clients/{other}"), None),
    ]


def main():
    zrk, url, data, tier, rate, duration, cpus, out = sys.argv[1:9]
    routes = {"a": tier_a, "b": tier_b, "c": tier_c}[tier](data)
    total = sum(r[1] for r in routes)
    procs = []
    for name, share, method, path, headers, body in routes:
        cmd = ["taskset", "-c", cpus, zrk, "--plain", "--format", "json", "-o", f"{out}.{name}.json",
               "-t", str(max(1, THREADS * share // total)), "-c", str(max(8, CONNS * share // total)),
               "-d", f"{duration}s", "-R", str(max(1, int(rate) * share // total)), "-m", method]
        for k, v in headers.items():
            cmd += ["-H", f"{k}: {v}"]
        if body is not None:
            cmd += ["-b", body]
        cmd.append(url + path)
        procs.append(subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=open(f"{out}.{name}.err", "w")))
    sys.exit(max(p.wait() for p in procs))


if __name__ == "__main__":
    main()
