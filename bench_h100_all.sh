#!/bin/bash
# Re-profile every RANS closure on every geometry on the current node (H100).
# Captures per-iteration cost: TOTAL, turb correct, p solve, U solve.
# 21 closures (9 fused classical + 12 NN variants) × 4 geometries.
#
# Usage:
#   source setup_spuma_env.sh
#   ./bench_h100_all.sh                  # full sweep
#   CASES="cylinder duct" ./bench_h100_all.sh   # subset
#
# Per-case iter counts can be overridden by env var (NITERS_<case>).

set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
WORKROOT="$DIR/bench_h100_runs"
CSV="$DIR/bench_h100_results.csv"
TIMEOUT=${TIMEOUT:-900}

# Per-case iters (smaller for big meshes)
NITERS_cylinder=${NITERS_cylinder:-20}
NITERS_duct=${NITERS_duct:-20}
NITERS_hills=${NITERS_hills:-10}
NITERS_sphere=${NITERS_sphere:-10}

CASES="${CASES:-cylinder duct hills sphere}"

mkdir -p "$WORKROOT"
if [ ! -s "$CSV" ]; then
    echo "case,model,exit,total_ms,turb_ms,p_ms,U_ms,niters,note" > "$CSV"
fi

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
    cat > system/fvSchemes << 'FSEOF'
FoamFile { version 2.0; format ascii; class dictionary; object fvSchemes; }
ddtSchemes      { default steadyState; }
gradSchemes     { default Gauss linear; }
divSchemes
{
    default             none;
    div(phi,U)          bounded Gauss linearUpwind grad(U);
    div(phi,k)          bounded Gauss upwind;
    div(phi,omega)      bounded Gauss upwind;
    div(phi,epsilon)    bounded Gauss upwind;
    div(phi,R)          bounded Gauss upwind;
    div(R)              Gauss linear;
    div((nuEff*dev2(T(grad(U))))) Gauss linear;
    div(nonlinearStress) Gauss linear;
}
laplacianSchemes { default Gauss linear corrected; }
interpolationSchemes { default linear; }
snGradSchemes    { default corrected; }
wallDist { method meshWave; }
FSEOF
    cat > system/fvSolution << 'FVEOF'
FoamFile { version 2.0; format ascii; class dictionary; object fvSolution; }
solvers
{
    p { solver GAMG; smoother twoStageGaussSeidel; tolerance 1e-06; relTol 0.1; }
    "(U|k|omega|epsilon|R)" { solver smoothSolver; smoother twoStageSymGaussSeidel; tolerance 1e-06; relTol 0.1; }
}
SIMPLE { nNonOrthogonalCorrectors 0; consistent yes; pRefCell 0; pRefValue 0; }
relaxationFactors { equations { U 0.7; k 0.7; omega 0.7; epsilon 0.7; R 0.7; } fields { p 0.3; } }
FVEOF
}

run_one() {
    local case_name=$1
    local template=$2
    local model_name=$3
    local turb_block=$4
    local nIters=$5

    local work="$WORKROOT/${case_name}__${model_name}"
    rm -rf "$work"
    cp -r "$template" "$work"
    # symlink nn_weights from cylinder template if missing
    if [ ! -d "$work/constant/nn_weights" ] && [ -d "$DIR/cylinder_nn_template/constant/nn_weights" ]; then
        ln -s "$DIR/cylinder_nn_template/constant/nn_weights" "$work/constant/nn_weights"
    fi
    cd "$work"
    rm -rf [1-9]* postProcessing log
    # Strip fvOptions for the bench (some cases reference cellZones that
    # require topoSet to be run first; we don't care about the source term
    # for per-iteration cost profiling).
    if [ -f system/fvOptions ]; then
        cat > system/fvOptions << 'OPTEOF'
FoamFile { version 2.0; format ascii; class dictionary; object fvOptions; }
OPTEOF
    fi

    cat > constant/turbulenceProperties << EOF
FoamFile { version 2.0; format ascii; class dictionary; object turbulenceProperties; }
$turb_block
EOF

    # fusedRSM uses Reynolds-stress + epsilon transport. Provide uniform
    # initial fields if missing (we only need plausible values for profiling).
    if [[ "$model_name" == "fusedRSM" ]]; then
        if [ ! -f 0/R ]; then
            # Generate R BCs by parsing constant/polyMesh/boundary so we
            # respect cyclic / wall / etc. patch types per case.
            local bc_block
            bc_block=$(awk '
                /^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*$/ && prev == "{" { name=$1 }
                /type[[:space:]]+/ {
                    if (name != "" && !printed[name]) {
                        gsub(";","",$2); type=$2;
                        if (type == "cyclic")        bc[name]="type cyclic;";
                        else if (type == "empty")    bc[name]="type empty;";
                        else if (type == "symmetry"||type=="symmetryPlane") bc[name]="type symmetry;";
                        else if (type == "wall")     bc[name]="type kqRWallFunction; value uniform (0 0 0 0 0 0);";
                        else                          bc[name]="type calculated; value uniform (0 0 0 0 0 0);";
                        order[++n]=name; printed[name]=1;
                    }
                }
                { prev=$1 }
                END {
                    for (i=1;i<=n;i++) printf "    %s { %s }\n", order[i], bc[order[i]];
                }
            ' constant/polyMesh/boundary)
            cat > 0/R << REOF
FoamFile { version 2.0; format ascii; class volSymmTensorField; object R; }
dimensions      [0 2 -2 0 0 0 0];
internalField   uniform (0.001 0 0 0.001 0 0.001);
boundaryField
{
$bc_block
}
REOF
        fi
        if [ ! -f 0/epsilon ]; then
            cat > 0/epsilon << 'EEOF'
FoamFile { version 2.0; format ascii; class volScalarField; object epsilon; }
dimensions      [0 2 -3 0 0 0 0];
internalField   uniform 0.01;
boundaryField
{
    ".*"  { type zeroGradient; }
}
EEOF
        fi
    fi

    write_dicts "$nIters"

    timeout "$TIMEOUT" simpleFoam -pool fixedSizeMemoryPool -poolSize 16 > log 2>&1
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

    printf "%-9s  %-22s  rc=%-3d total=%-10s turb=%-10s p=%-10s U=%-10s %s\n" \
        "$case_name" "$model_name" "$rc" "$TOT" "$TURB" "$P" "$U" "$NOTE"
    echo "$case_name,$model_name,$rc,$TOT,$TURB,$P,$U,$nIters,$NOTE" >> "$CSV"
    cd "$DIR"
}

# ---- 21 closures ----------------------------------------------------------
# 9 fused classical baselines
declare -a MODELS=(
    "fusedKOmegaSST|simulationType RAS; RAS { RASModel fusedKOmegaSST; turbulence on; }"
    "fusedKOmega|simulationType RAS; RAS { RASModel fusedKOmega; turbulence on; }"
    "fusedKOmegaMenter|simulationType RAS; RAS { RASModel fusedKOmegaMenter; turbulence on; }"
    "fusedMixingLength|simulationType RAS; RAS { RASModel fusedMixingLength; turbulence on; }"
    "fusedEARSMwj|simulationType RAS; RAS { RASModel fusedEARSMwj; turbulence on; }"
    "fusedEARSMhellsten|simulationType RAS; RAS { RASModel fusedEARSMhellsten; turbulence on; }"
    "fusedEARSMgs|simulationType RAS; RAS { RASModel fusedEARSMgs; turbulence on; }"
    "fusedRSM|simulationType RAS; RAS { RASModel fusedRSM; turbulence on; }"
    "fusedGEP|simulationType RAS; RAS { RASModel fusedGEP; turbulence on; }"
    # 12 NN variants
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
CASE_TEMPLATE[hills]="$DIR/hills_sst"
CASE_TEMPLATE[sphere]="$DIR/sphere_sst"

declare -A CASE_NITERS
CASE_NITERS[cylinder]=$NITERS_cylinder
CASE_NITERS[duct]=$NITERS_duct
CASE_NITERS[hills]=$NITERS_hills
CASE_NITERS[sphere]=$NITERS_sphere

echo "=== bench_h100_all — $(date) ==="
echo "host: $(hostname)"
echo "GPU:  $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)"
echo "cases: $CASES   timeout/run=${TIMEOUT}s"
echo "results: $CSV"
echo

for case_name in $CASES; do
    template=${CASE_TEMPLATE[$case_name]:-}
    nIters=${CASE_NITERS[$case_name]:-20}
    if [ -z "$template" ] || [ ! -d "$template" ]; then
        echo "SKIP $case_name: no template"
        continue
    fi
    if [ ! -d "$template/constant/polyMesh" ]; then
        echo "SKIP $case_name: no polyMesh in template"
        continue
    fi
    echo "--- case: $case_name (template: $template, iters=$nIters) ---"
    for entry in "${MODELS[@]}"; do
        IFS='|' read -r mname mblock <<< "$entry"
        run_one "$case_name" "$template" "$mname" "$mblock" "$nIters"
    done
    echo
done

echo "=== Done.  CSV: $CSV ==="
