#!/bin/bash
# Run a SPUMA case with GPU acceleration
# Usage: ./run_spuma.sh <case_dir> [pool_size_GB]
#
# Expects SPUMA environment to be sourced (etc/bashrc)

CASE_DIR=${1:?Usage: ./run_spuma.sh <case_dir> [pool_size_GB]}
POOL_SIZE=${2:-4}

cd "$CASE_DIR" || exit 1

echo "=== Running SPUMA simpleFoam ==="
echo "Case: $CASE_DIR"
echo "Pool size: ${POOL_SIZE} GB"
echo "GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo 'CPU mode')"

# Run simpleFoam with SPUMA GPU memory pool
simpleFoam -pool fixedSizeMemoryPool -poolSize "$POOL_SIZE" \
    2>&1 | tee log.simpleFoam

echo "=== Done ==="
