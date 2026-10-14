#!/bin/sh
# Cross-builds every example for 32-bit ARM Linux (armhf) and runs
# scripts/test-examples.sh on the builds in an emulated arm/v7 container
# (scripts/test-arm.sh).
exec "$(dirname "$0")/test-arm.sh" armhf
