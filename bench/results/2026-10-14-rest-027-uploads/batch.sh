#!/bin/bash
# As root in WSL: tier D again for main (n) and findings-46356c2-hot (f), whose
# uploads beside forms read 145-151/s against 159-164/s in 2026-10-14-rest-027-025.
# The servers are that batch's builds, f first this time.
#   n  main                        cb57a0b
#   f  findings-46356c2-hot        e047040, with main merged
set -eu
export PATH=$HOME/.cargo/bin:$PATH
export MACHINE=wsl2-5800x3d
cd /mnt/c/Users/kait/projects/goose/goose-http
OUT=bench/results/2026-10-14-rest-027-uploads \
    SERVERS="goose-uring-27f goose-uring-27n" STEPS=2 bench/rest.sh run 2>&1 | tail -30
