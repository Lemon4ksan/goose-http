perf stat of tier D's forms role alone on variants of findings-46356c2-hot at 40ce2a6,
each with one group of files taken back from main (batch.sh lists them), against n (main,
cb57a0b), 2026-10-14, daytime: Ryzen 7 5800X3D, WSL2 kernel 6.18.54.1, gcc 15.2.0, Goose
46356c2. The server (TIER=d JSON=serialize WORKERS=4 LOOP=uring) on CPUs 0-3; wrk 4.1.0
with bench/rest/tier-d.lua's forms role (7 threads, 224 connections) on CPUs 4-15, 5 s of
warm-up and then 12 s, perf stat -p PID for 10 s from its second second. forms.txt:
rounds 1 and 2 of every variant (batch.sh); confirm.txt: rounds 3 and 4 of n, f, and
find (confirm.sh).
