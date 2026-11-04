#!/bin/bash
# Lab only (a11y-lab-nowplaying). The change and the control built for the
# device exactly as build-ipa.yml builds a release (Release, iphoneos,
# unsigned), with whichever Xcode is selected. $1 names the logs.
set -uo pipefail
TAG="$1"
mkdir -p out
for B in change control; do
  LOG="out/compile-$TAG-pure-$B-device.log"
  (
    cd "trees/pure-$B" && xcodegen generate > /dev/null && \
    xcodebuild \
      -project Ammy.xcodeproj \
      -scheme Ammy \
      -configuration Release \
      -sdk iphoneos \
      -derivedDataPath build \
      MARKETING_VERSION=1.0 \
      CURRENT_PROJECT_VERSION=158 \
      CODE_SIGN_IDENTITY="" \
      CODE_SIGNING_REQUIRED=NO \
      CODE_SIGNING_ALLOWED=NO \
      ONLY_ACTIVE_ARCH=NO
  ) > "$LOG" 2>&1
  STATUS=$?
  {
    echo "== pure-$B for the device, $(xcodebuild -version | tr '\n' ' '), iphoneos SDK $(xcrun --sdk iphoneos --show-sdk-version): exit $STATUS"
    grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)|\*\* BUILD" "$LOG" | sort -u | head -80
    P="trees/pure-$B/build/Build/Products/Release-iphoneos/Ammy.app"
    if [ -d "$P" ]; then
      plutil -p "$P/Info.plist" | grep -E "DTSDKName|DTXcode|DTPlatformVersion|MinimumOSVersion|CFBundleVersion"
      lipo -info "$P/Ammy"
      shasum -a 256 "$P/Ammy"
    fi
  } | tee -a "out/compile-$TAG-summary.txt"
done
