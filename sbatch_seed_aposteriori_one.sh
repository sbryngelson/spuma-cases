#!/bin/bash
#SBATCH -J seed_apost
#SBATCH -A gts-sbryngelson3 --qos embers
#SBATCH -N 1 --ntasks-per-node=1 --gres=gpu:H200:1
#SBATCH -t 2:00:00
#SBATCH -o /storage/scratch1/6/sbryngelson3/spuma_cases/acc_h100_runs/seed_apost_%j.log

# One (SEED, CASE) per job. Reuses sweep_h100_accuracy.sh as the driver.
# No `set -u`: OpenFOAM's etc/bashrc references unbound variables.
#
# Usage:
#   sbatch --export=ALL,SEED=42,CASE=cylinder sbatch_seed_aposteriori_one.sh
# See submit_seed_aposteriori.sh for the batch submitter.

source /storage/scratch1/6/sbryngelson3/spuma_cases/setup_spuma_env.sh

: "${SEED:?SEED required}"
: "${CASE:?CASE required}"

BASE=/storage/scratch1/6/sbryngelson3/spuma_cases
cd "$BASE"
mkdir -p acc_h100_runs

# Verify the seed weights exist in cylinder_nn_template.
WD="cylinder_nn_template/constant/nn_weights/pi_tbnn_paper_s${SEED}"
if [ ! -f "$WD/layer0_W.txt" ]; then
    echo "ERROR: weights dir $WD missing or incomplete."
    echo "Run ./deposit_seed_weights.sh $SEED first." >&2
    exit 1
fi

MODEL="PI-TBNN-med-s${SEED}"
echo "=== seed=${SEED} case=${CASE} model=${MODEL} ==="
date

# Drive one (case, model) run via the existing sweep script. CSV is per-seed
# so concurrent seed jobs don't clobber each other.
CSV="$BASE/acc_h100_runs/acc_seed${SEED}.csv" \
WORKROOT="$BASE/acc_h100_runs/seed${SEED}" \
MODEL="$MODEL" CASE="$CASE" \
    bash "$BASE/sweep_h100_accuracy.sh"

EXIT=$?
echo "=== done seed=${SEED} case=${CASE} exit=$EXIT ==="
