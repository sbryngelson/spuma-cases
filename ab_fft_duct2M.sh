#!/bin/bash
# A/B: duct_2M with fusedKOmegaSST, GAMG vs FFTPoisson for the p solver.
# Runs locally on the current GPU node. 15 SIMPLE iters each.

DIR="/storage/scratch1/6/sbryngelson3/spuma_cases"
cd "$DIR"
source "$DIR/setup_spuma_env.sh"
set -u

TMPL="$DIR/duct_2M_template"
WORK="$DIR/ab_fft_duct2M"
NITERS=15
TIMEOUT=600

rm -rf "$WORK"
mkdir -p "$WORK"

write_shared_dicts() {
    local case=$1 nIters=$2
    cat > "$case/system/controlDict" << CDEOF
FoamFile { version 2.0; format ascii; class dictionary; object controlDict; }
libs ("libnnTurbulenceModels.so" "libfvOptions.so");
application simpleFoam;
startFrom startTime; startTime 0; stopAt endTime; endTime $nIters; deltaT 1;
writeControl timeStep; writeInterval 99999; purgeWrite 0;
writeFormat ascii; writePrecision 8; writeCompression off;
timeFormat general; timePrecision 6; runTimeModifiable false;
CDEOF
    cat > "$case/system/fvSchemes" << 'FSEOF'
FoamFile { version 2.0; format ascii; class dictionary; object fvSchemes; }
ddtSchemes { default steadyState; }
gradSchemes { default Gauss linear; }
divSchemes { default none; div(phi,U) bounded Gauss linearUpwind grad(U); div(phi,k) bounded Gauss upwind; div(phi,omega) bounded Gauss upwind; div(phi,epsilon) bounded Gauss upwind; div(phi,R) bounded Gauss upwind; div(R) Gauss linear; div((nuEff*dev2(T(grad(U))))) Gauss linear; div(nonlinearStress) Gauss linear; }
laplacianSchemes { default Gauss linear corrected; }
interpolationSchemes { default linear; }
snGradSchemes { default corrected; }
wallDist { method meshWave; }
FSEOF
    cat > "$case/system/fvOptions" << 'OPTEOF'
FoamFile { version 2.0; format ascii; class dictionary; object fvOptions; }
momentumSource { type meanVelocityForce; selectionMode all; fields (U); Ubar (1 0 0); }
OPTEOF
    cat > "$case/constant/turbulenceProperties" << 'TEOF'
FoamFile { version 2.0; format ascii; class dictionary; object turbulenceProperties; }
simulationType RAS;
RAS { RASModel fusedKOmegaSST; turbulence on; }
TEOF
}

write_gamg_fvsolution() {
    cat > "$1/system/fvSolution" << 'FVEOF'
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

write_fft_fvsolution() {
    cat > "$1/system/fvSolution" << 'FVEOF'
FoamFile { version 2.0; format ascii; class dictionary; object fvSolution; }
solvers
{
    p
    {
        solver      FFTPoisson;
        Nx          128;
        Ny          128;
        Nz          128;
        Lx          6.283185;
        Ly          2;
        Lz          2;
        periodicX   yes;
        periodicY   no;
        periodicZ   no;
        tolerance   1e-06;
        relTol      0.1;
    }
    "(U|k|omega|epsilon|R)" { solver smoothSolver; smoother twoStageSymGaussSeidel; tolerance 1e-06; relTol 0.1; }
}
SIMPLE { nNonOrthogonalCorrectors 0; consistent yes; pRefCell 0; pRefValue 0; }
relaxationFactors { equations { U 0.7; k 0.7; omega 0.7; epsilon 0.7; R 0.7; } fields { p 0.3; } }
FVEOF
}

run_one() {
    local tag=$1 variant=$2
    local work="$WORK/${tag}"
    rm -rf "$work"
    cp -r "$TMPL" "$work"
    rm -rf "$work"/[1-9]* "$work"/postProcessing "$work"/log
    write_shared_dicts "$work" "$NITERS"
    "write_${variant}_fvsolution" "$work"
    cd "$work"
    timeout "$TIMEOUT" simpleFoam -pool fixedSizeMemoryPool -poolSize 32 > log 2>&1
    local rc=$?
    parse() { awk -v key="$1" '/FINAL Profiling/{flag=1;next} flag && index($0,key){for(i=1;i<=NF;i++) if($i~/^[0-9.eE+-]+$/){print $i;exit}}' log; }
    local TOT TURB P U CONT
    TOT=$(parse "TOTAL:"); TURB=$(parse "turb correct:")
    P=$(parse "p solve:"); U=$(parse "U solve:")
    CONT=$(grep -oP 'global = \K-?[0-9.eE+-]+' log | tail -1)
    local NITERS_P
    NITERS_P=$(grep -c "Solving for p" log)
    printf "[%-6s] rc=%d  TOTAL=%-10s p=%-10s U=%-10s turb=%-10s  global_cont=%-10s  pSolves=%s\n" \
        "$tag" "$rc" "$TOT" "$P" "$U" "$TURB" "$CONT" "$NITERS_P"
    grep -q "FOAM FATAL" log && echo "  !!! FATAL in log (see $work/log)"
    cd "$DIR"
}

echo "=== A/B duct_2M fusedKOmegaSST ($NITERS iters) — $(date) ==="
echo "GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)"
echo "--- round 1 (warm-up both paths so second-run has hot caches) ---"
run_one "gamg_warm" gamg
run_one "fft_warm"  fft
echo "--- round 2 (measurement, reversed order) ---"
run_one "fft"  fft
run_one "gamg" gamg
echo "=== done $(date) ==="
