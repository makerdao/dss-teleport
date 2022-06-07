#!/usr/bin/env bash
set -e

export DAPP_BUILD_OPTIMIZE=1
export DAPP_BUILD_OPTIMIZE_RUNS=200

if [[ -z "$1" && -z "$2" ]]; then
    dapp --use solc:0.8.14 test --fuzz-runs 1 -vv
elif [[ -z "$2" ]]; then
    dapp --use solc:0.8.14 test --match "$1" --fuzz-runs 1 -vv
elif [[ -z "$1" ]]; then
    dapp --use solc:0.8.14 test --fuzz-runs "$2" -vv
else
    dapp --use solc:0.8.14 test --match "$1" --fuzz-runs "$2" -vv
fi
