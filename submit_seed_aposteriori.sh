#!/bin/bash
# Submit 24 individual SLURM jobs for the PI-TBNN-med seed sweep.
# Requires: ./deposit_seed_weights.sh {42,123,456} has been run.
#
# 3 seeds x 8 cases = 24 jobs. Each 2h walltime. Jobs are independent.

cd /storage/scratch1/6/sbryngelson3/spuma_cases

SEEDS=${SEEDS:-"42 123 456"}
CASES=${CASES:-"cylinder cylinder_re200 sphere sphere_re300 duct duct_re2500 hills hills_re10595"}

for S in $SEEDS; do
    WD="cylinder_nn_template/constant/nn_weights/pi_tbnn_paper_s${S}"
    if [ ! -f "$WD/layer0_W.txt" ]; then
        echo "SKIP seed=$S (weights not deposited). Run: ./deposit_seed_weights.sh $S" >&2
        continue
    fi
    for C in $CASES; do
        JID=$(sbatch --parsable --export=ALL,SEED=$S,CASE=$C sbatch_seed_aposteriori_one.sh)
        echo "seed=$S case=$C  jobID=$JID"
    done
done
