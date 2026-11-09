#!/bin/zsh
# Fails if the built app carries anything a Daily Command user must never see: the clone-host
# software's vendor name, operator-console terms, or ExecClone staff/clone names. Daily Command is
# a planner by ExecClone; it talks only to ExecClone's client API.
# Usage: scripts/brand-check.sh <path to .app>
set -euo pipefail
APP=${1:?usage: brand-check.sh <App.app>}
V="openc""law"
TERMS="${V}|clawd|advanced mode|clone host|gatewaywire|node[.]invoke|chat[.]send|sessions[.](patch|list)|connect[.]challenge|device[.]pair|\bJ4\b"
bad=0
while IFS= read -r f; do echo "forbidden file name: ${f#$APP/}"; bad=1; done < <(find "$APP" -iname "*${V}*")
while IFS= read -r f; do
  while IFS= read -r tok; do
    echo "forbidden: '$tok' in ${f#$APP/}"; bad=1
  done < <(strings -a "$f" 2>/dev/null | grep -oiE "[A-Za-z0-9._()/:-]*(${TERMS})[A-Za-z0-9._()/:-]*" | sort -u)
done < <(find "$APP" -type f)
exit $bad
