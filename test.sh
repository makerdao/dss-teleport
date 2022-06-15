#!/usr/bin/env bash
set -e

[[ "$ETH_RPC_URL" && "$(seth chain)" == "ethlive" ]] || { echo "Please set a mainnet ETH_RPC_URL"; exit 1; }

export DAPP_BUILD_OPTIMIZE=1
export DAPP_BUILD_OPTIMIZE_RUNS=200

if [[ -z "$1" && -z "$2" ]]; then
    dapp --use solc:0.8.14 test --rpc-url="$ETH_RPC_URL" --fuzz-runs 1 -vv
elif [[ -z "$2" ]]; then
    dapp --use solc:0.8.14 test --rpc-url="$ETH_RPC_URL" --match "$1" --fuzz-runs 1 -vv
elif [[ -z "$1" ]]; then
    dapp --use solc:0.8.14 test --rpc-url="$ETH_RPC_URL" --fuzz-runs "$2" -vv
else
    dapp --use solc:0.8.14 test --rpc-url="$ETH_RPC_URL" --match "$1" --fuzz-runs "$2" -vv
fi
