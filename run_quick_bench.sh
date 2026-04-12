#!/bin/bash
source /storage/scratch1/6/sbryngelson3/spuma_cases/setup_spuma_env.sh 2>/dev/null

BASE=/storage/scratch1/6/sbryngelson3/spuma_cases
TEMPLATE=$BASE/cost100_duct_fusedKOmegaSST
NITERS=30

P_FIXED2='p { solver GAMG; tolerance 0; relTol 0; maxIter 2; smoother GaussSeidel; nPreSweeps 0; nPostSweeps 2; cacheAgglomeration true; nCellsInCoarsestLevel 10; agglomerator faceAreaPair; mergeLevels 1; }'

declare -a MODELS=(
    "fusedKOmega-fused1|simulationType RAS; RAS { RASModel fusedKOmega; turbulence on; fusedKOmegaCoeffs { transportSweeps 1; } }"
    "fusedKOmega-fused3|simulationType RAS; RAS { RASModel fusedKOmega; turbulence on; fusedKOmegaCoeffs { transportSweeps 3; } }"
    "fusedKOmega-legacy|simulationType RAS; RAS { RASModel fusedKOmega; turbulence on; fusedKOmegaCoeffs { transportSweeps 0; } }"
    "fusedKOmegaSST|simulationType RAS; RAS { RASModel fusedKOmegaSST; turbulence on; }"
    "fusedEARSMwj|simulationType RAS; RAS { RASModel fusedEARSMwj; turbulence on; }"
    "fusedMixingLength|simulationType RAS; RAS { RASModel fusedMixingLength; turbulence on; }"
    "nnTBNN-small|simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/tbnn_small_paper\"; nutMax 1.0; } }"
    "nnMLP-small|simulationType RAS; RAS { RASModel nnMLP; turbulence on; nnMLPCoeffs { weightsDir \"constant/nn_weights/mlp_paper\"; nutMax 1.0; } }"
    "nnTBRF-1t|simulationType RAS; RAS { RASModel nnTBRF; turbulence on; nnTBRFCoeffs { weightsDir \"constant/nn_weights/tbrf_1t_paper\"; nutMax 1.0; } }"
)

for entry in "${MODELS[@]}"; do
    IFS='|' read -r model_name turb_props <<< "$entry"
    dir="$BASE/bench_${model_name}"
    rm -rf "$dir"
    cp -r "$TEMPLATE" "$dir"
    rm -rf "$dir"/[1-9]* "$dir"/log.*

    cat > "$dir/constant/turbulenceProperties" << EOF2
FoamFile { version 2.0; format ascii; class dictionary; object turbulenceProperties; }
$turb_props
EOF2

    cat > "$dir/system/fvSolution" << EOF2
FoamFile { version 2.0; format ascii; class dictionary; object fvSolution; }
solvers
{
    $P_FIXED2
    U { solver smoothSolver; smoother symGaussSeidel; tolerance 1e-06; relTol 0.1; }
    "(k|omega|epsilon|R)" { solver smoothSolver; smoother twoStageGaussSeidel; nSweeps -1; tolerance 0; relTol 0; }
}
SIMPLE { nNonOrthogonalCorrectors 0; consistent yes; pRefCell 0; pRefValue 0; }
relaxationFactors { equations { U 0.7; k 0.7; omega 0.7; epsilon 0.7; } fields { p 0.3; } }
EOF2

    sed -i 's/endTime [0-9][0-9]*/endTime '"$NITERS"'/' "$dir/system/controlDict"
    sed -i 's/writeInterval [0-9][0-9]*/writeInterval '"$NITERS"'/' "$dir/system/controlDict"
    grep -q "^libs" "$dir/system/controlDict" || sed -i '/^}/a libs (nnTurbulenceModels);' "$dir/system/controlDict"

    cd "$dir"
    echo "--- $model_name ---"
    timeout 180 simpleFoam > log.simpleFoam 2>&1
    iters=$(grep -c "^Time = " log.simpleFoam 2>/dev/null || echo 0)
    if [ "$iters" -ge "$NITERS" ]; then
        # Print the full profiling summary
        grep "=== FINAL" -A20 log.simpleFoam
    else
        echo "FAIL ($iters/$NITERS)"
        grep -i "fatal\|nan" log.simpleFoam | head -1
    fi
    cd "$BASE"
    echo ""
done
