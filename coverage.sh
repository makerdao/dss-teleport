#!/bin/bash

set -e
MAX_UNCOVERED=0 # Maximum number of uncovered lines allowed

echo "Running coverage..."
uncovered=$(DAPP_BUILD_OPTIMIZE=1 DAPP_BUILD_OPTIMIZE_RUNS=200 dapp --use solc:0.8.15 test -v --rpc --coverage --cov-match "src\/Teleport" | grep "\[31m" | wc -l)
echo "Uncovered lines: $uncovered"

if [[ $uncovered -gt $MAX_UNCOVERED ]]; then
    echo "Insufficient coverage (max $MAX_UNCOVERED uncovered lines allowed)"
    exit 1
fi

echo "Satisfying coverage!"

