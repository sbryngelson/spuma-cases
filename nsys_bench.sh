#!/bin/bash
DIR="/storage/scratch1/6/sbryngelson3/spuma_cases"
cd "$DIR"
source "$DIR/setup_spuma_env.sh"
set -u

WORK="$DIR/nsys_runs"
rm -rf "$WORK"; mkdir -p "$WORK"
export TMPDIR=/storage/scratch1/6/sbryngelson3/nsys_tmp
mkdir -p "$TMPDIR"

TMPL="$DIR/duct_re2500_template"   # 96^3 = 884k cells
NITERS=5

setup_case() {
    local work=$1 turb_block=$2
    rm -rf "$work"; cp -r "$TMPL" "$work"
    [[ ! -d "$work/constant/nn_weights" && -d "$DIR/cylinder_nn_template/constant/nn_weights" ]] && \
        ln -s "$DIR/cylinder_nn_template/constant/nn_weights" "$work/constant/nn_weights"
    rm -rf "$work"/[1-9]* "$work"/postProcessing "$work"/log
    cat > "$work/system/controlDict" << CDEOF
FoamFile { version 2.0; format ascii; class dictionary; object controlDict; }
libs ("libnnTurbulenceModels.so" "libfvOptions.so");
application simpleFoam;
startFrom startTime; startTime 0; stopAt endTime; endTime $NITERS; deltaT 1;
writeControl timeStep; writeInterval 99999; purgeWrite 0;
writeFormat ascii; writePrecision 8; writeCompression off;
timeFormat general; timePrecision 6; runTimeModifiable false;
CDEOF
    cat > "$work/system/fvSchemes" << 'FSEOF'
FoamFile { version 2.0; format ascii; class dictionary; object fvSchemes; }
ddtSchemes { default steadyState; }
gradSchemes { default Gauss linear; }
divSchemes { default none; div(phi,U) bounded Gauss linearUpwind grad(U); div(phi,k) bounded Gauss upwind; div(phi,omega) bounded Gauss upwind; div(phi,epsilon) bounded Gauss upwind; div(phi,R) bounded Gauss upwind; div(R) Gauss linear; div((nuEff*dev2(T(grad(U))))) Gauss linear; div(nonlinearStress) Gauss linear; }
laplacianSchemes { default Gauss linear corrected; }
interpolationSchemes { default linear; }
snGradSchemes { default corrected; }
wallDist { method meshWave; }
FSEOF
    cat > "$work/system/fvSolution" << 'FVEOF'
FoamFile { version 2.0; format ascii; class dictionary; object fvSolution; }
solvers
{
    p { solver GAMG; smoother twoStageGaussSeidel; tolerance 1e-06; relTol 0.1; }
    "(U|k|omega|epsilon|R)" { solver smoothSolver; smoother twoStageSymGaussSeidel; tolerance 1e-06; relTol 0.1; }
}
SIMPLE { nNonOrthogonalCorrectors 0; consistent yes; pRefCell 0; pRefValue 0; }
relaxationFactors { equations { U 0.7; k 0.7; omega 0.7; epsilon 0.7; R 0.7; } fields { p 0.3; } }
FVEOF
    cat > "$work/system/fvOptions" << 'OPTEOF'
FoamFile { version 2.0; format ascii; class dictionary; object fvOptions; }
momentumSource { type meanVelocityForce; selectionMode all; fields (U); Ubar (1 0 0); }
OPTEOF
    cat > "$work/constant/turbulenceProperties" << EOF
FoamFile { version 2.0; format ascii; class dictionary; object turbulenceProperties; }
$turb_block
EOF
}

run_nsys() {
    local tag=$1 work=$2
    cd "$work"
    echo "--- $tag ($(date)) ---"
    nsys profile \
        --trace=cuda \
        --sample=none \
        --cuda-memory-usage=false \
        --force-overwrite true \
        --stats=true \
        --output "$WORK/${tag}" \
        simpleFoam -pool fixedSizeMemoryPool -poolSize 4 \
        > "$WORK/${tag}.log" 2>&1
    local rc=$?
    # Show profiling summary from OF log
    echo "=== OF profiling ==="
    awk '/FINAL Profiling/,0' "$WORK/${tag}.log" | head -15
    # Show top 15 GPU kernels from nsys
    echo "=== Top GPU kernels ==="
    grep -A100 "CUDA Kernel Statistics" "$WORK/${tag}.log" | head -30
    echo "=== CUDA API Summary ==="
    grep -A30 "CUDA API Statistics" "$WORK/${tag}.log" | head -20
    printf "[%-20s] rc=%d\n\n" "$tag" "$rc"
    cd "$DIR"
}

echo "=== nsys profile — duct 96^3 (884k cells), $NITERS iters — $(date) ==="
echo "GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)"

# Warmup both paths (JIT cache)
echo "--- warmup (SST) ---"
setup_case "$WORK/warmup" "simulationType RAS; RAS { RASModel fusedKOmegaSST; turbulence on; }"
cd "$WORK/warmup" && simpleFoam -pool fixedSizeMemoryPool -poolSize 4 > /dev/null 2>&1; cd "$DIR"
echo "--- warmup (TBNN) ---"
setup_case "$WORK/warmup2" "simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/tbnn_paper\"; nutMax 1.0; } }"
cd "$WORK/warmup2" && simpleFoam -pool fixedSizeMemoryPool -poolSize 4 > /dev/null 2>&1; cd "$DIR"

# Profile 1: fusedKOmegaSST (baseline classical)
setup_case "$WORK/sst" "simulationType RAS; RAS { RASModel fusedKOmegaSST; turbulence on; }"
run_nsys "sst" "$WORK/sst"

# Profile 2: nnTBNN-med (NN tensor)
setup_case "$WORK/tbnn" "simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/tbnn_paper\"; nutMax 1.0; } }"
run_nsys "tbnn" "$WORK/tbnn"

echo "=== done $(date) ==="
echo "Full nsys reports: $WORK/*.nsys-rep"
