#!/bin/bash
# Short benchmark of all proposed turbulence model configurations on every
# runnable case. Captures per-phase timing into a CSV. Each run is short
# (50 iters) — purpose is performance profiling, not statistical convergence.
#
# Usage:  source setup_spuma_env.sh && ./bench_all_cases.sh

set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
WORKROOT="$DIR/bench_runs"
CSV="$DIR/bench_results.csv"
NITERS=${NITERS:-20}
TIMEOUT=${TIMEOUT:-600}

mkdir -p "$WORKROOT"
echo "case,model,exit,total_ms,turb_ms,p_ms,U_ms,note" > "$CSV"

# Common simpleFoam files
write_dicts() {
    local nIters=$1
    cat > system/controlDict << CDEOF
FoamFile { version 2.0; format ascii; class dictionary; object controlDict; }
libs ("libnnTurbulenceModels.so");
application simpleFoam;
startFrom startTime; startTime 0; stopAt endTime; endTime $nIters; deltaT 1;
writeControl timeStep; writeInterval 99999; purgeWrite 0;
writeFormat ascii; writePrecision 8; writeCompression off;
timeFormat general; timePrecision 6; runTimeModifiable false;
CDEOF
    cat > system/fvSolution << 'FVEOF'
FoamFile { version 2.0; format ascii; class dictionary; object fvSolution; }
solvers
{
    p { solver GAMG; smoother twoStageGaussSeidel; tolerance 1e-06; relTol 0.1; }
    "(U|k|omega)" { solver smoothSolver; smoother twoStageSymGaussSeidel; tolerance 1e-06; relTol 0.1; }
}
SIMPLE { nNonOrthogonalCorrectors 0; consistent yes; pRefCell 0; pRefValue 0; }
relaxationFactors { equations { U 0.7; k 0.7; omega 0.7; } fields { p 0.3; } }
FVEOF
}

run_one() {
    local case_name=$1   # cylinder | duct
    local template=$2
    local model_name=$3
    local turb_block=$4

    local work="$WORKROOT/${case_name}__${model_name}"
    rm -rf "$work"
    cp -r "$template" "$work"
    cd "$work"
    rm -rf [1-9]* postProcessing log

    cat > constant/turbulenceProperties << EOF
FoamFile { version 2.0; format ascii; class dictionary; object turbulenceProperties; }
$turb_block
EOF

    write_dicts "$NITERS"

    timeout "$TIMEOUT" simpleFoam -pool fixedSizeMemoryPool -poolSize 8 > log 2>&1
    local rc=$?

    # Parse FINAL Profiling Summary block: lines look like "  TOTAL: 54.008 ms/iter"
    # Take the first numeric token on the matching line.
    parse() { awk -v key="$1" '
        /FINAL Profiling/ {flag=1; next}
        flag && index($0,key) {
            for (i=1; i<=NF; i++) {
                if ($i ~ /^[0-9.eE+-]+$/) { print $i; exit }
            }
        }' log; }
    local TOT TURB P U NOTE=""
    TOT=$(parse "TOTAL:")
    TURB=$(parse "turb correct:")
    P=$(parse "p solve:")
    U=$(parse "U solve:")
    if grep -qiE "nan|FATAL" log; then NOTE="nan_or_fatal"; fi
    [ -z "${TOT:-}" ] && TOT=NA
    [ -z "${TURB:-}" ] && TURB=NA
    [ -z "${P:-}" ] && P=NA
    [ -z "${U:-}" ] && U=NA

    printf "%-8s  %-18s  rc=%d  total=%-10s  turb=%-10s  p=%-10s  U=%-10s  %s\n" \
        "$case_name" "$model_name" "$rc" "$TOT" "$TURB" "$P" "$U" "$NOTE"
    echo "$case_name,$model_name,$rc,$TOT,$TURB,$P,$U,$NOTE" >> "$CSV"
    cd "$DIR"
}

# ---- Model definitions (13 total) -----------------------------------------
# kOmegaSST (baseline) and 12 NN variants
declare -a MODELS=(
    "kOmegaSST|simulationType RAS; RAS { RASModel kOmegaSST; turbulence on; }"
    "nnMLP-small|simulationType RAS; RAS { RASModel nnMLP; turbulence on; nnMLPCoeffs { weightsDir \"constant/nn_weights/mlp_paper\"; nutMax 1.0; } }"
    "nnMLP-med|simulationType RAS; RAS { RASModel nnMLP; turbulence on; nnMLPCoeffs { weightsDir \"constant/nn_weights/mlp_med_paper\"; nutMax 1.0; } }"
    "nnMLP-large|simulationType RAS; RAS { RASModel nnMLP; turbulence on; nnMLPCoeffs { weightsDir \"constant/nn_weights/mlp_large_paper\"; nutMax 1.0; } }"
    "nnTBNN-small|simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/tbnn_small_paper\"; nutMax 1.0; } }"
    "nnTBNN-med|simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/tbnn_paper\"; nutMax 1.0; } }"
    "nnTBNN-large|simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/tbnn_large_paper\"; nutMax 1.0; } }"
    "nnPITBNN-small|simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/pi_tbnn_small_paper\"; nutMax 1.0; } }"
    "nnPITBNN-med|simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/pi_tbnn_paper\"; nutMax 1.0; } }"
    "nnPITBNN-large|simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/pi_tbnn_large_paper\"; nutMax 1.0; } }"
    "nnTBRF-1t|simulationType RAS; RAS { RASModel nnTBRF; turbulence on; nnTBRFCoeffs { weightsDir \"constant/nn_weights/tbrf_1t_paper\"; nutMax 1.0; } }"
    "nnTBRF-5t|simulationType RAS; RAS { RASModel nnTBRF; turbulence on; nnTBRFCoeffs { weightsDir \"constant/nn_weights/tbrf_5t_paper\"; nutMax 1.0; } }"
    "nnTBRF-10t|simulationType RAS; RAS { RASModel nnTBRF; turbulence on; nnTBRFCoeffs { weightsDir \"constant/nn_weights/tbrf_10t_paper\"; nutMax 1.0; } }"
)

# ---- Cases ----------------------------------------------------------------
declare -A CASE_TEMPLATE
CASE_TEMPLATE[cylinder]="$DIR/cylinder_nn_template"
CASE_TEMPLATE[duct]="$DIR/duct_nn_template_gpu"

echo "=== bench_all_cases — $(date) ==="
echo "GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo 'no GPU')"
echo "iters/run=$NITERS  timeout=${TIMEOUT}s"
echo "results: $CSV"
echo

for case_name in cylinder duct; do
    template=${CASE_TEMPLATE[$case_name]}
    if [ ! -d "$template" ]; then
        echo "SKIP $case_name: no template at $template"
        continue
    fi
    echo "--- case: $case_name (template: $template) ---"
    for entry in "${MODELS[@]}"; do
        IFS='|' read -r mname mblock <<< "$entry"
        run_one "$case_name" "$template" "$mname" "$mblock"
    done
    echo
done

echo "=== Done.  CSV: $CSV ==="
