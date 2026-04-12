#!/bin/bash
# Re-extract bench results from existing bench_h100_runs/<case>__<model>/log files
# and append to bench_h100_results.csv.
DIR="$(cd "$(dirname "$0")" && pwd)"
WORKROOT="$DIR/bench_h100_runs"
CSV="$DIR/bench_h100_results.csv"

if [ ! -s "$CSV" ]; then
    echo "case,model,exit,total_ms,turb_ms,p_ms,U_ms,niters,note" > "$CSV"
fi

for d in "$WORKROOT"/*/; do
    base=$(basename "$d")
    case_name=${base%%__*}
    model_name=${base#*__}
    log="$d/log"
    [ -f "$log" ] || continue

    parse() { awk -v key="$1" '
        /FINAL Profiling/ {flag=1; next}
        flag && index($0,key) {
            for (i=1; i<=NF; i++) {
                if ($i ~ /^[0-9.eE+-]+$/) { print $i; exit }
            }
        }' "$log"; }

    TOT=$(parse "TOTAL:");      [ -z "$TOT" ] && TOT=NA
    TURB=$(parse "turb correct:"); [ -z "$TURB" ] && TURB=NA
    P=$(parse "p solve:");      [ -z "$P" ] && P=NA
    U=$(parse "U solve:");      [ -z "$U" ] && U=NA
    NITERS=$(grep -oE "FINAL Profiling Summary \([0-9]+ iters\)" "$log" | grep -oE '[0-9]+' | head -1)
    [ -z "$NITERS" ] && NITERS=NA
    NOTE=""
    if [ "$TOT" = "NA" ]; then NOTE="parse_failed"; fi
    if grep -qiE "FATAL" "$log"; then NOTE="nan_or_fatal"; fi

    RC=0
    [ "$TOT" = "NA" ] && RC=1

    # Skip if this row already in CSV
    if grep -q "^${case_name},${model_name}," "$CSV"; then continue; fi

    echo "$case_name,$model_name,$RC,$TOT,$TURB,$P,$U,$NITERS,$NOTE" >> "$CSV"
done

echo "Done. CSV: $CSV"
wc -l "$CSV"
