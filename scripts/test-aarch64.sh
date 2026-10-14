#!/bin/sh
# Cross-builds every example for aarch64 Linux and runs scripts/test-examples.sh
# on the builds in an emulated arm64 container (scripts/test-arm.sh).
exec "$(dirname "$0")/test-arm.sh" aarch64
