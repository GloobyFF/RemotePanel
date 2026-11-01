#!/bin/bash
# Build ZhangJieStocks and install it on the iPad over USB (Wi-Fi as fallback).
# Run on the build Mac (.179, Xcode 10.1). Same signing setup as ../build_install.sh.
set -euo pipefail
ROOT="${RP_ZJ_ROOT:-/Users/fangzhiling/Developer/ZhangJieStocks}"
# Wildcard team profile (FLFYQXCCZM.*), expires 2027-10-31; includes the iPad 3
# and the pinned certificate below.
PROFILE_UUID="${RP_PROFILE_UUID:-b0f2eb7f-6f8c-40df-8c6a-3a2ec6ca1b39}"
PROFILE="$HOME/Library/MobileDevice/Provisioning Profiles/${PROFILE_UUID}.mobileprovision"
# Two keychain certificates share the name "iPhone Developer: ZhiLing Fang
# (GE75FA37EU)"; pin the one the profiles contain.
IDENTITY="${RP_IDENTITY:-1DF5C6144994B3B6C7932553B9C5D50FF5A72E0A}"
TEAM="FLFYQXCCZM"
UDID="${RP_UDID:-1b9b4d6959e9d533837d946d94105049dfd794a8}"
IOS_DEPLOY="$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/ios-deploy-*/Build/Products/Release/ios-deploy 2>/dev/null | head -1)"
KC="$HOME/Library/Keychains/login.keychain"
if [ ! -f "$KC" ]; then KC="$HOME/Library/Keychains/login.keychain-db"; fi
PASS="${SSHPASS:?Set SSHPASS or unlock keychain manually — ask operator}"
LOG=/tmp/ZhangJieStocks_build.log

[ -x "$IOS_DEPLOY" ] || { echo "ios-deploy not found under DerivedData"; exit 1; }
security unlock-keychain -p "$PASS" "$KC"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASS" "$KC" >/dev/null 2>&1 || true

cd "$ROOT"
rm -rf "$ROOT/DerivedData"
# The wildcard profile is Xcode-managed, which xcodebuild refuses for manual
# signing. Build unsigned, then sign with codesign using the profile's own
# entitlements (application-identifier rewritten to this bundle ID).
set +e
xcodebuild -project ZhangJieStocks.xcodeproj -scheme ZhangJieStocks -configuration Debug \
  -sdk iphoneos -derivedDataPath "$ROOT/DerivedData" \
  ONLY_ACTIVE_ARCH=NO \
  ARCHS="armv7" \
  IPHONEOS_DEPLOYMENT_TARGET=9.3 \
  TARGETED_DEVICE_FAMILY=2 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build 2>&1 | tee "$LOG"
XC=${PIPESTATUS[0]}
set -e
if [ "$XC" -ne 0 ]; then
  echo "BUILD_FAILED exit=$XC"
  grep -E "error:" "$LOG" | tail -20
  exit "$XC"
fi

APP="$ROOT/DerivedData/Build/Products/Debug-iphoneos/ZhangJieStocks.app"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")"
cp -f "$PROFILE" "$APP/embedded.mobileprovision"
ENT="$ROOT/DerivedData/ZhangJieStocks.entitlements"
security cms -D -i "$PROFILE" > "$ROOT/DerivedData/profile.plist"
/usr/libexec/PlistBuddy -x -c 'Print :Entitlements' "$ROOT/DerivedData/profile.plist" > "$ENT"
/usr/libexec/PlistBuddy -c "Set :application-identifier $TEAM.$BUNDLE_ID" "$ENT"
/usr/libexec/PlistBuddy -c "Set :get-task-allow true" "$ENT" 2>/dev/null || true
# keychain-access-groups "TEAM.*" is fine as is; drop anything iCloud/push the app does not use.
for k in aps-environment com.apple.developer.icloud-container-identifiers com.apple.developer.ubiquity-kvstore-identifier com.apple.developer.icloud-services com.apple.developer.ubiquity-container-identifiers com.apple.developer.team-identifier; do
  /usr/libexec/PlistBuddy -c "Delete :$k" "$ENT" >/dev/null 2>&1 || true
done
/usr/bin/codesign --force --sign "$IDENTITY" --entitlements "$ENT" --timestamp=none "$APP"
codesign -dv "$APP" 2>&1 | grep -E "Identifier|TeamIdentifier"

set +e
"$IOS_DEPLOY" --id "$UDID" --bundle "$APP" --no-wifi --nostart --timeout 20
RC=$?
if [ $RC -ne 0 ]; then
  echo "USB install failed (rc=$RC); trying Wi-Fi"
  "$IOS_DEPLOY" --id "$UDID" --bundle "$APP" --nostart --timeout 30
  RC=$?
fi
set -e
if [ $RC -ne 0 ]; then
  echo "INSTALL_FAILED exit=$RC"
  exit $RC
fi
echo "INSTALL_OK"
