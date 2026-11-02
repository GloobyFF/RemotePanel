#!/bin/bash
# Package the last signed builds as .ipa files (Payload/<App>.app zipped).
# Run on the build Mac after build_install.sh / ZhangJieStocks/build_install.sh.
# Output: ~/ipa-out/<App>-<version>-b<build>.ipa, with the signature checked.
set -euo pipefail
OUT="${RP_IPA_OUT:-$HOME/ipa-out}"
mkdir -p "$OUT"

pack() {
  local name="$1" app="$2"
  if [ ! -d "$app" ]; then echo "APP_MISSING $app"; return 1; fi
  codesign --verify --deep --strict "$app"
  local ver build stage ipa
  ver=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Info.plist")
  build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Info.plist")
  stage=$(mktemp -d /tmp/ipa-stage.XXXXXX)
  mkdir -p "$stage/Payload"
  ditto "$app" "$stage/Payload/$name.app"
  ipa="$OUT/$name-$ver-b$build.ipa"
  rm -f "$ipa"
  (cd "$stage" && zip -qry -X "$ipa" Payload)
  rm -rf "$stage"
  # Re-open the ipa and check the copy is still validly signed.
  local check
  check=$(mktemp -d /tmp/ipa-check.XXXXXX)
  unzip -q "$ipa" -d "$check"
  codesign --verify --deep --strict "$check/Payload/$name.app"
  local profile
  profile=$(security cms -D -i "$check/Payload/$name.app/embedded.mobileprovision" 2>/dev/null | plutil -extract Name xml1 -o - - 2>/dev/null | sed -n 's/.*<string>\(.*\)<\/string>.*/\1/p')
  rm -rf "$check"
  echo "IPA $ipa  $(stat -f %z "$ipa") bytes  version $ver ($build)  profile: ${profile:-?}"
}

pack RemotePanel "$HOME/Developer/RemotePanel/DerivedData/Build/Products/Debug-iphoneos/RemotePanel.app"
pack ZhangJieStocks "$HOME/Developer/ZhangJieStocks/DerivedData/Build/Products/Debug-iphoneos/ZhangJieStocks.app"
echo IPA_OK
