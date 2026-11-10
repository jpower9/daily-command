#!/bin/zsh
# One-word TestFlight release from a Mac that has Xcode and the team's App Store Connect key
# at ~/.appstoreconnect/private_keys/AuthKey_RWQT9P832G.p8. Usage: scripts/mini-release.sh [build-number]
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f Config/Local.xcconfig ] || : > Config/Local.xcconfig
which xcodegen >/dev/null || brew install xcodegen || { echo "brew install xcodegen failed"; exit 1; }
BUILD=${1:-$(date +%Y%m%d%H%M)}
# Sign from a throwaway build keychain (same as CI). The login keychain stays untouched; over ssh it is
# locked and codesign fails with errSecInternalComponent. Xcode re-creates the signing certificate
# into this keychain via the ASC API key.
KC=$HOME/Library/Keychains/dc-build.keychain-db; KCPW=$(uuidgen)
security delete-keychain "$KC" 2>/dev/null || true
security create-keychain -p "$KCPW" "$KC"
security set-keychain-settings -lut 7200 "$KC"
security unlock-keychain -p "$KCPW" "$KC"
# Only the build keychain is searchable: the login keychain holds an identity whose key is
# unusable over ssh, and Xcode would keep picking it. Restored on exit.
ORIG_KCS=$(security list-keychains -d user | tr -d '" ')
security list-keychains -d user -s "$KC"
security default-keychain -d user -s "$KC"
# Apple's intermediate so the chain validates in the new keychain
curl -fsSL -o /tmp/AppleWWDRCAG3.cer https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer && security import /tmp/AppleWWDRCAG3.cer -k "$KC" -T /usr/bin/codesign >/dev/null 2>&1 || true
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KCPW" "$KC" >/dev/null 2>&1 || true
trap 'security list-keychains -d user -s $ORIG_KCS; security default-keychain -d user -s "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null' EXIT
export ASC_KEY_ID=RWQT9P832G ASC_ISSUER_ID=44012159-23e1-4c9e-86f6-23c38d448cf8
# The build keychain is empty, so any API-made development certificate on file is orphaned; revoke
# it so Xcode (-allowProvisioningUpdates) issues a fresh one into this keychain.
python3 scripts/asc_setup.py --revoke-orphan-dev-certs
exec zsh scripts/release.sh "$BUILD"
