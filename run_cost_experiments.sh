#!/bin/bash
source /storage/scratch1/6/sbryngelson3/spuma_cases/setup_spuma_env.sh 2>/dev/null

BASE=/storage/scratch1/6/sbryngelson3/spuma_cases
TEMPLATE=$BASE/cost100_duct_fusedKOmegaSST
NITERS=50

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

run_one() {
    local model_name=$1
    local turb_props=$2
    local exp_name=$3
    local p_solver=$4

    local dir="$BASE/cost_${exp_name}_${model_name}"

    rm -rf "$dir"
    cp -r "$TEMPLATE" "$dir"
    rm -rf "$dir"/[1-9]* "$dir"/log.*

    cat > "$dir/constant/turbulenceProperties" << EOF2
FoamFile { version 2.0; format ascii; class dictionary; object turbulenceProperties; }
$turb_props
EOF2

    if [ "$model_name" = "fusedRSM" ]; then
        cp "$dir/0/k" "$dir/0/epsilon"
        sed -i 's/dimensions.*/dimensions [0 2 -3 0 0 0 0];/' "$dir/0/epsilon"
        cp "$dir/0/k" "$dir/0/R"
        sed -i 's/dimensions.*/dimensions [0 2 -2 0 0 0 0];/' "$dir/0/R"
        sed -i 's/class.*scalarField/class symmTensorField/' "$dir/0/R"
        sed -i 's/uniform 0;/uniform (0 0 0 0 0 0);/g' "$dir/0/R"
        sed -i 's/uniform [0-9.e+-]*/uniform (0 0 0 0 0 0)/g' "$dir/0/R"
    fi

    cat > "$dir/system/fvSolution" << EOF2
FoamFile { version 2.0; format ascii; class dictionary; object fvSolution; }
solvers
{
    $p_solver
    U { solver smoothSolver; smoother symGaussSeidel; tolerance 1e-06; relTol 0.1; }
    "(k|omega|epsilon|R)" { solver smoothSolver; smoother twoStageGaussSeidel; nSweeps -1; tolerance 0; relTol 0; }
}
SIMPLE { nNonOrthogonalCorrectors 0; consistent yes; pRefCell 0; pRefValue 0; }
relaxationFactors { equations { U 0.7; k 0.7; omega 0.7; epsilon 0.7; } fields { p 0.3; } }
EOF2

    sed -i 's/endTime [0-9][0-9]*;/endTime '"$NITERS"';/' "$dir/system/controlDict"
    sed -i 's/writeInterval [0-9][0-9]*;/writeInterval '"$NITERS"';/' "$dir/system/controlDict"
    grep -q "^libs" "$dir/system/controlDict" || sed -i '/^}/a libs (nnTurbulenceModels);' "$dir/system/controlDict"

    cd "$dir"
    timeout 300 simpleFoam > log.simpleFoam 2>&1
    local rc=$?
    cd "$BASE"

    local iters
    iters=$(grep -c "^Time = " "$dir/log.simpleFoam" 2>/dev/null || echo 0)
    if [ "$iters" -ge "$NITERS" ]; then
        local exec_time turb_ms p_ms gamg ms_per_iter
        exec_time=$(grep "^ExecutionTime" "$dir/log.simpleFoam" | tail -1 | awk '{print $3}')
        ms_per_iter=$(echo "scale=1; $exec_time * 1000 / $iters" | bc)
        turb_ms=$(grep "turb correct:" "$dir/log.simpleFoam" | tail -1 | awk '{print $3}')
        p_ms=$(grep "p solve:" "$dir/log.simpleFoam" | tail -1 | awk '{print $3}')
        gamg=$(grep "GAMG.*No Iterations" "$dir/log.simpleFoam" | tail -1 | sed 's/.*No Iterations //')
        echo "RESULT|$exp_name|$model_name|$ms_per_iter|${turb_ms:--}|${p_ms:--}|${gamg:--}|$iters"
    else
        local err
        err=$(grep -i "fatal\|nan\|diverge" "$dir/log.simpleFoam" 2>/dev/null | head -1)
        echo "RESULT|$exp_name|$model_name|FAIL($iters/$NITERS)|${err:-(timeout/stuck)}"
    fi
}

P_FIXED2='p { solver GAMG; tolerance 0; relTol 0; maxIter 2; smoother GaussSeidel; nPreSweeps 0; nPostSweeps 2; cacheAgglomeration true; nCellsInCoarsestLevel 10; agglomerator faceAreaPair; mergeLevels 1; }'
P_RELTOL='p { solver GAMG; tolerance 1e-06; relTol 0.01; smoother GaussSeidel; nPreSweeps 0; nPostSweeps 2; cacheAgglomeration true; nCellsInCoarsestLevel 10; agglomerator faceAreaPair; mergeLevels 1; }'

echo "=============================="
echo "Experiment 1: fixed2 (2 GAMG V-cycles)"
echo "=============================="
for entry in "${MODELS[@]}"; do
    IFS='|' read -r model_name turb_props <<< "$entry"
    echo "--- $model_name (fixed2) ---"
    run_one "$model_name" "$turb_props" "fixed2" "$P_FIXED2"
done

echo ""
echo "=============================="
echo "Experiment 2: reltol01 (relTol 0.01)"
echo "=============================="
for entry in "${MODELS[@]}"; do
    IFS='|' read -r model_name turb_props <<< "$entry"
    echo "--- $model_name (reltol01) ---"
    run_one "$model_name" "$turb_props" "reltol01" "$P_RELTOL"
done

echo ""
echo "=============================="
echo "ALL EXPERIMENTS COMPLETE"
echo "=============================="
