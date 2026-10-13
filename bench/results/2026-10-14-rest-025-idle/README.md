Idle memory of bench/rest's Goose server, 2026-10-14: Ryzen 7 5800X3D, WSL2 kernel
6.18.54.1, gcc 15.2.0, Goose 0bdbd18, each build made from git archive of its commit with
`goose build --cc gcc --standalone`. For each build, tier, JSON way, and worker count, the
server started with `REST_DATA=build/rest TIER=t JSON=j WORKERS=n LOOP=epoll`, on CPUs 0-3,
VmRSS and VmHWM read 3 s after it listened, with no request sent. One run each.
25m is main at dd68f22; 25a c9d9d9f (records loaded on a thread that exits); 25b a81b3f0
(strings in one pool, template records dropped); 25c 9408035 (each note's text held once).
