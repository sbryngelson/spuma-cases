#!/bin/bash
#SBATCH --job-name=acc_v2
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

# Rerun accuracy sweep v2 -- all 4 main cases on compute-dominated meshes:
#   - cylinder: cylinder_hires_template (552k cells, was 68k)
#   - sphere:   sphere_sst (966k cells), hardcap 3000 (was 1500)
#   - duct:     duct_2M_template (2.1M cells = 128^3, was 884k = 96^3)
#   - hills:    hills_sst (2.56M cells), nNonOrthogonalCorrectors 1
#   - all:      relTol 0.05 on GAMG + maxIter 50 (was relTol 0.01, no maxIter)
#   - all:      residualControl p/U 1e-5 for all cases including cylinder
#
# Results written to acc_h100_results_v2.csv (separate from v1 for comparison).
# After validation, promote v2 to the canonical CSV.

DIR="/storage/scratch1/6/sbryngelson3/spuma_cases"
cd "$DIR"
source "$DIR/setup_spuma_env.sh" || { echo "FATAL: env setup failed"; exit 1; }
set -u

echo "=== acc_v2 -- $(date) ==="
echo "host: $(hostname)"
echo "GPU:  $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)"

# Separate CSV/workroot so v1 is preserved for comparison.
export CSV="$DIR/acc_h100_results_v2.csv"
export WORKROOT="$DIR/acc_h100_runs_v2"

# Hardcaps: 3000 for all (duct was already 3000; cylinder/sphere increase from 1500).
export HARDCAP_cylinder=3000
export HARDCAP_sphere=3000
export HARDCAP_duct=3000
export HARDCAP_hills=3000

# Timeouts: scale with mesh size.
# cylinder_hires (552k):  ~65ms/iter x 3000 = 195s  -> 1800s safe
# sphere (966k):         ~160ms/iter x 3000 = 480s  -> 2400s safe
# duct_2M (2.1M):        ~280ms/iter x 3000 = 840s  -> 3600s safe
# hills (2.56M):         ~350ms/iter x 3000 = 1050s -> 5400s safe
export TIMEOUT_cylinder=1800
export TIMEOUT_sphere=2400
export TIMEOUT_duct=3600
export TIMEOUT_hills=5400

mkdir -p "$WORKROOT"
echo "case,model,exit,iters,walltime_s,p_res,U_res,Cd,Cl,U_cl,converged,note" > "$CSV"

# Run all four primary cases with v2 settings.
CASES="cylinder sphere duct hills" bash "$DIR/sweep_h100_accuracy.sh"

echo ""
echo "=== acc_v2 Done: $(date) ==="
echo "Results: $CSV"
echo ""
echo "Next steps:"
echo "  cd /storage/scratch1/6/sbryngelson3/cfd-nn"
echo "  python3 paper/data/backfill_residuals.py --csv $CSV"
echo "  python3 paper/data/plot_pareto.py"
