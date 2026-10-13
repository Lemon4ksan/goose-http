"""Summarizes a bench/rest.sh run as Markdown tables.

    python3 bench/rest/summary.py OUTDIR
    python3 bench/rest/summary.py --half OUTDIR TIER

Saturation (sat-*): wrk's requests per second as the median and the range of
the runs, wrk's median p50 and p99, the server's median CPU time per request,
and the highest peak RSS. Tier D (d-*): uploads and the forms role's requests
per second, the uploads' p50 and the forms' p99. Fixed rate (rate-*, mixed-*):
each route's zrk p50 and p99 as the median of the runs and their range, the
rate reached, and the server's CPU time per request. Errors are summed: wrk's
socket errors and non-2xx (tier D's forms role has its 422s), zrk's errors
and statuses other than 2xx.

--half prints half the lowest median rate of TIER in the saturation runs,
both JSON ways, to two significant figures: the fixed rate bench/rest.sh
offers.
"""

import glob
import json
import os
import re
import statistics
import sys
from collections import defaultdict

ORDER = ["goose-uring", "goose-epoll", "hyper", "tokio", "may-minihttp", "xitca-web", "odin-http", "tina"]
UNITS = {"us": 1e-3, "ms": 1.0, "s": 1e3}


def ms(text):
    m = re.match(r"([\d.]+)(us|ms|s)$", text)
    return float(m.group(1)) * UNITS[m.group(2)] if m else None


def wrk(path):
    """rps, p50 and p99 in ms, requests, errors."""
    r = {"rps": 0.0, "p50": None, "p99": None, "requests": 0, "errors": 0}
    if not os.path.exists(path):
        return r
    for line in open(path):
        f = line.split()
        if line.startswith("Requests/sec:"):
            r["rps"] = float(f[1])
        elif len(f) == 2 and f[0] in ("50%", "99%"):
            r["p" + f[0][:-1]] = ms(f[1])
        elif "requests in" in line:
            r["requests"] = int(f[0])
        elif line.strip().startswith("Socket errors"):
            r["errors"] += sum(int(n) for n in re.findall(r"\d+", line))
        elif line.strip().startswith("Non-2xx"):
            r["errors"] += int(f[-1])
    return r


def stat(path):
    """CPU seconds since the mark, and peak RSS in MB."""
    try:
        c0, c1, hz, rss = open(path).read().split()
        return (int(c1) - int(c0)) / int(hz), int(rss) / 1024
    except (OSError, ValueError):
        return 0.0, 0.0


def zrk(path):
    try:
        d = json.load(open(path))
    except (OSError, ValueError):
        return None
    codes = d.get("status_codes", {})
    bad = sum(v for k, v in codes.items() if k != "2xx") + sum(d.get("errors", {}).values())
    lat = d.get("latency_us", {})
    return {"rate": d.get("achieved_rate", 0.0), "target": d.get("target_rate", 0),
            "requests": d.get("requests", 0), "p50": lat.get("p50", 0) / 1000,
            "p99": lat.get("p99", 0) / 1000, "errors": bad}


def order(name):
    return (ORDER.index(name) if name in ORDER else len(ORDER), name)


def span(xs, fmt):
    xs = [x for x in xs if x is not None]
    if not xs:
        return ""
    lo, hi = min(xs), max(xs)
    return fmt(lo) if fmt(lo) == fmt(hi) else f"{fmt(lo)}-{fmt(hi)}"


def k(x):
    return f"{x / 1000:.1f}K" if x >= 1000 else f"{x:.0f}"


def msf(x):
    return f"{x:.2f}" if x < 10 else f"{x:.1f}" if x < 100 else f"{x:.0f}"


def saturation(out):
    cells = defaultdict(list)
    for p in glob.glob(f"{out}/sat-*.wrk"):
        m = re.match(r"sat-(.+)-([abc])-(serialize|template)-r(\d+)\.wrk$", os.path.basename(p))
        w = wrk(p)
        cpu, rss = stat(p[:-4] + ".stat")
        w["cpu_us"] = cpu / w["requests"] * 1e6 if w["requests"] else 0
        w["rss"] = rss
        cells[m.group(1), m.group(2), m.group(3)].append(w)
    return cells


def half(out, tier):
    cells = saturation(out)
    medians = [statistics.median(w["rps"] for w in runs) for (s, t, j), runs in cells.items() if t == tier]
    x = min(medians) / 2
    digits = len(str(int(x))) - 2
    return int(round(x, -digits)) if digits > 0 else int(x)


def main():
    if sys.argv[1] == "--half":
        print(half(sys.argv[2], sys.argv[3]))
        return
    out = sys.argv[1]

    cells = saturation(out)
    if cells:
        print("## Saturation\n")
        print("| Server | Tier | JSON | req/s, median | range | p50 ms | p99 ms | CPU µs/req | peak RSS MB | errors |")
        print("|---|---|---|---:|---:|---:|---:|---:|---:|---:|")
        for key in sorted(cells, key=lambda c: (c[1], c[2], order(c[0]))):
            runs = cells[key]
            print(f"| {key[0]} | {key[1].upper()} | {key[2]} "
                  f"| {k(statistics.median(w['rps'] for w in runs))} | {span([w['rps'] for w in runs], k)} "
                  f"| {msf(statistics.median(w['p50'] or 0 for w in runs))} "
                  f"| {msf(statistics.median(w['p99'] or 0 for w in runs))} "
                  f"| {statistics.median(w['cpu_us'] for w in runs):.1f} | {max(w['rss'] for w in runs):.0f} "
                  f"| {sum(w['errors'] for w in runs)} |")
        print()

    d = defaultdict(list)
    for p in glob.glob(f"{out}/d-*.uploads.wrk"):
        m = re.match(r"d-(.+)-(alone|both)-r(\d+)\.uploads\.wrk$", os.path.basename(p))
        base = p[:-len(".uploads.wrk")]
        cpu, rss = stat(base + ".stat")
        d[m.group(1), m.group(2)].append((wrk(p), wrk(base + ".forms.wrk"), rss))
    if d:
        print("## Tier D\n")
        print("| Server | Run | uploads/s | uploads p50 ms | forms role req/s | forms p99 ms | peak RSS MB | upload errors |")
        print("|---|---|---:|---:|---:|---:|---:|---:|")
        for key in sorted(d, key=lambda c: (c[1], order(c[0]))):
            runs = d[key]
            both = key[1] == "both"
            print(f"| {key[0]} | {'beside forms' if both else 'alone'} "
                  f"| {span([u['rps'] for u, f, r in runs], k)} | {span([u['p50'] for u, f, r in runs], msf)} "
                  f"| {span([f['rps'] for u, f, r in runs], k) if both else ''} "
                  f"| {span([f['p99'] for u, f, r in runs], msf) if both else ''} "
                  f"| {max(r for u, f, r in runs):.0f} | {sum(u['errors'] for u, f, r in runs)} |")
        print()

    for kind, title in (("rate", "Fixed rate"), ("mixed", "Mixed run: tier C's reads, alone and beside uploads")):
        cells = defaultdict(lambda: defaultdict(list))
        cpu = defaultdict(list)
        ups = defaultdict(list)
        for p in sorted(glob.glob(f"{out}/{kind}-*.stat")):
            base = p[:-5]
            m = re.match(rf"{kind}-(.+)-(?:([abc])-(serialize|template)|(alone|uploads))-r(\d+)$",
                         os.path.basename(base))
            key = (m.group(1), m.group(2) or "c", m.group(3) or m.group(4))
            total = 0
            for z in glob.glob(base + ".*.json"):
                route = z[len(base) + 1:-5]
                r = zrk(z)
                if r:
                    cells[key][route].append(r)
                    total += r["requests"]
            secs, _ = stat(p)
            if total:
                cpu[key].append(secs / total * 1e6)
            if os.path.exists(base + ".uploads.wrk"):
                ups[key].append(wrk(base + ".uploads.wrk")["rps"])
        if not cells:
            continue
        print(f"## {title}\n")
        print("| Server | Tier | Run | Route | rate reached | p50 ms | p99 ms | errors |")
        print("|---|---|---|---|---:|---:|---:|---:|")
        for key in sorted(cells, key=lambda c: (c[1], c[2], order(c[0]))):
            for route, runs in sorted(cells[key].items()):
                print(f"| {key[0]} | {key[1].upper()} | {key[2]} | {route} "
                      f"| {span([r['rate'] for r in runs], k)} of {k(runs[0]['target'])} "
                      f"| {span([r['p50'] for r in runs], msf)} | {span([r['p99'] for r in runs], msf)} "
                      f"| {sum(r['errors'] for r in runs)} |")
        print()
        print("| Server | Tier | Run | CPU µs/req | uploads/s |")
        print("|---|---|---|---:|---:|")
        for key in sorted(cells, key=lambda c: (c[1], c[2], order(c[0]))):
            print(f"| {key[0]} | {key[1].upper()} | {key[2]} | {span(cpu[key], lambda x: f'{x:.1f}')} "
                  f"| {span(ups[key], k)} |")
        print()


if __name__ == "__main__":
    main()
