Idle memory of bench/rest's Goose server on main at 1818526 (tasks 025 and 027 merged),
2026-10-14: Ryzen 7 5800X3D, WSL2 kernel 6.18.54.1, gcc 15.2.0, Goose 46356c2, built from
git archive with `goose build --cc gcc --standalone`. Each tier, JSON way, and worker count
started with `REST_DATA=build/rest TIER=t JSON=j WORKERS=n LOOP=epoll` on CPUs 0-3, VmRSS
and VmHWM read 3 s after it listened, no request sent, one run each (batch.sh).
