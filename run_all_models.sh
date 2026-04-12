#!/bin/bash
# Run all 21 turbulence models on a given case using SPUMA
# Usage: ./run_all_models.sh <template_case_dir> <output_dir> [pool_size_GB]
#
# The template case must have:
# - constant/nn_weights/ with all model weight directories
# - constant/turbulenceProperties.* for each model variant
# - 0/ with converged SST fields (k, omega, U, p, nut)

TEMPLATE=${1:?Usage: ./run_all_models.sh <template_case> <output_dir>}
OUTPUT=${2:?Usage: ./run_all_models.sh <template_case> <output_dir>}
POOL_SIZE=${3:-4}

WEIGHTS_DIR="$TEMPLATE/constant/nn_weights"

# Classical RANS models (built-in OpenFOAM)
CLASSICAL_MODELS=(
    "laminar"          # No turbulence model
    "kOmega"           # Standard k-omega
    "kOmegaSST"        # SST k-omega (baseline)
)

# NN model weight directories → model type mapping
declare -A NN_MODELS
NN_MODELS=(
    ["mlp_paper"]="nnMLP"
    ["mlp_med_paper"]="nnMLP"
    ["mlp_large_paper"]="nnMLP"
    ["tbnn_paper"]="nnTBNN"
    ["tbnn_small_paper"]="nnTBNN"
    ["tbnn_large_paper"]="nnTBNN"
    ["pi_tbnn_paper"]="nnTBNN"
    ["pi_tbnn_small_paper"]="nnTBNN"
    ["pi_tbnn_large_paper"]="nnTBNN"
    ["tbrf_1t_paper"]="nnTBRF"
    ["tbrf_5t_paper"]="nnTBRF"
    ["tbrf_10t_paper"]="nnTBRF"
)

mkdir -p "$OUTPUT"

# Run classical models
for MODEL in "${CLASSICAL_MODELS[@]}"; do
    echo "=== Running $MODEL ==="
    CASE_DIR="$OUTPUT/$MODEL"
    cp -r "$TEMPLATE" "$CASE_DIR"

    # Set turbulence model
    cat > "$CASE_DIR/constant/turbulenceProperties" << EOF
FoamFile { version 2.0; format ascii; class dictionary; object turbulenceProperties; }
simulationType RAS;
RAS { RASModel $MODEL; turbulence on; printCoeffs on; }
EOF

    cd "$CASE_DIR"
    simpleFoam -pool fixedSizeMemoryPool -poolSize "$POOL_SIZE" \
        > log.simpleFoam 2>&1
    echo "  Done: $(tail -1 log.simpleFoam)"
    cd -
done

# Run NN models
for WEIGHTS_NAME in "${!NN_MODELS[@]}"; do
    MODEL_TYPE="${NN_MODELS[$WEIGHTS_NAME]}"
    echo "=== Running $WEIGHTS_NAME ($MODEL_TYPE) ==="
    CASE_DIR="$OUTPUT/$WEIGHTS_NAME"
    cp -r "$TEMPLATE" "$CASE_DIR"

    cat > "$CASE_DIR/constant/turbulenceProperties" << EOF
FoamFile { version 2.0; format ascii; class dictionary; object turbulenceProperties; }
simulationType RAS;
RAS
{
    RASModel    $MODEL_TYPE;
    turbulence  on;
    printCoeffs on;
    ${MODEL_TYPE}Coeffs
    {
        weightsDir  "constant/nn_weights/$WEIGHTS_NAME";
        nutMax      1.0;
    }
}
EOF

    cd "$CASE_DIR"
    simpleFoam -pool fixedSizeMemoryPool -poolSize "$POOL_SIZE" \
        > log.simpleFoam 2>&1
    echo "  Done: $(tail -1 log.simpleFoam)"
    cd -
done

echo "=== All models complete ==="
