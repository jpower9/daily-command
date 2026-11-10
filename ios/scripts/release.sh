#!/bin/zsh
# Archive Daily Command and upload it to App Store Connect / TestFlight.
# Signing uses the team's App Store Connect API key (no Xcode account needed), so this runs the
# same way in CI and in Terminal.
# Usage: scripts/release.sh <build-number>     (higher than every earlier build)
# Env:   ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (.p8); Config/Local.xcconfig must hold the publishable key.
set -euo pipefail
BUILD=${1:?usage: release.sh <build-number>}
KEY_ID=${ASC_KEY_ID:?ASC_KEY_ID is required}
ISSUER=${ASC_ISSUER_ID:?ASC_ISSUER_ID is required}
KEY_PATH=${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_$KEY_ID.p8}
OUT=${TMPDIR:-/tmp}/daily-command-release-$BUILD
cd "$(dirname "$0")/.."
[ -f Config/Local.xcconfig ] || { echo "Config/Local.xcconfig is missing (copy Local.xcconfig.example)"; exit 1; }
grep -q "sb_publishable_" Config/Base.xcconfig Config/Local.xcconfig || { echo "no publishable key in Config"; exit 1; }
[ -f "$KEY_PATH" ] || { echo "App Store Connect key not found at $KEY_PATH"; exit 1; }
mkdir -p "$OUT"
echo "xcodegen $(xcodegen --version 2>&1 | head -1) at $(which xcodegen)"
xcodegen generate > "$OUT/xcodegen.log" 2>&1 || { cat "$OUT/xcodegen.log"; echo "xcodegen failed"; exit 1; }
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$KEY_PATH" -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER")
xcodebuild -project DailyCommand.xcodeproj -scheme DailyCommand -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$OUT/DailyCommand.xcarchive" -derivedDataPath "$OUT/dd" CURRENT_PROJECT_VERSION="$BUILD" archive "${AUTH[@]}" > "$OUT/archive.log" 2>&1 \
  || { set +e; grep -E "error:" "$OUT/archive.log" | head -20; echo "-- archive.log tail:"; tail -40 "$OUT/archive.log"; echo "archive failed (log: $OUT/archive.log)"; exit 1; }
scripts/brand-check.sh "$OUT/DailyCommand.xcarchive/Products/Applications/Daily Command.app" || { echo "brand check failed"; exit 1; }
xcodebuild -exportArchive -archivePath "$OUT/DailyCommand.xcarchive" -exportOptionsPlist Config/ExportOptions.plist -exportPath "$OUT/export" "${AUTH[@]}" > "$OUT/export.log" 2>&1 \
  || { set +e; tail -40 "$OUT/export.log"; echo "export/upload failed (log: $OUT/export.log)"; exit 1; }
echo "Uploaded build $BUILD. It appears in TestFlight after Apple finishes processing (5–20 min)."
