#!/bin/bash

set -e
MAX_UNCOVERED=0 # Maximum number of uncovered lines allowed

echo "Running coverage..."
uncovered=$(dapp test -v --rpc --coverage | grep "\[31m" | wc -l)
echo "Uncovered lines: $uncovered"

if [[ $uncovered -gt $MAX_UNCOVERED ]]; then
    echo "Insufficient coverage (max $MAX_UNCOVERED uncovered lines allowed)"
    exit 1
fi

echo "Satisfying coverage!"

