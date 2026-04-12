#!/bin/bash
# Generate nsys profiles for one representative configuration per case +
# turbulence model family (SST baseline + one MLP + one TBNN + one TBRF).
# Short run (10 iters) — purpose: see GPU kernel mix, not measure throughput.
#
# Usage: source setup_spuma_env.sh && ./profile_representative.sh

set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$DIR/nsys_profiles"
mkdir -p "$OUT"

NITERS=10

declare -a CONFIGS=(
    "cylinder|cylinder_nn_template|kOmegaSST|simulationType RAS; RAS { RASModel kOmegaSST; turbulence on; }"
    "cylinder|cylinder_nn_template|nnMLP-med|simulationType RAS; RAS { RASModel nnMLP; turbulence on; nnMLPCoeffs { weightsDir \"constant/nn_weights/mlp_med_paper\"; nutMax 1.0; } }"
    "cylinder|cylinder_nn_template|nnTBNN-med|simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/tbnn_paper\"; nutMax 1.0; } }"
    "cylinder|cylinder_nn_template|nnTBRF-5t|simulationType RAS; RAS { RASModel nnTBRF; turbulence on; nnTBRFCoeffs { weightsDir \"constant/nn_weights/tbrf_5t_paper\"; nutMax 1.0; } }"
    "duct|duct_nn_template_gpu|kOmegaSST|simulationType RAS; RAS { RASModel kOmegaSST; turbulence on; }"
    "duct|duct_nn_template_gpu|nnMLP-med|simulationType RAS; RAS { RASModel nnMLP; turbulence on; nnMLPCoeffs { weightsDir \"constant/nn_weights/mlp_med_paper\"; nutMax 1.0; } }"
    "duct|duct_nn_template_gpu|nnTBNN-med|simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/tbnn_paper\"; nutMax 1.0; } }"
    "duct|duct_nn_template_gpu|nnTBRF-5t|simulationType RAS; RAS { RASModel nnTBRF; turbulence on; nnTBRFCoeffs { weightsDir \"constant/nn_weights/tbrf_5t_paper\"; nutMax 1.0; } }"
)

for entry in "${CONFIGS[@]}"; do
    IFS='|' read -r case_name template name turb <<< "$entry"
    work="$DIR/profile_${case_name}__${name}"
    rm -rf "$work"
    cp -r "$DIR/$template" "$work"
    cd "$work"
    rm -rf [1-9]* postProcessing log

    cat > constant/turbulenceProperties << EOF
FoamFile { version 2.0; format ascii; class dictionary; object turbulenceProperties; }
$turb
EOF
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

    REP="$OUT/${case_name}__${name}"
    rm -f "${REP}.nsys-rep" "${REP}.sqlite"
    echo "--- profiling: ${case_name} ${name} ---"
    nsys profile -o "$REP" -t cuda,nvtx --force-overwrite=true \
        --stats=false \
        simpleFoam -pool fixedSizeMemoryPool -poolSize 8 > log 2>&1
    rc=$?
    echo "  rc=$rc  rep=$(ls -1 ${REP}.nsys-rep 2>/dev/null || echo MISSING)"
    cd "$DIR"
done

echo "=== Profiles in $OUT ==="
ls -lh "$OUT"
