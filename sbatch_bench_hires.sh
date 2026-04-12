#!/bin/bash
#SBATCH --job-name=bench_hires
#SBATCH --partition=gpu-h200
#SBATCH --account=gts-sbryngelson3
#SBATCH --qos=embers
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --gres=gpu:H200:1
#SBATCH --time=3:00:00
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err

# High-resolution bench: measures per-cell slope OUT of kernel-launch-overhead regime.
#
# Two new cases:
#   channel_hires : 2D plane channel  1600×400×1 = 640k cells  (vs cylinder 68k)
#   duct_hires    : 3D square duct    192×192×192 = 7.1M cells  (vs duct 884k)
#
# Results appended to bench_h100_results.csv under case names
# "channel_hires" and "duct_hires".

DIR="/storage/scratch1/6/sbryngelson3/spuma_cases"
cd "$DIR"
# Do NOT use set -u before sourcing SPUMA env (OpenFOAM bashrc references unset vars internally)
source "$DIR/setup_spuma_env.sh" || { echo "FATAL: env setup failed"; exit 1; }
set -u

echo "=== bench_hires — $(date) ==="
echo "host: $(hostname)"
echo "GPU:  $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)"

CSV="$DIR/bench_h100_results.csv"
WORKROOT="$DIR/bench_h100_runs"
TIMEOUT=600

if [ ! -s "$CSV" ]; then
    echo "case,model,exit,total_ms,turb_ms,p_ms,U_ms,niters,note" > "$CSV"
fi

# ── 1. Generate meshes ─────────────────────────────────────────────────────

CHAN_TMPL="$DIR/channel_hires_template"
DUCT_TMPL="$DIR/duct_hires_template"

echo ""
echo "--- Generating channel_hires mesh (blockMesh 1600×400×1) ---"
( cd "$CHAN_TMPL" && blockMesh > log.blockMesh 2>&1 ) && \
    echo "channel_hires blockMesh OK" || \
    { echo "channel_hires blockMesh FAILED"; cat "$CHAN_TMPL/log.blockMesh"; exit 1; }
python3 -c "
import re, sys
txt=open('$CHAN_TMPL/log.blockMesh').read()
m=re.search(r'nCells\s*:\s*(\d+)', txt)
print('  nCells:', m.group(1) if m else '?')
"

echo ""
echo "--- Generating duct_hires mesh (blockMesh 192×192×192) ---"
( cd "$DUCT_TMPL" && blockMesh > log.blockMesh 2>&1 ) && \
    echo "duct_hires blockMesh OK" || \
    { echo "duct_hires blockMesh FAILED"; cat "$DUCT_TMPL/log.blockMesh"; exit 1; }
python3 -c "
import re, sys
txt=open('$DUCT_TMPL/log.blockMesh').read()
m=re.search(r'nCells\s*:\s*(\d+)', txt)
print('  nCells:', m.group(1) if m else '?')
"

# ── 2. Bench helper (mirrors bench_h100_all.sh run_one) ───────────────────

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
    local case_name=$1 template=$2 model_name=$3 turb_block=$4 nIters=$5
    local work="$WORKROOT/${case_name}__${model_name}"
    rm -rf "$work"
    cp -r "$template" "$work"
    if [ ! -d "$work/constant/nn_weights" ] && [ -d "$DIR/cylinder_nn_template/constant/nn_weights" ]; then
        ln -s "$DIR/cylinder_nn_template/constant/nn_weights" "$work/constant/nn_weights"
    fi
    cd "$work"
    rm -rf [1-9]* postProcessing log
    [ -f system/fvOptions ] && cat > system/fvOptions << 'OPTEOF'
FoamFile { version 2.0; format ascii; class dictionary; object fvOptions; }
OPTEOF

    cat > constant/turbulenceProperties << EOF
FoamFile { version 2.0; format ascii; class dictionary; object turbulenceProperties; }
$turb_block
EOF

    # RSM needs R and epsilon fields with proper patch-aware BCs
    if [[ "$model_name" == "fusedRSM" ]]; then
        if [ ! -f 0/R ]; then
            # Build BC block by inspecting boundary file
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
                END { for (i=1;i<=n;i++) printf "    %s { %s }\n", order[i], bc[order[i]]; }
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
boundaryField   { ".*" { type zeroGradient; } }
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
    TOT=$(parse "TOTAL:"); TURB=$(parse "turb correct:")
    P=$(parse "p solve:");  U=$(parse "U solve:")
    grep -qiE "nan|FATAL" log && NOTE="nan_or_fatal"
    [ -z "${TOT:-}" ] && TOT=NA; [ -z "${TURB:-}" ] && TURB=NA
    [ -z "${P:-}"   ] && P=NA;   [ -z "${U:-}"    ] && U=NA

    printf "%-14s  %-22s  rc=%-3d total=%-10s turb=%-10s p=%-10s U=%-10s %s\n" \
        "$case_name" "$model_name" "$rc" "$TOT" "$TURB" "$P" "$U" "$NOTE"
    echo "$case_name,$model_name,$rc,$TOT,$TURB,$P,$U,$nIters,$NOTE" >> "$CSV"
    cd "$DIR"
}

# ── 3. Model list (same as bench_h100_all.sh) ─────────────────────────────
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

# ── 4. Run bench on both hires cases ──────────────────────────────────────

CYLI_TMPL="$DIR/cylinder_hires_template"

declare -A HIRES_TMPL=( ["channel_hires"]="$CHAN_TMPL" ["duct_hires"]="$DUCT_TMPL" ["cylinder_hires"]="$CYLI_TMPL" )
declare -A HIRES_NITERS=( ["channel_hires"]=20 ["duct_hires"]=10 ["cylinder_hires"]=20 )

for CASE_NAME in channel_hires duct_hires cylinder_hires; do
    TMPL="${HIRES_TMPL[$CASE_NAME]}"
    NITERS="${HIRES_NITERS[$CASE_NAME]}"
    echo ""
    echo "=== case: $CASE_NAME (template: $TMPL, iters=$NITERS) ==="
    for entry in "${MODELS[@]}"; do
        IFS='|' read -r mname mblock <<< "$entry"
        run_one "$CASE_NAME" "$TMPL" "$mname" "$mblock" "$NITERS"
    done
done

echo ""
echo "=== bench_hires Done: $(date) ==="
echo "Results: $CSV"
