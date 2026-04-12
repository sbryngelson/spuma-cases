#!/bin/bash
# Profile all models with nsys to verify GPU execution
# Usage: source SPUMA env first, then ./nsys_profile.sh

CASEDIR=$(dirname "$0")
PROFDIR=$CASEDIR/nsys_profiles
mkdir -p $PROFDIR

run_profile() {
    local NAME=$1
    local CASE=$2
    local TURB=$3
    local LIBS=${4:-""}

    echo "=== Profiling: $NAME ==="

    cp -r $CASEDIR/$CASE $CASEDIR/prof_tmp
    cd $CASEDIR/prof_tmp
    rm -rf [1-9]*

    echo "$TURB" > constant/turbulenceProperties

    cat > system/controlDict << CDEOF
FoamFile { version 2.0; format ascii; class dictionary; object controlDict; }
${LIBS}
application simpleFoam; startFrom startTime; startTime 0; stopAt endTime; endTime 5; deltaT 1;
writeControl timeStep; writeInterval 9999; purgeWrite 0;
writeFormat ascii; writePrecision 8; writeCompression off;
timeFormat general; timePrecision 6; runTimeModifiable false;
CDEOF

    cat > system/fvSolution << 'FVEOF'
FoamFile { version 2.0; format ascii; class dictionary; object fvSolution; }
solvers { p { solver GAMG; smoother twoStageGaussSeidel; tolerance 1e-06; relTol 0.1; } "(U|k|omega)" { solver smoothSolver; smoother twoStageSymGaussSeidel; tolerance 1e-06; relTol 0.1; } }
SIMPLE { nNonOrthogonalCorrectors 0; consistent yes; pRefCell 0; pRefValue 0; }
relaxationFactors { equations { U 0.7; k 0.7; omega 0.7; } fields { p 0.3; } }
FVEOF

    # Run with nsys
    nsys profile --stats=true --output=$PROFDIR/${NAME} \
        simpleFoam -pool fixedSizeMemoryPool -poolSize 4 2>&1 | \
        grep -E "CUDA API|CUDA Kernel|Time\(%\)|cudaLaunch|cudaMemcpy|cudaDeviceSynchronize" | head -30

    echo ""
    cd $CASEDIR
    rm -rf prof_tmp
}

echo "=== nsys GPU Profiling: 68K cells, 5 iters each ==="
echo ""

run_profile "SST" "cylinder_sst" \
    'FoamFile { version 2.0; format ascii; class dictionary; object turbulenceProperties; }
simulationType RAS; RAS { RASModel kOmegaSST; turbulence on; printCoeffs on; }'

run_profile "nnMLP" "cylinder_nn_template" \
    'FoamFile { version 2.0; format ascii; class dictionary; object turbulenceProperties; }
simulationType RAS; RAS { RASModel nnMLP; turbulence on; printCoeffs on; nnMLPCoeffs { weightsDir "constant/nn_weights/mlp_paper"; nutMax 1.0; } }' \
    'libs (libnnTurbulenceModels);'

run_profile "nnTBNN" "cylinder_nn_template" \
    'FoamFile { version 2.0; format ascii; class dictionary; object turbulenceProperties; }
simulationType RAS; RAS { RASModel nnTBNN; turbulence on; printCoeffs on; nnTBNNCoeffs { weightsDir "constant/nn_weights/tbnn_paper"; nutMax 1.0; } }' \
    'libs (libnnTurbulenceModels);'

run_profile "nnTBRF" "cylinder_nn_template" \
    'FoamFile { version 2.0; format ascii; class dictionary; object turbulenceProperties; }
simulationType RAS; RAS { RASModel nnTBRF; turbulence on; printCoeffs on; nnTBRFCoeffs { weightsDir "constant/nn_weights/tbrf_1t_paper"; nutMax 1.0; } }' \
    'libs (libnnTurbulenceModels);'

echo "=== Done ==="
echo "Full reports in $PROFDIR/"
