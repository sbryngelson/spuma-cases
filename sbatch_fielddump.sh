#!/bin/bash
#SBATCH --job-name=fdump
#SBATCH --partition=gpu-h200
#SBATCH --account=gts-sbryngelson3
#SBATCH --qos=embers
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --gres=gpu:H200:1
#SBATCH --time=1:00:00
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err

# Field-dump worker: run one (CASE, MODEL) combo with final field written.
# Used for flow-field viz panels in the paper.
#
# Pass via: --export=ALL,CASE=<c>,MODEL=<m> [,HARDCAP=<n>]

DIR="/storage/scratch1/6/sbryngelson3/spuma_cases"
cd "$DIR"
source "$DIR/setup_spuma_env.sh" || { echo "FATAL: env"; exit 1; }

OUT="$DIR/fielddump_runs/${CASE}__${MODEL}"
mkdir -p "$(dirname "$OUT")"
rm -rf "$OUT"

# Pick template
case "$CASE" in
    cylinder)        TPL="$DIR/cylinder_nn_template"      ; HCAP=${HARDCAP:-1500}; LIBS='"libnnTurbulenceModels.so"' ;;
    duct)            TPL="$DIR/duct_nn_template_gpu"      ; HCAP=${HARDCAP:-3000}; LIBS='"libnnTurbulenceModels.so"' ;;
    hills)           TPL="$DIR/hills_sst"                 ; HCAP=${HARDCAP:-3000}; LIBS='"libnnTurbulenceModels.so" "libfvOptions.so"' ;;
    *) echo "unknown CASE=$CASE"; exit 2 ;;
esac

cp -a "$TPL" "$OUT"
cd "$OUT"

# Strip any prior saved time dirs so we start clean from 0/
rm -rf 100 200 300 500 1000 2000 3000 constant/polyMesh/sets 2>/dev/null || true

# Symlink NN weights from cylinder template if missing (hills_sst template doesn't have them)
if [ ! -d "constant/nn_weights" ] && [ -d "$DIR/cylinder_nn_template/constant/nn_weights" ]; then
    ln -s "$DIR/cylinder_nn_template/constant/nn_weights" "constant/nn_weights"
fi

# Map MODEL → turbulenceProperties block
case "$MODEL" in
    fusedKOmegaSST)    BLK="simulationType RAS; RAS { RASModel fusedKOmegaSST; turbulence on; }" ;;
    fusedKOmegaMenter) BLK="simulationType RAS; RAS { RASModel fusedKOmegaMenter; turbulence on; }" ;;
    fusedKOmega)       BLK="simulationType RAS; RAS { RASModel fusedKOmega; turbulence on; }" ;;
    fusedMixingLength) BLK="simulationType RAS; RAS { RASModel fusedMixingLength; turbulence on; }" ;;
    fusedEARSMwj)      BLK="simulationType RAS; RAS { RASModel fusedEARSMwj; turbulence on; }" ;;
    fusedEARSMhellsten) BLK="simulationType RAS; RAS { RASModel fusedEARSMhellsten; turbulence on; }" ;;
    fusedEARSMgs)      BLK="simulationType RAS; RAS { RASModel fusedEARSMgs; turbulence on; }" ;;
    fusedRSM)          BLK="simulationType RAS; RAS { RASModel fusedRSM; turbulence on; }" ;;
    fusedGEP)          BLK="simulationType RAS; RAS { RASModel fusedGEP; turbulence on; }" ;;
    nnMLP-small)       BLK="simulationType RAS; RAS { RASModel nnMLP;  turbulence on; nnMLPCoeffs  { weightsDir \"constant/nn_weights/mlp_paper\";       nutMax 1.0; } }" ;;
    nnMLP-med)         BLK="simulationType RAS; RAS { RASModel nnMLP;  turbulence on; nnMLPCoeffs  { weightsDir \"constant/nn_weights/mlp_med_paper\";   nutMax 1.0; } }" ;;
    nnMLP-large)       BLK="simulationType RAS; RAS { RASModel nnMLP;  turbulence on; nnMLPCoeffs  { weightsDir \"constant/nn_weights/mlp_large_paper\"; nutMax 1.0; } }" ;;
    nnTBNN-small)      BLK="simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/tbnn_small_paper\"; nutMax 1.0; } }" ;;
    nnTBNN-med)        BLK="simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/tbnn_paper\";       nutMax 1.0; } }" ;;
    nnTBNN-large)      BLK="simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/tbnn_large_paper\"; nutMax 1.0; } }" ;;
    nnPITBNN-small)    BLK="simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/pi_tbnn_small_paper\"; nutMax 1.0; } }" ;;
    nnPITBNN-med)      BLK="simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/pi_tbnn_paper\";       nutMax 1.0; } }" ;;
    nnPITBNN-large)    BLK="simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/pi_tbnn_large_paper\"; nutMax 1.0; } }" ;;
    nnTBRF-1t)         BLK="simulationType RAS; RAS { RASModel nnTBRF; turbulence on; nnTBRFCoeffs { weightsDir \"constant/nn_weights/tbrf_1t_paper\";  nutMax 1.0; } }" ;;
    nnTBRF-5t)         BLK="simulationType RAS; RAS { RASModel nnTBRF; turbulence on; nnTBRFCoeffs { weightsDir \"constant/nn_weights/tbrf_5t_paper\";  nutMax 1.0; } }" ;;
    nnTBRF-10t)        BLK="simulationType RAS; RAS { RASModel nnTBRF; turbulence on; nnTBRFCoeffs { weightsDir \"constant/nn_weights/tbrf_10t_paper\"; nutMax 1.0; } }" ;;
    *) echo "unknown MODEL=$MODEL"; exit 3 ;;
esac

cat > constant/turbulenceProperties << EOF
FoamFile { version 2.0; format ascii; class dictionary; object turbulenceProperties; }
$BLK
EOF

# fvSchemes — full set for any k/omega/epsilon/R turbulence variant
cat > system/fvSchemes << 'FSEOF'
FoamFile { version 2.0; format ascii; class dictionary; object fvSchemes; }
ddtSchemes      { default steadyState; }
gradSchemes     { default Gauss linear; }
divSchemes
{
    default             none;
    div(phi,U)          bounded Gauss linearUpwind grad(U);
    div(phi,k)          bounded Gauss upwind;
    div(phi,omega)      bounded Gauss upwind;
    div(phi,epsilon)    bounded Gauss upwind;
    div(phi,R)          bounded Gauss upwind;
    div(R)              Gauss linear;
    div((nuEff*dev2(T(grad(U))))) Gauss linear;
    div((nu*dev2(T(grad(U)))))    Gauss linear;
    div(nonlinearStress) Gauss linear;
}
laplacianSchemes { default Gauss linear corrected; }
interpolationSchemes { default linear; }
snGradSchemes    { default corrected; }
wallDist { method meshWave; }
FSEOF

# controlDict — write ONLY the final step (writeInterval=HARDCAP, purgeWrite=0)
cat > system/controlDict << EOF
FoamFile { version 2.0; format ascii; class dictionary; object controlDict; }
libs ($LIBS);
application simpleFoam;
startFrom startTime; startTime 0; stopAt endTime; endTime $HCAP; deltaT 1;
writeControl timeStep; writeInterval $HCAP; purgeWrite 0;
writeFormat ascii; writePrecision 8; writeCompression off;
timeFormat general; timePrecision 6; runTimeModifiable false;
EOF

# Duct/hills need meanVelocityForce (periodic)
if [[ "$CASE" == "duct" || "$CASE" == "hills" ]]; then
    cat > system/fvOptions << 'FVEOF'
momentumSource
{
    type            meanVelocityForce;
    active          yes;
    selectionMode   all;
    fields          (U);
    Ubar            (1 0 0);
}
FVEOF
fi

echo "=== field-dump: $CASE $MODEL, $HCAP iters ==="
echo "host: $(hostname)"
echo "GPU:  $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)"
date
simpleFoam -pool fixedSizeMemoryPool -poolSize 16 > log.simpleFoam 2>&1
echo "rc=$?"
ls -d [0-9]* 2>/dev/null
date
echo "=== done ==="
