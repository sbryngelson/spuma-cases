#!/bin/bash
#SBATCH --job-name=case_1h
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

# Generic 1-hour worker for any case + model list.
# Pass via --export=ALL,CASE=<case>,MODELS="m1 m2 ..." [,TIMO=<sec>]
# Resume-safe: sweep_h100_accuracy.sh skips (case,model) pairs already in CSV.

DIR="/storage/scratch1/6/sbryngelson3/spuma_cases"
cd "$DIR"
source "$DIR/setup_spuma_env.sh" || { echo "FATAL: env setup failed"; exit 1; }

echo "=== generic 1h worker ==="
echo "host: $(hostname)"
echo "GPU:  $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)"
echo "CASE: $CASE"
echo "MODELS: $MODELS"
echo "date: $(date)"
echo

HCAP=${HCAP:-3000}
TIMO=${TIMO:-600}   # 10 min default per model; cylinder/sphere/duct much faster than hills

for m in $MODELS; do
    echo "--- $CASE $m ---"
    MODEL=$m CASE=$CASE \
        HARDCAP_cylinder=$HCAP HARDCAP_cylinder_re40=$HCAP \
        HARDCAP_cylinder_re200=$HCAP HARDCAP_cylinder_re300=$HCAP HARDCAP_cylinder_re500=$HCAP \
        HARDCAP_sphere=$HCAP HARDCAP_sphere_re100=$HCAP HARDCAP_sphere_re300=$HCAP HARDCAP_sphere_re500=$HCAP \
        HARDCAP_duct=$HCAP HARDCAP_duct_re2500=$HCAP HARDCAP_duct_re4400=$HCAP HARDCAP_duct_re6400=$HCAP \
        HARDCAP_hills=$HCAP HARDCAP_hills_re10595=$HCAP HARDCAP_hills_re2800=$HCAP HARDCAP_hills_re5600=$HCAP \
        TIMEOUT_cylinder=$TIMO TIMEOUT_cylinder_re40=$TIMO \
        TIMEOUT_cylinder_re200=$TIMO TIMEOUT_cylinder_re300=$TIMO TIMEOUT_cylinder_re500=$TIMO \
        TIMEOUT_sphere=$TIMO TIMEOUT_sphere_re100=$TIMO TIMEOUT_sphere_re300=$TIMO TIMEOUT_sphere_re500=$TIMO \
        TIMEOUT_duct=$TIMO TIMEOUT_duct_re2500=$TIMO TIMEOUT_duct_re4400=$TIMO TIMEOUT_duct_re6400=$TIMO \
        TIMEOUT_hills=$TIMO TIMEOUT_hills_re10595=$TIMO TIMEOUT_hills_re2800=$TIMO TIMEOUT_hills_re5600=$TIMO \
        bash "$DIR/sweep_h100_accuracy.sh"
done

echo "=== Done: $(date) ==="
