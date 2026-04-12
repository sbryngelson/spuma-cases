#!/bin/bash
source /storage/scratch1/6/sbryngelson3/spuma_cases/setup_spuma_env.sh 2>/dev/null

BASE=/storage/scratch1/6/sbryngelson3/spuma_cases
TEMPLATE=$BASE/cost100_duct_fusedKOmegaSST
NITERS=50

P_FIXED2='p { solver GAMG; tolerance 0; relTol 0; maxIter 2; smoother GaussSeidel; nPreSweeps 0; nPostSweeps 2; cacheAgglomeration true; nCellsInCoarsestLevel 10; agglomerator faceAreaPair; mergeLevels 1; }'

# Test matrix: legacy vs fused U solve, with SST and a NN model
declare -a MODELS=(
    "SST-legacyU|fusedKOmegaSST|0"
    "SST-fusedU2|fusedKOmegaSST|2"
    "SST-fusedU4|fusedKOmegaSST|4"
    "kOmega-fused1-legacyU|fusedKOmega|0"
    "kOmega-fused1-fusedU2|fusedKOmega|2"
    "TBNN-small-legacyU|nnTBNN|0"
    "TBNN-small-fusedU2|nnTBNN|2"
    "MLP-small-legacyU|nnMLP|0"
    "MLP-small-fusedU2|nnMLP|2"
)

for entry in "${MODELS[@]}"; do
    IFS='|' read -r name model fusedUSweeps <<< "$entry"
    dir="$BASE/bench_fusedU_${name}"
    rm -rf "$dir"
    cp -r "$TEMPLATE" "$dir"
    rm -rf "$dir"/[1-9]* "$dir"/log.*

    # Turbulence properties
    case "$model" in
        fusedKOmegaSST)
            echo 'FoamFile { version 2.0; format ascii; class dictionary; object turbulenceProperties; }
simulationType RAS; RAS { RASModel fusedKOmegaSST; turbulence on; }' > "$dir/constant/turbulenceProperties"
            ;;
        fusedKOmega)
            echo 'FoamFile { version 2.0; format ascii; class dictionary; object turbulenceProperties; }
simulationType RAS; RAS { RASModel fusedKOmega; turbulence on; fusedKOmegaCoeffs { transportSweeps 1; } }' > "$dir/constant/turbulenceProperties"
            ;;
        nnTBNN)
            echo 'FoamFile { version 2.0; format ascii; class dictionary; object turbulenceProperties; }
simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir "constant/nn_weights/tbnn_small_paper"; nutMax 1.0; } }' > "$dir/constant/turbulenceProperties"
            ;;
        nnMLP)
            echo 'FoamFile { version 2.0; format ascii; class dictionary; object turbulenceProperties; }
simulationType RAS; RAS { RASModel nnMLP; turbulence on; nnMLPCoeffs { weightsDir "constant/nn_weights/mlp_paper"; nutMax 1.0; } }' > "$dir/constant/turbulenceProperties"
            ;;
    esac

    # fvSolution — legacy vs fused U
    if [ "$fusedUSweeps" -eq 0 ]; then
        USOLVER='U { solver smoothSolver; smoother symGaussSeidel; tolerance 1e-06; relTol 0.1; }'
        SIMPLE_EXTRA=""
    else
        USOLVER='U { solver smoothSolver; smoother symGaussSeidel; tolerance 1e-06; relTol 0.1; }'
        SIMPLE_EXTRA="fusedMomentumSweeps ${fusedUSweeps};"
    fi

    cat > "$dir/system/fvSolution" << EOF2
FoamFile { version 2.0; format ascii; class dictionary; object fvSolution; }
solvers
{
    $P_FIXED2
    $USOLVER
    "(k|omega|epsilon|R)" { solver smoothSolver; smoother twoStageGaussSeidel; nSweeps -1; tolerance 0; relTol 0; }
}
SIMPLE { nNonOrthogonalCorrectors 0; consistent yes; pRefCell 0; pRefValue 0; $SIMPLE_EXTRA }
relaxationFactors { equations { U 0.7; k 0.7; omega 0.7; epsilon 0.7; } fields { p 0.3; } }
EOF2

    sed -i 's/endTime [0-9][0-9]*/endTime '"$NITERS"'/' "$dir/system/controlDict"
    sed -i 's/writeInterval [0-9][0-9]*/writeInterval '"$NITERS"'/' "$dir/system/controlDict"
    grep -q "^libs" "$dir/system/controlDict" || sed -i '/^}/a libs (nnTurbulenceModels);' "$dir/system/controlDict"

    cd "$dir"
    echo "=== $name ==="
    timeout 180 simpleFoam > log.simpleFoam 2>&1
    iters=$(grep -c "^Time = " log.simpleFoam 2>/dev/null || echo 0)
    if [ "$iters" -ge "$NITERS" ]; then
        grep "=== FINAL" -A20 log.simpleFoam
    else
        echo "FAIL ($iters/$NITERS)"
        grep -i "fatal\|error\|nan" log.simpleFoam | head -3
    fi
    echo ""
done
