#!/bin/bash
#SBATCH --job-name=hills10595_sweep
#SBATCH --partition=gpu-h200
#SBATCH --account=gts-sbryngelson3
#SBATCH --qos=embers
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --gres=gpu:H200:1
#SBATCH --time=8:00:00
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err

# Hills Re=10595 accuracy sweep: 21 closures.
# Resume-safe: skips case+model pairs already in acc_h100_results.csv.

DIR="/storage/scratch1/6/sbryngelson3/spuma_cases"
cd "$DIR"

source "$DIR/setup_spuma_env.sh" || { echo "FATAL: setup_spuma_env.sh failed"; exit 1; }
set -e
echo "=== Hills Re=10595 accuracy sweep ==="
echo "host: $(hostname)"
echo "GPU:  $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)"
echo "date: $(date)"
echo

CASES="hills_re10595" \
    HARDCAP_hills_re10595=3000 \
    TIMEOUT_hills_re10595=5400 \
    bash "$DIR/sweep_h100_accuracy.sh"

echo "=== Done: $(date) ==="
