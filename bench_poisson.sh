#!/bin/bash
# Benchmark pressure solver variants on cylinder SST
# Usage: source spuma env first, then ./bench_poisson.sh

CASE_BASE="cylinder_sst"
NWARMUP=50
NBENCH=50

run_config() {
    local NAME=$1
    local SOLVER_BLOCK=$2
    
    echo "=== $NAME ==="
    
    # Copy fresh case
    cp -r $CASE_BASE bench_tmp
    cd bench_tmp
    rm -rf [1-9]* processor*
    
    # Set endTime to warmup+bench
    local TOTAL=$((NWARMUP + NBENCH))
    cat > system/controlDict << EOF
FoamFile { version 2.0; format ascii; class dictionary; object controlDict; }
application simpleFoam;
startFrom startTime;
startTime 0;
stopAt endTime;
endTime $TOTAL;
deltaT 1;
writeControl timeStep;
writeInterval $TOTAL;
purgeWrite 1;
writeFormat ascii;
writePrecision 8;
writeCompression off;
timeFormat general;
timePrecision 6;
runTimeModifiable false;
profiling { active true; }
EOF
    
    # Set solver config
    cat > system/fvSolution << EOF
FoamFile { version 2.0; format ascii; class dictionary; object fvSolution; }
solvers
{
    p { $SOLVER_BLOCK }
    "(U|k|omega)"
    {
        solver smoothSolver;
        smoother symGaussSeidel;
        tolerance 1e-06;
        relTol 0.1;
    }
}
SIMPLE
{
    nNonOrthogonalCorrectors 0;
    consistent yes;
    pRefCell 0;
    pRefValue 0;
}
relaxationFactors
{
    equations { U 0.7; k 0.7; omega 0.7; }
    fields { p 0.3; }
}
EOF
    
    simpleFoam -pool fixedSizeMemoryPool -poolSize 4 > log.simpleFoam 2>&1
    
    # Extract pressure solve time from profiling
    local P_TIME=$(grep -A3 'description.*"fvMatrix::solve.p"' $TOTAL/uniform/profiling 2>/dev/null | grep totalTime | awk '{print $2}' | tr -d ';')
    local TOTAL_TIME=$(grep -A3 'description.*"time.run()"' $TOTAL/uniform/profiling 2>/dev/null | grep totalTime | awk '{print $2}' | tr -d ';')
    
    # Also get last execution time line
    local EXEC_TIME=$(grep "ExecutionTime" log.simpleFoam | tail -1)
    
    echo "  Pressure: ${P_TIME}s / Total: ${TOTAL_TIME}s"
    echo "  Pressure per-iter: $(echo "scale=1; $P_TIME / $TOTAL * 1000" | bc 2>/dev/null)ms"
    echo "  $EXEC_TIME"
    
    cd ..
    rm -rf bench_tmp
}

# 1. GAMG (default)
run_config "GAMG (default)" "
        solver GAMG;
        smoother GaussSeidel;
        tolerance 1e-06;
        relTol 0.01;
"

# 2. GAMG with GPU smoother
run_config "GAMG + twoStageGaussSeidel" "
        solver GAMG;
        smoother twoStageGaussSeidel;
        tolerance 1e-06;
        relTol 0.01;
"

# 3. PCG + GAMG preconditioner
run_config "PCG + GAMG precond" "
        solver PCG;
        preconditioner GAMG;
        tolerance 1e-06;
        relTol 0.01;
"

# 4. PCG + aDIC (GPU diagonal IC)
run_config "PCG + aDIC (GPU)" "
        solver PCG;
        preconditioner aDIC;
        tolerance 1e-06;
        relTol 0.01;
"

# 5. GAMG aggressive coarsening
run_config "GAMG aggressive" "
        solver GAMG;
        smoother GaussSeidel;
        tolerance 1e-06;
        relTol 0.01;
        nCellsInCoarsestLevel 100;
        agglomerator faceAreaPair;
        mergeLevels 2;
"

# 6. PCG + DIC (CPU)
run_config "PCG + DIC (CPU)" "
        solver PCG;
        preconditioner DIC;
        tolerance 1e-06;
        relTol 0.01;
"

# 7. Relaxed tolerance
run_config "GAMG relTol=0.1" "
        solver GAMG;
        smoother GaussSeidel;
        tolerance 1e-06;
        relTol 0.1;
"

echo "=== DONE ==="
