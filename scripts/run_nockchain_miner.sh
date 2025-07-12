#!/bin/bash
source .env
export RUST_LOG
export MINIMAL_LOG_FORMAT
export MINING_PUBKEY

get_cpu_count() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sysctl -n hw.logicalcpu
    else
        # Linux (Ubuntu, etc.)
        nproc
    fi
}

# Get total CPU cores
total_threads=$(get_cpu_count)

# Use CPU cores minus 4
num_threads=$((total_threads > 4 ? total_threads - 4 : total_threads))

echo "Starting nockchain miner with $num_threads mining threads:"

nockchain --mining-pubkey ${MINING_PUBKEY} --mine --num-threads $num_threads

