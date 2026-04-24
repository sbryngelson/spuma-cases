#!/bin/bash
#SBATCH -J gci_hills
#SBATCH -A gts-sbryngelson3 --qos embers
#SBATCH -N 1 --ntasks-per-node=1 --gres=gpu:H200:1
#SBATCH -t 5:00:00
#SBATCH -o /storage/scratch1/6/sbryngelson3/spuma_cases/convergence_runs/gci_hills_%j.log

# One (Re, model) per job. Submit via:
#   sbatch --export=ALL,RE_TAG=2800,MODEL=fusedKOmegaSST,TURB="<props>" sbatch_gci_hills_one.sh
# See submit_gci_hills_sphere.sh for the batch submitter.
#
# No `set -u`: OpenFOAM's etc/bashrc touches unbound variables.

source /storage/scratch1/6/sbryngelson3/spuma_cases/setup_spuma_env.sh

: "${RE_TAG:?RE_TAG required (2800 or 10595)}"
: "${MODEL:?MODEL required (fusedKOmegaSST, fusedRSM, PI-TBNN-med)}"
: "${TURB:?TURB required (turbulenceProperties body)}"

BASE=/storage/scratch1/6/sbryngelson3/spuma_cases
TEMPLATE=$BASE/hills_re${RE_TAG}_hires_template
DIR=$BASE/convergence_runs/hills_re${RE_TAG}_hires__${MODEL}
NITERS=3000

echo "======================================="
echo " GCI hills_hires Re=${RE_TAG} model=${MODEL}"
echo "======================================="
date
rm -rf "$DIR"
cp -r "$TEMPLATE" "$DIR"
rm -rf "$DIR"/constant/polyMesh "$DIR"/log* "$DIR"/[1-9]*

[ -d "$DIR/constant/nn_weights" ] || cp -r "$BASE/cylinder_nn_template/constant/nn_weights" "$DIR/constant/nn_weights"

for scheme in "div(phi,omega)" "div(phi,epsilon)" "div(phi,R)" "div(nonlinearStress)"; do
    grep -q "$scheme" "$DIR/system/fvSchemes" || \
        sed -i "/div(phi,k)/a\\    $scheme  Gauss linear;" "$DIR/system/fvSchemes"
done
grep -q "wallDist" "$DIR/system/fvSchemes" || echo 'wallDist { method meshWave; }' >> "$DIR/system/fvSchemes"

[ -f "$DIR/system/fvOptions" ] && {
    sed -i 's/selectionMode.*cellZone;/selectionMode   all;/' "$DIR/system/fvOptions"
    sed -i '/cellZone.*inletCellZone/d' "$DIR/system/fvOptions"
}

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

echo "--- blockMesh ($(date)) ---"
blockMesh -case "$DIR" > "$DIR/log.blockMesh" 2>&1
tail -5 "$DIR/log.blockMesh"

echo "--- simpleFoam ($(date)) ---"
START=$SECONDS
simpleFoam -pool fixedSizeMemoryPool -poolSize 48 -case "$DIR" > "$DIR/log" 2>&1
EXIT=$?
ELAPSED=$((SECONDS - START))
echo "simpleFoam exit=$EXIT, elapsed=${ELAPSED}s"
grep "ExecutionTime" "$DIR/log" | tail -1
