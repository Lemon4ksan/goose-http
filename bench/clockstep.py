"""Logs steps of the wall clock against the monotonic clock until killed.

    python3 bench/clockstep.py [threshold_us]

Every 10 ms it compares the two clocks, and prints a line for each change in
their difference of more than threshold_us (200): the monotonic time in
seconds and the step in microseconds, negative for a step back. bench/run.sh
runs it beside each load run, to show which runs a step fell in.
"""

import signal
import sys
import time


def offset():
    return time.time_ns() - time.monotonic_ns()


def main():
    threshold = int(sys.argv[1]) * 1000 if len(sys.argv) > 1 else 200_000
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    last = offset()
    while True:
        time.sleep(0.01)
        now = offset()
        if abs(now - last) > threshold:
            print(f"{time.monotonic():.3f} {(now - last) / 1000:+.0f}", flush=True)
        last = now


if __name__ == "__main__":
    main()
