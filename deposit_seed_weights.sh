#!/bin/bash
# Deposit PI-TBNN-med seed weights from cfd-nn into cylinder_nn_template.
# Run once after each seed training job completes.
#
# Usage:
#   ./deposit_seed_weights.sh           # all seeds found in SRC
#   ./deposit_seed_weights.sh 42        # a single seed
#
# Reads:  $CFDNN/data/models/seed{N}/pi_tbnn_paper/{layer*.txt,input_*.txt,metadata.json}
# Writes: cylinder_nn_template/constant/nn_weights/pi_tbnn_paper_s{N}/<same files>

SRC=${CFDNN:-/storage/scratch1/6/sbryngelson3/cfd-nn}/data/models
DST=$(cd "$(dirname "$0")" && pwd)/cylinder_nn_template/constant/nn_weights

if [ $# -eq 0 ]; then
    SEEDS=$(ls -d "$SRC"/seed* 2>/dev/null | sed 's|.*/seed||' | sort -n)
else
    SEEDS="$@"
fi

if [ -z "$SEEDS" ]; then
    echo "No seed directories found under $SRC" >&2; exit 1
fi

for N in $SEEDS; do
    SRC_DIR="$SRC/seed$N/pi_tbnn_paper"
    DST_DIR="$DST/pi_tbnn_paper_s$N"
    if [ ! -d "$SRC_DIR" ] || [ ! -f "$SRC_DIR/layer0_W.txt" ]; then
        echo "SKIP seed=$N (missing or incomplete: $SRC_DIR)"
        continue
    fi
    rm -rf "$DST_DIR"
    mkdir -p "$DST_DIR"
    cp "$SRC_DIR"/{layer*,input_*,metadata.json} "$DST_DIR"/
    N_FILES=$(ls "$DST_DIR" | wc -l)
    echo "OK seed=$N  $SRC_DIR -> $DST_DIR  ($N_FILES files)"
done
