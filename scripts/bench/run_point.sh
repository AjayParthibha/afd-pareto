#!/bin/bash
# Launch a config, run its points, stop.  SYSTEM=afd A=2 F=2 SHAPES=short CONCS=32 bash scripts/bench/run_point.sh
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
SYSTEM=${SYSTEM:?afd or colocated}
SHAPES=${SHAPES:-short}; CONCS=${CONCS:-32}
export LOG_DIR=${LOG_DIR:-$PWD/logs}

if [ "$SYSTEM" = afd ]; then
  export A=${A:-1} F=${F:-1}
  NGPU=$((A + F))
  CONFIG=${CONFIG:-afd-${A}a${F}f$([ "${DBO:-0}" = 1 ] && echo -dbo)}
  launch=$here/../launch/afd.sh
else
  export N=${N:-4} TP=${TP:-1}
  NGPU=$N
  dp=$((N / TP)); CONFIG=${CONFIG:-colo-dp${dp}$([ "$TP" -gt 1 ] && echo "tp$TP")}
  launch=$here/../launch/colocated.sh
fi
export CONFIG NGPU
mkdir -p "$LOG_DIR/$CONFIG"; export LOG_DIR=$LOG_DIR/$CONFIG

bash "$here/../launch/stop.sh" >/dev/null 2>&1
if ! bash "$launch"; then
  tail -30 "$LOG_DIR"/*.log; bash "$here/../launch/stop.sh"; echo "POINT FAILED $CONFIG (launch)"; exit 1
fi
if [ -z "${POINTS:-}" ]; then
  POINTS=$(for s in $SHAPES; do for c in $CONCS; do echo -n "$s:$c "; done; done)
fi
rc=0
for p in $POINTS; do
  s=${p%%:*}; c=${p##*:}
  SHAPE=$s CONC=$c bash "$here/bench.sh" || { rc=1; echo "POINT FAILED $CONFIG $s c$c"; }
done
bash "$here/../launch/stop.sh"
echo "POINTS DONE $CONFIG rc=$rc"
exit $rc
