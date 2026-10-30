#!/bin/bash
set -euo pipefail
ROOT="/Users/fangzhiling/Developer/RemotePanel"
PROFILE_UUID="82daac59-68ad-46f5-bacd-b8033bc9dc0b"
PROFILE="$HOME/Library/MobileDevice/Provisioning Profiles/${PROFILE_UUID}.mobileprovision"
IDENTITY="iPhone Developer: ZhiLing Fang (GE75FA37EU)"
TEAM="FLFYQXCCZM"
UDID="1b9b4d6959e9d533837d946d94105049dfd794a8"
IOS_DEPLOY="$HOME/Library/Developer/Xcode/DerivedData/ios-deploy-caqdlqektaptvpavtvifdgxwbhad/Build/Products/Release/ios-deploy"
KC="$HOME/Library/Keychains/login.keychain"
if [ ! -f "$KC" ]; then KC="$HOME/Library/Keychains/login.keychain-db"; fi
PASS="${SSHPASS:?Set SSHPASS or unlock keychain manually — ask operator}"

security unlock-keychain -p "$PASS" "$KC"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASS" "$KC" >/dev/null 2>&1 || true

cd "$ROOT"
rm -rf "$ROOT/DerivedData"
set +e
xcodebuild -project RemotePanel.xcodeproj -scheme RemotePanel -configuration Debug \
  -sdk iphoneos -derivedDataPath "$ROOT/DerivedData" \
  DEVELOPMENT_TEAM="$TEAM" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  PROVISIONING_PROFILE="$PROFILE_UUID" \
  PROVISIONING_PROFILE_SPECIFIER="RemotePanel Dev" \
  ONLY_ACTIVE_ARCH=NO \
  ARCHS="armv7" \
  IPHONEOS_DEPLOYMENT_TARGET=9.3 \
  TARGETED_DEVICE_FAMILY=2 \
  build 2>&1 | tee /tmp/RemotePanel_build.log
XC=${PIPESTATUS[0]}
set -e

if [ $XC -ne 0 ] && grep -q errSecInternalComponent /tmp/RemotePanel_build.log; then
  echo "RETRY after errSecInternalComponent"
  security unlock-keychain -p "$PASS" "$KC"
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASS" "$KC" >/dev/null 2>&1 || true
  set +e
  xcodebuild -project RemotePanel.xcodeproj -scheme RemotePanel -configuration Debug \
    -sdk iphoneos -derivedDataPath "$ROOT/DerivedData" \
    DEVELOPMENT_TEAM="$TEAM" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    PROVISIONING_PROFILE="$PROFILE_UUID" \
    PROVISIONING_PROFILE_SPECIFIER="RemotePanel Dev" \
    ONLY_ACTIVE_ARCH=NO \
    ARCHS="armv7" \
    IPHONEOS_DEPLOYMENT_TARGET=9.3 \
    TARGETED_DEVICE_FAMILY=2 \
    build 2>&1 | tee /tmp/RemotePanel_build.log
  XC=${PIPESTATUS[0]}
  set -e
fi

if [ $XC -ne 0 ]; then
  echo "BUILD_FAILED exit=$XC"
  tail -100 /tmp/RemotePanel_build.log
  exit $XC
fi

APP="$ROOT/DerivedData/Build/Products/Debug-iphoneos/RemotePanel.app"
XCENT="$ROOT/DerivedData/Build/Intermediates.noindex/RemotePanel.build/Debug-iphoneos/RemotePanel.build/RemotePanel.app.xcent"
cp -f "$PROFILE" "$APP/embedded.mobileprovision"
/usr/bin/codesign --force --sign "$IDENTITY" --entitlements "$XCENT" --timestamp=none "$APP"
codesign -dv "$APP" 2>&1 | head -20

set +e
"$IOS_DEPLOY" --id "$UDID" --bundle "$APP" --no-wifi --timeout 20
RC=$?
if [ $RC -ne 0 ]; then
  echo "USB --no-wifi failed (rc=$RC); falling back to WiFi install"
  "$IOS_DEPLOY" --id "$UDID" --bundle "$APP" --nostart
  RC=$?
fi
set -e
if [ $RC -ne 0 ]; then
  echo "INSTALL_FAILED exit=$RC"
  exit $RC
fi
echo "INSTALL_OK"
