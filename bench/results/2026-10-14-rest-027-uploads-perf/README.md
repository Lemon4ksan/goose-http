perf stat of bench/rest's Goose server on tier D's roles alone, 2026-10-14, daytime: Ryzen 7
5800X3D, WSL2 kernel 6.18.54.1, gcc 15.2.0, Goose 46356c2. n is main at cb57a0b, f
findings-46356c2-hot at e047040, the builds of 2026-10-14-rest-027-025. The server
(REST_DATA=build/rest TIER=d JSON=serialize WORKERS=4 LOOP=uring) on CPUs 0-3; wrk 4.1.0
with bench/rest/tier-d.lua on CPUs 4-15 (wrk-monotonic.so), 5 s of warm-up and then 12 s,
with perf stat -p PID for 10 s from its second second. Two rounds, n then f in each.
perf.txt: the uploads role (1 thread, 32 connections), batch.sh. forms.txt: the forms role
(7 threads, 224 connections, as beside the uploads), forms.sh.
