#!/bin/bash
#SBATCH --job-name=hills_1h
#SBATCH --partition=gpu-h200
#SBATCH --account=gts-sbryngelson3
#SBATCH --qos=embers
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --gres=gpu:H200:1
#SBATCH --time=1:00:00
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err

# One-hour hills worker. Runs a specified model group on one hills Re case.
# Resume-safe: skips (case,model) pairs already in acc_h100_results.csv.
#
# Pass via --export=ALL,CASE=<case>,MODELS="m1 m2 ..."

DIR="/storage/scratch1/6/sbryngelson3/spuma_cases"
cd "$DIR"
source "$DIR/setup_spuma_env.sh" || { echo "FATAL: env setup failed"; exit 1; }

echo "=== hills 1h worker ==="
echo "host: $(hostname)"
echo "GPU:  $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)"
echo "CASE: $CASE"
echo "MODELS: $MODELS"
echo "date: $(date)"
echo

# Map case to appropriate HARDCAP/TIMEOUT env vars
HCAP=3000
TIMO=1500   # 25 min per model ceiling to fit 2-3 models in 1 hour

for m in $MODELS; do
    echo "--- $CASE $m ---"
    MODEL=$m CASE=$CASE \
        HARDCAP_hills=$HCAP HARDCAP_hills_re10595=$HCAP \
        HARDCAP_hills_re2800=$HCAP HARDCAP_hills_re5600=$HCAP \
        TIMEOUT_hills=$TIMO TIMEOUT_hills_re10595=$TIMO \
        TIMEOUT_hills_re2800=$TIMO TIMEOUT_hills_re5600=$TIMO \
        bash "$DIR/sweep_h100_accuracy.sh"
done

echo "=== Done: $(date) ==="
