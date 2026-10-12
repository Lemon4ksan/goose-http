"""Prints README.md's plaintext and JSON table from bench/run.sh's runs.tsv
files: a row per server, a column per test and connection count, with WORKERS
workers, each cell wrk's median requests per second over the runs, and each
column's best in bold; and the range of the server's peak RSS over those cells,
the lowest highest in bold.

    python3 bench/table.py [--workers N] RUNS.tsv... [SERVER=NAME ...]

A cell missing from the first file is taken from the next that has it.
SERVER=NAME renames a row; rows keep the order of their first appearance.
"""

import csv
import statistics
import sys

TESTS = [("plaintext", "256"), ("plaintext", "1024"), ("plaintext", "4096"), ("json", "256"), ("json", "1024")]


def main():
    args = sys.argv[1:]
    workers = "4"
    if args[:1] == ["--workers"]:
        workers, args = args[1], args[2:]
    names = dict(a.split("=", 1) for a in args if "=" in a)
    files = [a for a in args if "=" not in a]
    cells, rss, order = {}, {}, []
    for path in files:
        seen = {}
        with open(path, newline="") as f:
            for r in csv.DictReader(f, delimiter="\t"):
                if r["workers"] != workers:
                    continue
                seen.setdefault((r["server"], r["test"], r["conns"]), []).append(r)
        for key, runs in seen.items():
            if key not in cells:
                cells[key] = statistics.median(float(r["rps"]) for r in runs)
                rss.setdefault(key[0], []).extend(int(r["peak_rss_kb"]) / 1024 for r in runs)
            if key[0] not in order:
                order.append(key[0])
    best = {t: max((v for (s, *k), v in cells.items() if tuple(k) == t), default=0) for t in TESTS}
    least = min(max(v) for v in rss.values())
    head = [f"{t} {int(c):,}" for t, c in TESTS]
    print("| Server | " + " | ".join(head) + " | peak RSS |")
    print("|---|" + "---:|" * (len(TESTS) + 1))
    for s in order:
        row = []
        for t in TESTS:
            v = cells.get((s, *t))
            if v is None:
                row.append("")
                continue
            text = f"{v / 1e6:.2f} M" if t[0] == "plaintext" else f"{v / 1e3:.0f} K"
            row.append(f"**{text}**" if v == best[t] else text)
        lo, hi = min(rss[s]), max(rss[s])
        text = f"{lo:,.0f}-{hi:,.0f} MB" if lo >= 10 else f"{lo:.1f}-{hi:.0f} MB"
        row.append(f"**{text}**" if hi == least else text)
        print(f"| {names.get(s, s)} | " + " | ".join(row) + " |")


if __name__ == "__main__":
    main()
