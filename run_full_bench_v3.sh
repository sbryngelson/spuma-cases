#!/bin/bash
source /storage/scratch1/6/sbryngelson3/spuma_cases/setup_spuma_env.sh 2>/dev/null

BASE=/storage/scratch1/6/sbryngelson3/spuma_cases
TEMPLATE=$BASE/cost100_duct_fusedKOmegaSST
NITERS=50

# All optimizations: GAMG 1 V-cycle twoStageGS + fusedMomentumSweeps=2 + fusedMomentumAssembly + fusedSIMPLEC
P_SOLVER='p { solver GAMG; tolerance 0; relTol 0; maxIter 1; smoother twoStageGaussSeidel; nPreSweeps 0; nPostSweeps 2; cacheAgglomeration true; nCellsInCoarsestLevel 10; agglomerator faceAreaPair; mergeLevels 1; }'

declare -a MODELS=(
    "fusedMixingLength|simulationType RAS; RAS { RASModel fusedMixingLength; turbulence on; }"
    "fusedKOmega|simulationType RAS; RAS { RASModel fusedKOmega; turbulence on; fusedKOmegaCoeffs { transportSweeps 1; } }"
    "fusedKOmegaMenter|simulationType RAS; RAS { RASModel fusedKOmegaMenter; turbulence on; fusedKOmegaMenterCoeffs { transportSweeps 1; } }"
    "fusedKOmegaSST|simulationType RAS; RAS { RASModel fusedKOmegaSST; turbulence on; }"
    "fusedEARSMwj|simulationType RAS; RAS { RASModel fusedEARSMwj; turbulence on; }"
    "fusedEARSMgs|simulationType RAS; RAS { RASModel fusedEARSMgs; turbulence on; }"
    "nnTBNN-small|simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/tbnn_small_paper\"; nutMax 1.0; } }"
    "nnTBNN-med|simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/tbnn_paper\"; nutMax 1.0; } }"
    "nnTBNN-large|simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/tbnn_large_paper\"; nutMax 1.0; } }"
    "PI-TBNN-small|simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/pi_tbnn_small_paper\"; nutMax 1.0; } }"
    "PI-TBNN-med|simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/pi_tbnn_paper\"; nutMax 1.0; } }"
    "PI-TBNN-large|simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/pi_tbnn_large_paper\"; nutMax 1.0; } }"
    "nnMLP-small|simulationType RAS; RAS { RASModel nnMLP; turbulence on; nnMLPCoeffs { weightsDir \"constant/nn_weights/mlp_paper\"; nutMax 1.0; } }"
    "nnMLP-med|simulationType RAS; RAS { RASModel nnMLP; turbulence on; nnMLPCoeffs { weightsDir \"constant/nn_weights/mlp_med_paper\"; nutMax 1.0; } }"
    "nnMLP-large|simulationType RAS; RAS { RASModel nnMLP; turbulence on; nnMLPCoeffs { weightsDir \"constant/nn_weights/mlp_large_paper\"; nutMax 1.0; } }"
    "nnTBRF-1t|simulationType RAS; RAS { RASModel nnTBRF; turbulence on; nnTBRFCoeffs { weightsDir \"constant/nn_weights/tbrf_1t_paper\"; nutMax 1.0; } }"
    "nnTBRF-5t|simulationType RAS; RAS { RASModel nnTBRF; turbulence on; nnTBRFCoeffs { weightsDir \"constant/nn_weights/tbrf_5t_paper\"; nutMax 1.0; } }"
    "nnTBRF-10t|simulationType RAS; RAS { RASModel nnTBRF; turbulence on; nnTBRFCoeffs { weightsDir \"constant/nn_weights/tbrf_10t_paper\"; nutMax 1.0; } }"
)

echo "=== Full benchmark v3: all optimizations (GAMG-1cyc-twoStageGS + fusedMomAsm + fusedMomSweeps=2 + fusedSIMPLEC), $NITERS iters, duct 885K ==="
echo ""
printf "%-20s %7s  %7s  %7s  %7s  %7s  %7s  %6s  %s\n" "MODEL" "TOTAL" "U_asm" "U_slv" "p_set" "p_slv" "turb" "cont" "status"
echo "-------------------- -------  -------  -------  -------  -------  -------  ------  ------"

for entry in "${MODELS[@]}"; do
    IFS='|' read -r model_name turb_props <<< "$entry"
    dir="$BASE/bench_v3_${model_name}"
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
    $P_SOLVER
    U { solver smoothSolver; smoother symGaussSeidel; tolerance 1e-06; relTol 0.1; }
    "(k|omega|epsilon|R)" { solver smoothSolver; smoother twoStageGaussSeidel; nSweeps -1; tolerance 0; relTol 0; }
}
SIMPLE { nNonOrthogonalCorrectors 0; consistent yes; pRefCell 0; pRefValue 0; fusedMomentumSweeps 2; fusedMomentumAssembly true; fusedSIMPLEC true; }
relaxationFactors { equations { U 0.7; k 0.7; omega 0.7; epsilon 0.7; } fields { p 0.3; } }
EOF2

    sed -i 's/endTime [0-9][0-9]*/endTime '"$NITERS"'/' "$dir/system/controlDict"
    sed -i 's/writeInterval [0-9][0-9]*/writeInterval '"$NITERS"'/' "$dir/system/controlDict"
    grep -q "^libs" "$dir/system/controlDict" || sed -i '/^}/a libs (nnTurbulenceModels);' "$dir/system/controlDict"

    cd "$dir"
    timeout 300 simpleFoam > log.simpleFoam 2>&1
    iters=$(grep -c "^Time = " log.simpleFoam 2>/dev/null || echo 0)
    if [ "$iters" -ge "$NITERS" ]; then
        total=$(grep "TOTAL:" log.simpleFoam | tail -1 | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]/) {print $i; exit}}')
        uasm=$(grep "U assembly:" log.simpleFoam | tail -1 | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]/) {print $i; exit}}')
        uslv=$(grep "U solve:" log.simpleFoam | tail -1 | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]/) {print $i; exit}}')
        pset=$(grep "p setup:" log.simpleFoam | tail -1 | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]/) {print $i; exit}}')
        pslv=$(grep "p solve:" log.simpleFoam | tail -1 | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]/) {print $i; exit}}')
        turb=$(grep "turb correct:" log.simpleFoam | tail -1 | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]/) {print $i; exit}}')
        cont=$(grep "continuity" log.simpleFoam | tail -1 | sed 's/.*sum local = \([^,]*\).*/\1/')
        printf "%-20s %7.1f  %7.1f  %7.1f  %7.1f  %7.1f  %7.1f  %s  OK\n" \
            "$model_name" "$total" "$uasm" "$uslv" "$pset" "$pslv" "$turb" "$cont"
    else
        printf "%-20s FAIL (%s/%s iters)\n" "$model_name" "$iters" "$NITERS"
        grep -i "fatal\|error" log.simpleFoam | head -1
    fi
    # Clean up time dirs to save disk
    rm -rf "$dir"/[1-9]* "$dir"/processor*
done

echo ""
echo "=== Benchmark complete ==="
