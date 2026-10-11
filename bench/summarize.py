"""Summarizes bench/run.sh's runs.tsv as a Markdown table, one row per cell.

    python3 bench/summarize.py bench/results/<date>/runs.tsv [BASE]

For each server, worker count, test, and connection count, across its runs:
wrk's requests per second as the median and the spread (lowest to highest),
the median relative to BASE's (default goose) in the same cell, h2load's median p50 and p99
latency and its own median rate, the highest peak RSS, the median CPU time of
the server and of wrk during the wrk run, the errors and clock steps summed
over the runs, and the earlier runs a cell's rows were copied from
(bench/run.sh's REUSE).
"""

import csv
import statistics
import sys
from collections import defaultdict

ORDER = ["goose", "may-minihttp", "hyper", "odin-http"]


def num(v):
    return float(v) if v not in ("", None) else 0.0


def main():
    with open(sys.argv[1], newline="") as f:
        rows = list(csv.DictReader(f, delimiter="\t"))
    cells = defaultdict(list)
    for r in rows:
        cells[(r["test"], int(r["conns"]), int(r["workers"]), r["server"])].append(r)

    def med(rs, k):
        return statistics.median(num(r[k]) for r in rs)

    # Runs with LATENCY=0 have no h2load phase.
    def lat(rs, k):
        return f"{med(rs, k) / 1000:.2f} ms" if any(r[k] for r in rs) else "–"

    def reused(rs):
        return ", ".join(sorted({r.get("from") or "" for r in rs} - {""}))

    base = sys.argv[2] if len(sys.argv) > 2 else "goose"
    print(f"| Test | Conns | Workers | Server | Req/s (wrk) | Spread | vs {base} | "
          "p50 (h2load) | p99 (h2load) | Req/s (h2load) | Peak RSS | Server CPU | wrk CPU | "
          "Errors | Steps | Runs | From |")
    print("|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|")
    keys = sorted(cells, key=lambda k: (k[0] != "plaintext", k[1], k[2],
                                        ORDER.index(k[3]) if k[3] in ORDER else 99))
    for test, conns, workers, server in keys:
        rs = cells[(test, conns, workers, server)]
        rps = [num(r["rps"]) for r in rs]
        m = statistics.median(rps)
        b = cells.get((test, conns, workers, base))
        rel = m / statistics.median(num(r["rps"]) for r in b) if b else 0
        errors = sum(int(num(r["errors"]) + num(r["non2xx"]) + num(r["h2load_failed"]) +
                         num(r["h2load_non2xx"])) for r in rs)
        steps = sum(int(num(r["steps"])) for r in rs)
        print(f"| {test} | {conns:,} | {workers} | {server} | {m / 1e6:.3f} M | "
              f"{min(rps) / 1e6:.3f}–{max(rps) / 1e6:.3f} M | {rel:.2f} | "
              f"{lat(rs, 'p50_us')} | {lat(rs, 'p99_us')} | "
              f"{med(rs, 'h2load_rps') / 1e6:.3f} M | "
              f"{max(num(r['peak_rss_kb']) for r in rs) / 1024:.1f} MB | "
              f"{med(rs, 'server_cpu_s'):.1f} s | {med(rs, 'wrk_cpu_s'):.1f} s | "
              f"{errors} | {steps} | {len(rs)} | {reused(rs)} |")


if __name__ == "__main__":
    main()
