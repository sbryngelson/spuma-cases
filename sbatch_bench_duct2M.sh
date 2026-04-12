#!/bin/bash
#SBATCH --job-name=bench_duct2M
#SBATCH --partition=gpu-h200
#SBATCH --account=gts-sbryngelson3
#SBATCH --qos=embers
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --gres=gpu:H200:1
#SBATCH --time=2:00:00
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err

DIR="/storage/scratch1/6/sbryngelson3/spuma_cases"
cd "$DIR"
source "$DIR/setup_spuma_env.sh" || { echo "FATAL: env setup failed"; exit 1; }
set -u

echo "=== bench_duct2M -- $(date) ==="
echo "GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)"

CSV="$DIR/bench_h100_results.csv"
WORKROOT="$DIR/bench_h100_runs"
TIMEOUT=300
TMPL="$DIR/duct_2M_template"
NITERS=10

[ -s "$CSV" ] || echo "case,model,exit,total_ms,turb_ms,p_ms,U_ms,niters,note" > "$CSV"

write_dicts() {
    local nIters=$1
    cat > system/controlDict << CDEOF
FoamFile { version 2.0; format ascii; class dictionary; object controlDict; }
libs ("libnnTurbulenceModels.so" "libfvOptions.so");
application simpleFoam;
startFrom startTime; startTime 0; stopAt endTime; endTime $nIters; deltaT 1;
writeControl timeStep; writeInterval 99999; purgeWrite 0;
writeFormat ascii; writePrecision 8; writeCompression off;
timeFormat general; timePrecision 6; runTimeModifiable false;
CDEOF
    cat > system/fvSchemes << 'FSEOF'
FoamFile { version 2.0; format ascii; class dictionary; object fvSchemes; }
ddtSchemes { default steadyState; }
gradSchemes { default Gauss linear; }
divSchemes { default none; div(phi,U) bounded Gauss linearUpwind grad(U); div(phi,k) bounded Gauss upwind; div(phi,omega) bounded Gauss upwind; div(phi,epsilon) bounded Gauss upwind; div(phi,R) bounded Gauss upwind; div(R) Gauss linear; div((nuEff*dev2(T(grad(U))))) Gauss linear; div(nonlinearStress) Gauss linear; }
laplacianSchemes { default Gauss linear corrected; }
interpolationSchemes { default linear; }
snGradSchemes { default corrected; }
wallDist { method meshWave; }
FSEOF
    cat > system/fvSolution << 'FVEOF'
FoamFile { version 2.0; format ascii; class dictionary; object fvSolution; }
solvers { p { solver GAMG; smoother twoStageGaussSeidel; tolerance 1e-06; relTol 0.1; } "(U|k|omega|epsilon|R)" { solver smoothSolver; smoother twoStageSymGaussSeidel; tolerance 1e-06; relTol 0.1; } }
SIMPLE { nNonOrthogonalCorrectors 0; consistent yes; pRefCell 0; pRefValue 0; }
relaxationFactors { equations { U 0.7; k 0.7; omega 0.7; epsilon 0.7; R 0.7; } fields { p 0.3; } }
FVEOF
    cat > system/fvOptions << 'OPTEOF'
FoamFile { version 2.0; format ascii; class dictionary; object fvOptions; }
momentumSource { type meanVelocityForce; selectionMode all; fields (U); Ubar (1 0 0); }
OPTEOF
}

run_one() {
    local case_name=$1 template=$2 model_name=$3 turb_block=$4 nIters=$5
    local work="$WORKROOT/${case_name}__${model_name}"
    rm -rf "$work"
    cp -r "$template" "$work"
    [ ! -d "$work/constant/nn_weights" ] && [ -d "$DIR/cylinder_nn_template/constant/nn_weights" ] && \
        ln -s "$DIR/cylinder_nn_template/constant/nn_weights" "$work/constant/nn_weights"
    cd "$work"
    rm -rf [1-9]* postProcessing log
    cat > constant/turbulenceProperties << EOF
FoamFile { version 2.0; format ascii; class dictionary; object turbulenceProperties; }
$turb_block
EOF
    write_dicts "$nIters"
    timeout "$TIMEOUT" simpleFoam -pool fixedSizeMemoryPool -poolSize 32 > log 2>&1
    local rc=$?
    parse() { awk -v key="$1" '/FINAL Profiling/{flag=1;next} flag && index($0,key){for(i=1;i<=NF;i++) if($i~/^[0-9.eE+-]+$/){print $i;exit}}' log; }
    local TOT TURB P U NOTE=""
    TOT=$(parse "TOTAL:"); TURB=$(parse "turb correct:")
    P=$(parse "p solve:"); U=$(parse "U solve:")
    grep -qiE "nan|FATAL" log && NOTE="nan_or_fatal"
    TOT=${TOT:-NA}; TURB=${TURB:-NA}; P=${P:-NA}; U=${U:-NA}
    printf "%-14s  %-22s  rc=%-3d total=%-10s turb=%-10s p=%-10s U=%-10s %s\n" \
        "$case_name" "$model_name" "$rc" "$TOT" "$TURB" "$P" "$U" "$NOTE"
    echo "$case_name,$model_name,$rc,$TOT,$TURB,$P,$U,$nIters,$NOTE" >> "$CSV"
    cd "$DIR"
}

declare -a MODELS=(
    "fusedKOmegaSST|simulationType RAS; RAS { RASModel fusedKOmegaSST; turbulence on; }"
    "fusedKOmega|simulationType RAS; RAS { RASModel fusedKOmega; turbulence on; }"
    "fusedKOmegaMenter|simulationType RAS; RAS { RASModel fusedKOmegaMenter; turbulence on; }"
    "fusedMixingLength|simulationType RAS; RAS { RASModel fusedMixingLength; turbulence on; }"
    "fusedEARSMwj|simulationType RAS; RAS { RASModel fusedEARSMwj; turbulence on; }"
    "fusedEARSMhellsten|simulationType RAS; RAS { RASModel fusedEARSMhellsten; turbulence on; }"
    "fusedEARSMgs|simulationType RAS; RAS { RASModel fusedEARSMgs; turbulence on; }"
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

echo ""
echo "=== case: duct_2M (2.1M cells, $NITERS iters) ==="
for entry in "${MODELS[@]}"; do
    IFS='|' read -r mname mblock <<< "$entry"
    run_one "duct_2M" "$TMPL" "$mname" "$mblock" "$NITERS"
done

echo ""
echo "=== bench_duct2M Done: $(date) ==="
echo "Results: $CSV"
