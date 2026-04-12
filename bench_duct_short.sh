#!/bin/bash
# Short duct pass — 5 iters per model, large timeout. Only runs models that
# are not already in bench_results.csv for case=duct.

set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
WORKROOT="$DIR/bench_runs"
CSV="$DIR/bench_results.csv"
NITERS=5
TIMEOUT=900
TEMPLATE="$DIR/duct_nn_template_gpu"

mkdir -p "$WORKROOT"
[ -f "$CSV" ] || echo "case,model,exit,total_ms,turb_ms,p_ms,U_ms,note" > "$CSV"

already_done() {
    awk -F, -v m="$1" '$1=="duct" && $2==m {print "yes"; exit}' "$CSV"
}

write_dicts() {
    cat > system/controlDict << CDEOF
FoamFile { version 2.0; format ascii; class dictionary; object controlDict; }
libs ("libnnTurbulenceModels.so");
application simpleFoam;
startFrom startTime; startTime 0; stopAt endTime; endTime $NITERS; deltaT 1;
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
    local mname=$1 mblock=$2
    if [ -n "$(already_done "$mname")" ]; then
        echo "SKIP duct $mname (already in CSV)"
        return
    fi
    local work="$WORKROOT/duct__${mname}"
    rm -rf "$work"
    cp -r "$TEMPLATE" "$work"
    cd "$work"
    rm -rf [1-9]* postProcessing log
    cat > constant/turbulenceProperties << EOF
FoamFile { version 2.0; format ascii; class dictionary; object turbulenceProperties; }
$mblock
EOF
    write_dicts
    timeout "$TIMEOUT" simpleFoam -pool fixedSizeMemoryPool -poolSize 12 > log 2>&1
    local rc=$?
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
    printf "duct  %-18s  rc=%d  total=%-10s  turb=%-10s  p=%-10s  U=%-10s  %s\n" \
        "$mname" "$rc" "$TOT" "$TURB" "$P" "$U" "$NOTE"
    echo "duct,$mname,$rc,$TOT,$TURB,$P,$U,$NOTE" >> "$CSV"
    cd "$DIR"
}

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

echo "=== bench_duct_short — $(date) ==="
for entry in "${MODELS[@]}"; do
    IFS='|' read -r m mb <<< "$entry"
    run_one "$m" "$mb"
done
echo "=== Done ==="
