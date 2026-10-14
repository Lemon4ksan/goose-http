Idle memory of bench/rest's Goose server split by source, 2026-10-14, by
bench/rest-memory.sh at c027978:
6.18.54.1-microsoft-standard-WSL2, gcc (Ubuntu 15.2.0-16ubuntu1) 15.2.0, Goose 46356c2.
Each tier and JSON way with 1 and 2 workers, epoll loop, CPUs 0-3, Rss from
/proc/PID/smaps 3 s after the server listened, no request sent, one run each.
records_kb and templates_kb are what one worker's globals hold, from the
loader's REST_LENS lines and the record sizes in the generated C.
