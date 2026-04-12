#!/bin/bash
#SBATCH --job-name=acc_sweep
#SBATCH --partition=gpu-h100
#SBATCH --account=gts-sbryngelson3
#SBATCH --qos=embers
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --gres=gpu:H100:1
#SBATCH --time=8:00:00
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err

# Accuracy sweep: 21 closures × 4 cases, run to residualControl convergence.
# Resume-safe: skips case+model pairs already in acc_h100_results.csv.

set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

source "$DIR/setup_spuma_env.sh"
echo "=== Accuracy sweep SLURM job ==="
echo "host: $(hostname)"
echo "GPU:  $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)"
echo "date: $(date)"
echo

# Run all 4 cases sequentially (each takes 1-2h).
CASES="cylinder duct duct_re2500 hills hills_re10595 sphere" \
    HARDCAP_cylinder=1500 \
    HARDCAP_duct=3000 \
    HARDCAP_duct_re2500=3000 \
    HARDCAP_hills=3000 \
    HARDCAP_hills_re10595=3000 \
    HARDCAP_sphere=1500 \
    TIMEOUT_cylinder=300 \
    TIMEOUT_sphere=900 \
    TIMEOUT_duct=5400 \
    TIMEOUT_duct_re2500=5400 \
    TIMEOUT_hills=5400 \
    TIMEOUT_hills_re10595=5400 \
    bash "$DIR/sweep_h100_accuracy.sh"

echo "=== Done: $(date) ==="
