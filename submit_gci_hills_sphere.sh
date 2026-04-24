#!/bin/bash
# Submit 10 individual SLURM jobs for the hills + sphere hires GCI study.
# Each job is one (Re, closure) pair so wall time stays short and embers
# queue priority stays high.
cd /storage/scratch1/6/sbryngelson3/spuma_cases

TBNN_TURB='simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir "constant/nn_weights/pi_tbnn_paper"; nutMax 1.0; } }'

echo "=== hills_hires (6 jobs, 5h each) ==="
for RE in 2800 10595; do
    for ENTRY in \
        "fusedKOmegaSST|simulationType RAS; RAS { RASModel fusedKOmegaSST; turbulence on; printCoeffs on; }" \
        "fusedRSM|simulationType RAS; RAS { RASModel fusedRSM; turbulence on; printCoeffs on; }" \
        "PI-TBNN-med|${TBNN_TURB}"; do
        IFS='|' read -r M T <<< "$ENTRY"
        JID=$(sbatch --parsable --export=ALL,RE_TAG=$RE,MODEL="$M",TURB="$T" sbatch_gci_hills_one.sh)
        echo "  hills Re=$RE model=$M  jobID=$JID"
    done
done

echo "=== sphere_hires (4 jobs, 2h each) ==="
for RE in 200 300; do
    for ENTRY in \
        "fusedKOmegaSST|simulationType RAS; RAS { RASModel fusedKOmegaSST; turbulence on; printCoeffs on; }" \
        "fusedEARSMhellsten|simulationType RAS; RAS { RASModel fusedEARSMhellsten; turbulence on; printCoeffs on; }"; do
        IFS='|' read -r M T <<< "$ENTRY"
        JID=$(sbatch --parsable --export=ALL,RE_TAG=$RE,MODEL="$M",TURB="$T" sbatch_gci_sphere_one.sh)
        echo "  sphere Re=$RE model=$M  jobID=$JID"
    done
done
