#!/bin/zsh
# One-word TestFlight release from a Mac that has Xcode and the team's App Store Connect key
# at ~/.appstoreconnect/private_keys/AuthKey_RWQT9P832G.p8. Usage: scripts/mini-release.sh [build-number]
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f Config/Local.xcconfig ] || : > Config/Local.xcconfig
which xcodegen >/dev/null || brew install -q xcodegen
BUILD=${1:-$(date +%Y%m%d%H%M)}
ASC_KEY_ID=RWQT9P832G ASC_ISSUER_ID=44012159-23e1-4c9e-86f6-23c38d448cf8 exec zsh scripts/release.sh "$BUILD"
