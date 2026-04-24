#!/bin/bash
#SBATCH -J gci_sphere_hires
#SBATCH -A gts-sbryngelson3 --qos embers
#SBATCH -N 1 --ntasks-per-node=1 --gres=gpu:H200:1
#SBATCH -t 4:00:00
#SBATCH --array=0-3
#SBATCH -o /storage/scratch1/6/sbryngelson3/spuma_cases/convergence_runs/gci_sphere_hires_%A_%a.log

# 2 closures x 2 Re = 4 array tasks.
# Closures: fusedKOmegaSST (baseline), fusedEARSMhellsten (anisotropy reference).

set -euo pipefail
source /storage/scratch1/6/sbryngelson3/spuma_cases/setup_spuma_env.sh

BASE=/storage/scratch1/6/sbryngelson3/spuma_cases

CONFIGS=(
    "200|fusedKOmegaSST|simulationType RAS; RAS { RASModel fusedKOmegaSST; turbulence on; printCoeffs on; }"
    "200|fusedEARSMhellsten|simulationType RAS; RAS { RASModel fusedEARSMhellsten; turbulence on; printCoeffs on; }"
    "300|fusedKOmegaSST|simulationType RAS; RAS { RASModel fusedKOmegaSST; turbulence on; printCoeffs on; }"
    "300|fusedEARSMhellsten|simulationType RAS; RAS { RASModel fusedEARSMhellsten; turbulence on; printCoeffs on; }"
)

IFS='|' read -r RE_TAG MODEL TURB <<< "${CONFIGS[$SLURM_ARRAY_TASK_ID]}"

TEMPLATE=$BASE/sphere_re${RE_TAG}_hires_template
DIR=$BASE/convergence_runs/sphere_re${RE_TAG}_hires__${MODEL}
NITERS=3000

echo "======================================="
echo " GCI sphere_hires Re=${RE_TAG} model=${MODEL}"
echo "======================================="

rm -rf "$DIR"
cp -r "$TEMPLATE" "$DIR"
rm -rf "$DIR"/constant/polyMesh "$DIR"/log* "$DIR"/[1-9]*

[ -d "$DIR/constant/nn_weights" ] || cp -r "$BASE/cylinder_nn_template/constant/nn_weights" "$DIR/constant/nn_weights"

for scheme in "div(phi,omega)" "div(phi,epsilon)" "div(phi,R)" "div(nonlinearStress)"; do
    grep -q "$scheme" "$DIR/system/fvSchemes" || \
        sed -i "/div(phi,k)/a\\    $scheme  Gauss linear;" "$DIR/system/fvSchemes"
done
grep -q "wallDist" "$DIR/system/fvSchemes" || echo 'wallDist { method meshWave; }' >> "$DIR/system/fvSchemes"

cat > "$DIR/constant/turbulenceProperties" << EOF2
FoamFile { version 2.0; format ascii; class dictionary; object turbulenceProperties; }
$TURB
EOF2

cat > "$DIR/system/fvSolution" << 'EOF2'
FoamFile { version 2.0; format ascii; class dictionary; object fvSolution; }
solvers { p { solver GAMG; tolerance 1e-06; relTol 0.01; smoother GaussSeidel; nPreSweeps 0; nPostSweeps 2; cacheAgglomeration true; nCellsInCoarsestLevel 10; agglomerator faceAreaPair; mergeLevels 1; } U { solver smoothSolver; smoother symGaussSeidel; tolerance 1e-06; relTol 0.1; } "(k|omega|epsilon|R)" { solver smoothSolver; smoother symGaussSeidel; tolerance 1e-06; relTol 0.1; } }
SIMPLE { nNonOrthogonalCorrectors 0; consistent yes; pRefCell 0; pRefValue 0; }
relaxationFactors { equations { U 0.7; k 0.7; omega 0.7; epsilon 0.7; } fields { p 0.3; } }
EOF2

sed -i "s/endTime .*/endTime         $NITERS;/" "$DIR/system/controlDict"
sed -i "s/writeInterval .*/writeInterval   $NITERS;/" "$DIR/system/controlDict"
sed -i '/libs.*nnTurbulenceModels/d' "$DIR/system/controlDict"
sed -i '/libs.*fvOptions/d' "$DIR/system/controlDict"
echo 'libs (libnnTurbulenceModels libfvOptions);' >> "$DIR/system/controlDict"

# Background mesh + sphere cut
echo "--- blockMesh ($(date)) ---"
blockMesh -case "$DIR" > "$DIR/log.blockMesh" 2>&1
tail -3 "$DIR/log.blockMesh"

echo "--- snappyHexMesh ($(date)) ---"
snappyHexMesh -overwrite -case "$DIR" > "$DIR/log.snappy" 2>&1
tail -5 "$DIR/log.snappy"

echo "--- simpleFoam ($(date)) ---"
START=$SECONDS
simpleFoam -pool fixedSizeMemoryPool -poolSize 16 -case "$DIR" > "$DIR/log" 2>&1
EXIT=$?
ELAPSED=$((SECONDS - START))
echo "simpleFoam exit=$EXIT, elapsed=${ELAPSED}s"
grep "ExecutionTime" "$DIR/log" | tail -1
echo "======================================="
