#!/bin/bash
# Accuracy sweep: run each closure to convergence, extract QoIs.
# Unlike bench_h100_all.sh this runs to residualControl convergence (or a
# hard iteration cap) and leaves the final time dir + postProcessing/forces
# output in place for QoI extraction.
#
# Usage:
#   source setup_spuma_env.sh
#   MODEL=fusedKOmegaSST CASE=cylinder ./sweep_h100_accuracy.sh   # single run
#   CASES="cylinder duct" ./sweep_h100_accuracy.sh                # full per-case sweep
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
WORKROOT="${WORKROOT:-$DIR/acc_h100_runs}"
CSV="${CSV:-$DIR/acc_h100_results.csv}"
HARDCAP_cylinder=${HARDCAP_cylinder:-3000}
HARDCAP_duct=${HARDCAP_duct:-3000}
HARDCAP_hills=${HARDCAP_hills:-3000}
HARDCAP_sphere=${HARDCAP_sphere:-3000}
# Per-case timeouts (seconds).
# cylinder_hires (552k cells) at ~60ms/iter × 3000 = 180s; use 1200 for safety.
# Sphere (965k cells): ~160ms/iter × 3000 = 480s; use 1800 for safety.
# Duct/hills: ~90-150ms/iter × 3000 = 270-450s; use 5400.
TIMEOUT_cylinder=${TIMEOUT_cylinder:-${TIMEOUT:-1200}}
TIMEOUT_sphere=${TIMEOUT_sphere:-${TIMEOUT:-1800}}
TIMEOUT_duct=${TIMEOUT_duct:-${TIMEOUT:-5400}}
TIMEOUT_duct_re2500=${TIMEOUT_duct_re2500:-${TIMEOUT_duct:-5400}}
TIMEOUT_hills=${TIMEOUT_hills:-${TIMEOUT:-5400}}
TIMEOUT_hills_re10595=${TIMEOUT_hills_re10595:-${TIMEOUT_hills:-5400}}

mkdir -p "$WORKROOT"
if [ ! -s "$CSV" ]; then
    echo "case,model,exit,iters,walltime_s,p_res,U_res,Cd,Cl,converged,note" > "$CSV"
fi

declare -A CASE_TEMPLATE=(
    [cylinder]="$DIR/cylinder_hires_template"
    [cylinder_re40]="$DIR/cylinder_re40_template"
    [cylinder_re200]="$DIR/cylinder_re200_template"
    [cylinder_re300]="$DIR/cylinder_re300_template"
    [cylinder_re500]="$DIR/cylinder_re500_template"
    [duct]="$DIR/duct_2M_template"
    [duct_re2500]="$DIR/duct_re2500_template"
    [duct_re4400]="$DIR/duct_re4400_template"
    [duct_re6400]="$DIR/duct_re6400_template"
    [hills]="$DIR/hills_sst"
    [hills_re2800]="$DIR/hills_re2800_template"
    [hills_re5600]="$DIR/hills_re5600_template"
    [hills_re10595]="$DIR/hills_re10595_template"
    [sphere]="$DIR/sphere_sst"
    [sphere_re100]="$DIR/sphere_re100_template"
    [sphere_re300]="$DIR/sphere_re300_template"
    [sphere_re500]="$DIR/sphere_re500_template"
)
declare -A CASE_HARDCAP=(
    [cylinder]=$HARDCAP_cylinder
    [cylinder_re40]=$HARDCAP_cylinder
    [cylinder_re200]=$HARDCAP_cylinder
    [cylinder_re300]=$HARDCAP_cylinder
    [cylinder_re500]=$HARDCAP_cylinder
    [duct]=$HARDCAP_duct
    [duct_re2500]=${HARDCAP_duct_re2500:-$HARDCAP_duct}
    [duct_re4400]=${HARDCAP_duct_re4400:-$HARDCAP_duct}
    [duct_re6400]=${HARDCAP_duct_re6400:-$HARDCAP_duct}
    [hills]=$HARDCAP_hills
    [hills_re2800]=${HARDCAP_hills_re2800:-$HARDCAP_hills}
    [hills_re5600]=${HARDCAP_hills_re5600:-$HARDCAP_hills}
    [hills_re10595]=${HARDCAP_hills_re10595:-$HARDCAP_hills}
    [sphere]=$HARDCAP_sphere
    [sphere_re100]=$HARDCAP_sphere
    [sphere_re300]=$HARDCAP_sphere
    [sphere_re500]=$HARDCAP_sphere
)
declare -A CASE_TIMEOUT=(
    [cylinder]=$TIMEOUT_cylinder
    [cylinder_re40]=$TIMEOUT_cylinder
    [cylinder_re200]=$TIMEOUT_cylinder
    [cylinder_re300]=$TIMEOUT_cylinder
    [cylinder_re500]=$TIMEOUT_cylinder
    [duct]=$TIMEOUT_duct
    [duct_re2500]=$TIMEOUT_duct_re2500
    [duct_re4400]=${TIMEOUT_duct_re4400:-$TIMEOUT_duct}
    [duct_re6400]=${TIMEOUT_duct_re6400:-$TIMEOUT_duct}
    [hills]=$TIMEOUT_hills
    [hills_re2800]=${TIMEOUT_hills_re2800:-$TIMEOUT_hills}
    [hills_re5600]=${TIMEOUT_hills_re5600:-$TIMEOUT_hills}
    [hills_re10595]=$TIMEOUT_hills_re10595
    [sphere]=$TIMEOUT_sphere
    [sphere_re100]=$TIMEOUT_sphere
    [sphere_re300]=$TIMEOUT_sphere
    [sphere_re500]=$TIMEOUT_sphere
)

# Model list — identical to bench_h100_all.sh.
declare -a MODELS=(
    "fusedKOmegaSST|simulationType RAS; RAS { RASModel fusedKOmegaSST; turbulence on; }"
    "fusedKOmega|simulationType RAS; RAS { RASModel fusedKOmega; turbulence on; }"
    "fusedKOmegaMenter|simulationType RAS; RAS { RASModel fusedKOmegaMenter; turbulence on; }"
    "fusedMixingLength|simulationType RAS; RAS { RASModel fusedMixingLength; turbulence on; }"
    "fusedEARSMwj|simulationType RAS; RAS { RASModel fusedEARSMwj; turbulence on; }"
    "fusedEARSMhellsten|simulationType RAS; RAS { RASModel fusedEARSMhellsten; turbulence on; }"
    "fusedEARSMgs|simulationType RAS; RAS { RASModel fusedEARSMgs; turbulence on; }"
    "fusedRSM|simulationType RAS; RAS { RASModel fusedRSM; turbulence on; }"
    "fusedGEP|simulationType RAS; RAS { RASModel fusedGEP; turbulence on; }"
    "nnMLP-small|simulationType RAS; RAS { RASModel nnMLP; turbulence on; nnMLPCoeffs { weightsDir \"constant/nn_weights/mlp_paper\"; nutMax 1.0; } }"
    "nnMLP-med|simulationType RAS; RAS { RASModel nnMLP; turbulence on; nnMLPCoeffs { weightsDir \"constant/nn_weights/mlp_med_paper\"; nutMax 1.0; } }"
    "nnMLP-large|simulationType RAS; RAS { RASModel nnMLP; turbulence on; nnMLPCoeffs { weightsDir \"constant/nn_weights/mlp_large_paper\"; nutMax 1.0; } }"
    "nnTBNN-small|simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/tbnn_small_paper\"; nutMax 1.0; } }"
    "nnTBNN-med|simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/tbnn_paper\"; nutMax 1.0; } }"
    "nnTBNN-large|simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/tbnn_large_paper\"; nutMax 1.0; } }"
    "nnPITBNN-small|simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/pi_tbnn_small_paper\"; nutMax 1.0; } }"
    "nnPITBNN-med|simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/pi_tbnn_paper\"; nutMax 1.0; } }"
    "nnPITBNN-large|simulationType RAS; RAS { RASModel nnTBNN; turbulence on; nnTBNNCoeffs { weightsDir \"constant/nn_weights/pi_tbnn_large_paper\"; nutMax 1.0; } }"
    "nnTBRF-1t|simulationType RAS; RAS { RASModel nnTBRF; turbulence on; nnTBRFCoeffs { weightsDir \"constant/nn_weights/tbrf_1t_paper\"; nutMax 1.0; } }"
    "nnTBRF-5t|simulationType RAS; RAS { RASModel nnTBRF; turbulence on; nnTBRFCoeffs { weightsDir \"constant/nn_weights/tbrf_5t_paper\"; nutMax 1.0; } }"
    "nnTBRF-10t|simulationType RAS; RAS { RASModel nnTBRF; turbulence on; nnTBRFCoeffs { weightsDir \"constant/nn_weights/tbrf_10t_paper\"; nutMax 1.0; } }"
)

# Per-case function-object block (forces + QoI sampling).
# cylinder/sphere: forceCoeffs on the body patch.
# hills: wallShearStress on bottom wall + surface export for Cf(x) → reattachment.
# duct: centerline U probe at (pi, 0, 0).
functions_block() {
    local case_name=$1
    local hardcap=$2
    case "$case_name" in
        cylinder*|sphere*)
            local patches="" Aref="" lRef=""
            case "$case_name" in
                # 2D cylinder D=1, span L_z=0.1 → frontal area = D*L_z = 0.1
                cylinder*) patches="(cylinder)"; Aref="0.1";       lRef="1.0" ;;
                # Sphere D=1 (radius 0.5) → frontal area = pi*(D/2)^2 = 0.7853981633974
                sphere*)   patches="(sphere)";   Aref="0.7853982"; lRef="1.0" ;;
            esac
            cat << FEOF
functions
{
    forces
    {
        type              forceCoeffs;
        libs              ("libforces.so");
        writeControl      timeStep;
        writeInterval     50;
        log               yes;
        patches           $patches;
        rho               rhoInf;
        rhoInf            1.0;
        CofR              (0 0 0);
        liftDir           (0 1 0);
        dragDir           (1 0 0);
        pitchAxis         (0 0 1);
        magUInf           1.0;
        lRef              $lRef;
        Aref              $Aref;
    }
}
FEOF
            ;;
        hills*)
            # Write wallShearStress on the hills (bottom) wall patch and export
            # as a raw surface file so extract_qoi.py can find the Cf zero crossing.
            # Also probe bulk-flow U at (L/2, mid-height, W/2) for convergence monitoring.
            # Hills domain: x=[0,0.252m], y=[0.028m(crest),0.085m(top)], z=[0,0.126m]
            cat << HEOF
functions
{
    wss
    {
        type            wallShearStress;
        libs            (fieldFunctionObjects);
        writeControl    timeStep;
        writeInterval   $hardcap;
        log             no;
        patches         (hills);
    }
    hillsCf
    {
        type            surfaces;
        libs            (sampling);
        writeControl    timeStep;
        writeInterval   $hardcap;
        surfaceFormat   raw;
        fields          (wallShearStress);
        surfaces
        {
            hills_wall
            {
                type        patch;
                patches     (hills);
                triangulate false;
            }
        }
    }
    centerlineProbe
    {
        type            probes;
        libs            (sampling);
        writeControl    timeStep;
        writeInterval   100;
        probeLocations  ((0.126 0.060 0.063));
        fields          (U);
    }
}
HEOF
            ;;
        duct*)
            # Probe centerline U at domain midpoint (x=pi, y=0, z=0).
            # mean(Ux) = Ub by continuity; probe gives U_cl for U_cl/Ub ratio.
            cat << DEOF
functions
{
    centerlineProbe
    {
        type            probes;
        libs            (sampling);
        writeControl    timeStep;
        writeInterval   100;
        probeLocations  ((3.14159 0 0));
        fields          (U);
    }
}
DEOF
            ;;
        *)  echo "" ;;
    esac
}

run_one() {
    local case_name=$1
    local template=$2
    local model_name=$3
    local turb_block=$4
    local hardcap=$5
    local case_timeout=${6:-${CASE_TIMEOUT[$case_name]:-7200}}

    # Skip if already recorded in CSV (resume support).
    if grep -q "^${case_name},${model_name}," "$CSV" 2>/dev/null; then
        echo "SKIP (done): $case_name $model_name"
        return
    fi

    local work="$WORKROOT/${case_name}__${model_name}"
    rm -rf "$work"
    cp -r "$template" "$work"
    if [ ! -d "$work/constant/nn_weights" ] && [ -d "$DIR/cylinder_nn_template/constant/nn_weights" ]; then
        ln -s "$DIR/cylinder_nn_template/constant/nn_weights" "$work/constant/nn_weights"
    fi
    cd "$work"
    rm -rf [1-9]* postProcessing log
    # Duct and hills both use cyclic streamwise BCs and need meanVelocityForce
    # to maintain Ubar=1.  selectionMode all avoids needing topoSet/cellZone.
    # All other cases: clear fvOptions.
    if [[ "$case_name" == "hills"* || "$case_name" == "duct"* ]]; then
        cat > system/fvOptions << 'FVEOF'
FoamFile { version 2.0; format ascii; class dictionary; object fvOptions; }
momentumSource
{
    type            meanVelocityForce;
    selectionMode   all;
    fields          (U);
    Ubar            (1 0 0);
}
FVEOF
    else
        [ -f system/fvOptions ] && echo 'FoamFile { version 2.0; format ascii; class dictionary; object fvOptions; }' > system/fvOptions
    fi

    cat > constant/turbulenceProperties << EOF
FoamFile { version 2.0; format ascii; class dictionary; object turbulenceProperties; }
$turb_block
EOF

    # fusedRSM needs 0/R and 0/epsilon with patch-aware BCs (reused from bench).
    if [[ "$model_name" == "fusedRSM" ]]; then
        gen_R_eps_bcs "$work"
    fi

    local fblock
    fblock=$(functions_block "$case_name" "$hardcap")
    # Duct and hills both need libfvOptions.so to register meanVelocityForce.
    local extra_libs=""
    [[ "$case_name" == "hills"* || "$case_name" == "duct"* ]] && extra_libs=' "libfvOptions.so"'
    cat > system/controlDict << CDEOF
FoamFile { version 2.0; format ascii; class dictionary; object controlDict; }
libs ("libnnTurbulenceModels.so"${extra_libs});
application simpleFoam;
startFrom startTime; startTime 0; stopAt endTime; endTime $hardcap; deltaT 1;
writeControl timeStep; writeInterval $hardcap; purgeWrite 1;
writeFormat ascii; writePrecision 8; writeCompression off;
timeFormat general; timePrecision 6; runTimeModifiable false;
$fblock
CDEOF

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

    # All cases use residualControl p/U 1e-5 for early exit when achievable.
    # Cylinder Re=100 (vortex shedding) will simply run to hardcap since RANS
    # won't produce a sustained residual < 1e-5 in the oscillating wake.
    # Hills uses nNonOrthogonalCorrectors 1 because snappyHexMesh produces
    # moderate non-orthogonality (max ~55°) on the body-fitted surface cells.
    # relTol 0.05 on GAMG (reduce 20× per step) is faster than 0.01 (100×) and
    # sufficient because SIMPLE outer convergence controls accuracy, not the
    # inner GAMG tolerance.
    local nonorth=0
    [[ "$case_name" == "hills"* ]] && nonorth=1
    # pRefCell is required for cases without any Dirichlet pressure BC
    # (duct, hills — streamwise cyclic). Harmless when a Dirichlet BC already
    # pins p (cylinder inlet, sphere inlet), so set it unconditionally.
    local pRef="pRefCell 0; pRefValue 0;"
    cat > system/fvSolution << FVEOF
FoamFile { version 2.0; format ascii; class dictionary; object fvSolution; }
solvers
{
    p { solver GAMG; smoother twoStageGaussSeidel; tolerance 1e-07; relTol 0.05; maxIter 50; }
    "(U|k|omega|epsilon|R)" { solver smoothSolver; smoother twoStageSymGaussSeidel; tolerance 1e-07; relTol 0.05; }
}
SIMPLE {
    nNonOrthogonalCorrectors $nonorth;
    consistent yes;
    $pRef
    residualControl { p 1e-5; U 1e-5; k 1e-5; omega 1e-5; epsilon 1e-5; R 1e-5; }
}
relaxationFactors { equations { U 0.7; k 0.7; omega 0.7; epsilon 0.7; R 0.7; } fields { p 0.3; } }
FVEOF

    local t0 t1
    t0=$(date +%s)
    timeout "$case_timeout" simpleFoam -pool fixedSizeMemoryPool -poolSize 16 > log 2>&1
    local rc=$?
    t1=$(date +%s)
    local walltime=$((t1 - t0))

    # Parse iterations reached, final residuals, convergence flag
    local iters pres ures converged note
    iters=$(grep -oE '^Time = [0-9]+' log | tail -1 | grep -oE '[0-9]+')
    [ -z "$iters" ] && iters=0
    pres=$(grep -oE 'Solving for p[,:].*Final residual = [0-9.eE+-]+' log | tail -1 | grep -oE 'Final residual = [0-9.eE+-]+' | awk '{print $NF}')
    ures=$(grep -oE 'Solving for Ux[,:].*Final residual = [0-9.eE+-]+' log | tail -1 | grep -oE 'Final residual = [0-9.eE+-]+' | awk '{print $NF}')
    [ -z "$pres" ] && pres=NA
    [ -z "$ures" ] && ures=NA
    converged=0
    grep -q "reached convergence criteria" log && converged=1
    note=""
    grep -qiE "FATAL|nan" log && note="nan_or_fatal"
    [ $rc -eq 124 ] && note="timeout"

    # Extract mean Cd/Cl from forceCoeffs output.
    # Bluff bodies (cylinder, sphere): average over last 20% of iters — no steady
    # state exists, SIMPLE produces a time-averaged approximation.
    # Periodic (duct, hills): Cd/Cl not applicable (NA).
    # Columns: time Cd Cd(f) Cd(r) Cl Cl(f) Cl(r) ...
    local Cd=NA Cl=NA
    local force_file=$(ls postProcessing/forces/*/coefficient.dat 2>/dev/null | head -1)
    if [ -n "$force_file" ]; then
        local avg_n=$(( hardcap / 5 ))   # last 20% of iterations
        read -r Cd Cl <<< "$(grep -vE '^#' "$force_file" | tail -$avg_n | awk '
            {sumCd += $2; sumCl += $5; n++}
            END { if (n > 0) printf "%.6e %.6e", sumCd/n, sumCl/n }')"
        [ -z "$Cd" ] && Cd=NA
        [ -z "$Cl" ] && Cl=NA
    fi

    # Extract mean U_cl (centerline streamwise velocity) from centerlineProbe.
    # Periodic cases (duct, hills): average Ux over last 20% of probe samples.
    # Bluff bodies: NA.
    local U_cl=NA
    local probe_file="postProcessing/centerlineProbe/0/U"
    if [ -f "$probe_file" ]; then
        local avg_n=$(( hardcap / 5 / 100 ))   # probe every 100 iters → /100
        [ "$avg_n" -lt 2 ] && avg_n=2
        U_cl=$(grep -vE '^#|^[[:space:]]*$' "$probe_file" | tail -$avg_n | awk '
            { ux = $2; gsub(/[()]/,"",ux); sumUx += ux; n++ }
            END { if (n > 0) printf "%.6e", sumUx/n }')
        [ -z "$U_cl" ] && U_cl=NA
    fi

    printf "%-9s %-22s rc=%-3d iters=%-5s walltime=%-5ss p_res=%-10s U_res=%-10s Cd=%-10s Cl=%-10s U_cl=%-10s conv=%s %s\n" \
        "$case_name" "$model_name" "$rc" "$iters" "$walltime" "$pres" "$ures" "$Cd" "$Cl" "$U_cl" "$converged" "$note"
    echo "$case_name,$model_name,$rc,$iters,$walltime,$pres,$ures,$Cd,$Cl,$U_cl,$converged,$note" >> "$CSV"
    cd "$DIR"
}

# Generate R and epsilon initial fields with patch-aware BCs (for fusedRSM).
gen_R_eps_bcs() {
    local work=$1
    (cd "$work"
    local bc_block eps_block
    bc_block=$(awk '
        /^[[:space:]]*\{/ { if (prev_word != "") name = prev_word; next }
        /^[[:space:]]*\}/ { name = ""; next }
        /type[[:space:]]+[a-zA-Z]+;/ {
            if (name != "" && !printed[name]) {
                t = $0; sub(/.*type[[:space:]]+/, "", t); sub(/;.*/, "", t);
                gsub(/[[:space:]]/, "", t);
                if (t == "cyclic")          bc[name]="type cyclic;";
                else if (t == "empty")      bc[name]="type empty;";
                else if (t == "symmetry"||t=="symmetryPlane") bc[name]="type symmetry;";
                else if (t == "wall")       bc[name]="type kqRWallFunction; value uniform (0 0 0 0 0 0);";
                else                         bc[name]="type zeroGradient;";
                order[++n]=name; printed[name]=1;
            }
        }
        /^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*$/ { prev_word = $1 }
        END { for (i=1;i<=n;i++) printf "    %s { %s }\n", order[i], bc[order[i]]; }
    ' constant/polyMesh/boundary)
    cat > 0/R << REOF
FoamFile { version 2.0; format ascii; class volSymmTensorField; object R; }
dimensions      [0 2 -2 0 0 0 0];
internalField   uniform (0.001 0 0 0.001 0 0.001);
boundaryField
{
$bc_block
}
REOF
    eps_block=$(awk '
        /^[[:space:]]*\{/ { if (prev_word != "") name = prev_word; next }
        /^[[:space:]]*\}/ { name = ""; next }
        /type[[:space:]]+[a-zA-Z]+;/ {
            if (name != "" && !printed[name]) {
                t = $0; sub(/.*type[[:space:]]+/, "", t); sub(/;.*/, "", t);
                gsub(/[[:space:]]/, "", t);
                if (t == "cyclic")          bc[name]="type cyclic;";
                else if (t == "empty")      bc[name]="type empty;";
                else if (t == "symmetry"||t=="symmetryPlane") bc[name]="type symmetry;";
                else if (t == "wall")       bc[name]="type epsilonWallFunction; value uniform 0.01;";
                else                         bc[name]="type zeroGradient;";
                order[++n]=name; printed[name]=1;
            }
        }
        /^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*$/ { prev_word = $1 }
        END { for (i=1;i<=n;i++) printf "    %s { %s }\n", order[i], bc[order[i]]; }
    ' constant/polyMesh/boundary)
    cat > 0/epsilon << EEOF
FoamFile { version 2.0; format ascii; class volScalarField; object epsilon; }
dimensions      [0 2 -3 0 0 0 0];
internalField   uniform 0.01;
boundaryField
{
$eps_block
}
EEOF
    )
}

# ---- Entry point ---------------------------------------------------------
CASES="${CASES:-cylinder duct duct_re2500 hills hills_re10595 sphere}"

# Single-run mode: MODEL and CASE set → run one and exit.
if [ -n "${MODEL:-}" ] && [ -n "${CASE:-}" ]; then
    template=${CASE_TEMPLATE[$CASE]:-}
    hardcap=${CASE_HARDCAP[$CASE]:-10000}
    if [ -z "$template" ] || [ ! -d "$template" ]; then
        echo "SKIP $CASE: no template"; exit 1
    fi
    for entry in "${MODELS[@]}"; do
        IFS='|' read -r mname mblock <<< "$entry"
        if [ "$mname" = "$MODEL" ]; then
            run_one "$CASE" "$template" "$mname" "$mblock" "$hardcap"
            exit 0
        fi
    done
    echo "SKIP: MODEL=$MODEL not found"; exit 1
fi

echo "=== sweep_h100_accuracy — $(date) ==="
echo "host: $(hostname)"
echo "GPU:  $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)"
echo "cases: $CASES"

for case_name in $CASES; do
    template=${CASE_TEMPLATE[$case_name]:-}
    hardcap=${CASE_HARDCAP[$case_name]:-10000}
    [ -z "$template" ] || [ ! -d "$template" ] && { echo "SKIP $case_name"; continue; }
    echo "--- case: $case_name (hardcap=$hardcap) ---"
    for entry in "${MODELS[@]}"; do
        IFS='|' read -r mname mblock <<< "$entry"
        run_one "$case_name" "$template" "$mname" "$mblock" "$hardcap"
    done
done

echo "=== Done.  CSV: $CSV ==="
