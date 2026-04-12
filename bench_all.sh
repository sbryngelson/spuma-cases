#!/bin/bash
# Benchmark ALL models. Fresh case copy for each run.
DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_SST="$DIR/cylinder_sst"
TEMPLATE_NN="$DIR/cylinder_nn_template"
WORKDIR="$DIR/bench_work"

run() {
    NAME=$1; TEMPLATE=$2; TURB=$3; LIBS=$4
    rm -rf "$WORKDIR"
    cp -r "$TEMPLATE" "$WORKDIR"
    cd "$WORKDIR"
    rm -rf [1-9]* postProcessing
    echo "$TURB" > constant/turbulenceProperties
    cat > system/controlDict << CDEOF
FoamFile { version 2.0; format ascii; class dictionary; object controlDict; }
${LIBS}
application simpleFoam; startFrom startTime; startTime 0; stopAt endTime; endTime 50; deltaT 1;
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
    timeout 120 simpleFoam -pool fixedSizeMemoryPool -poolSize 4 > log 2>&1
    TOT=$(grep "FINAL.*TOTAL:" log | awk '{print $2}')
    TURB_T=$(grep "FINAL.*turb correct:" log | awk '{print $2}')
    P_T=$(grep "FINAL.*p solve:" log | awk '{print $2}')
    if [ -z "$TOT" ]; then
        # Try 50-iter block instead of FINAL
        TOT=$(grep "Profiling (50" -A12 log | grep "TOTAL:" | awk '{print $2}')
        TURB_T=$(grep "Profiling (50" -A12 log | grep "turb correct:" | awk '{print $2}')
        P_T=$(grep "Profiling (50" -A12 log | grep "p solve:" | awk '{print $2}')
    fi
    if [ -z "$TOT" ]; then
        TOT="FAIL"
        TURB_T=$(tail -1 log | head -c 40)
    fi
    printf "%-25s  total=%7s  turb=%7s  p=%7s\n" "$NAME" "$TOT" "$TURB_T" "$P_T"
    cd "$DIR"
}

echo "=== All Models: Cylinder 68K, A100 cc80, 50 iters ==="

TP='FoamFile { version 2.0; format ascii; class dictionary; object turbulenceProperties; }'
L='libs (libnnTurbulenceModels);'

run "laminar"       "$TEMPLATE_SST" "$TP
simulationType laminar;" ""
run "kOmega"        "$TEMPLATE_SST" "$TP
simulationType RAS; RAS { RASModel kOmega; turbulence on; }" ""
run "kOmegaSST"     "$TEMPLATE_SST" "$TP
simulationType RAS; RAS { RASModel kOmegaSST; turbulence on; }" ""
run "nnMLP-small"   "$TEMPLATE_NN" "$TP
simulationType RAS; RAS { RASModel nnMLP; turbulence on; nnMLPCoeffs { weightsDir \"constant/nn_weights/mlp_paper\"; nutMax 1.0; } }" "$L"
run "nnMLP-med"     "$TEMPLATE_NN" "$TP
simulationType RAS; RAS { RASModel nnMLP; turbulence on; nnMLPCoeffs { weightsDir \"constant/nn_weights/mlp_med_paper\"; nutMax 1.0; } }" "$L"
run "nnMLP-large"   "$TEMPLATE_NN" "$TP
simulationType RAS; RAS { RASModel nnMLP; turbulence on; nnMLPCoeffs { weightsDir \"constant/nn_weights/mlp_large_paper\"; nutMax 1.0; } }" "$L"
run "nnTBNN-small"  "$TEMPLATE_NN" "$TP
simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/tbnn_small_paper\"; nutMax 1.0; } }" "$L"
run "nnTBNN-med"    "$TEMPLATE_NN" "$TP
simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/tbnn_paper\"; nutMax 1.0; } }" "$L"
run "nnTBNN-large"  "$TEMPLATE_NN" "$TP
simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/tbnn_large_paper\"; nutMax 1.0; } }" "$L"
run "nnPITBNN-small" "$TEMPLATE_NN" "$TP
simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/pi_tbnn_small_paper\"; nutMax 1.0; } }" "$L"
run "nnPITBNN-med"  "$TEMPLATE_NN" "$TP
simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/pi_tbnn_paper\"; nutMax 1.0; } }" "$L"
run "nnPITBNN-large" "$TEMPLATE_NN" "$TP
simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/pi_tbnn_large_paper\"; nutMax 1.0; } }" "$L"
run "nnTBRF-1t"     "$TEMPLATE_NN" "$TP
simulationType RAS; RAS { RASModel nnTBRF; turbulence on; nnTBRFCoeffs { weightsDir \"constant/nn_weights/tbrf_1t_paper\"; nutMax 1.0; } }" "$L"
run "nnTBRF-5t"     "$TEMPLATE_NN" "$TP
simulationType RAS; RAS { RASModel nnTBRF; turbulence on; nnTBRFCoeffs { weightsDir \"constant/nn_weights/tbrf_5t_paper\"; nutMax 1.0; } }" "$L"
run "nnTBRF-10t"    "$TEMPLATE_NN" "$TP
simulationType RAS; RAS { RASModel nnTBRF; turbulence on; nnTBRFCoeffs { weightsDir \"constant/nn_weights/tbrf_10t_paper\"; nutMax 1.0; } }" "$L"

rm -rf "$WORKDIR"
echo "=== Done ==="
