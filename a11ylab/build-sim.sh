#!/bin/bash
# Lab only (a11y-lab-nowplaying). Both lab apps (change and control) built
# for the simulator with whichever Xcode is selected, into apps/<build>/.
# $1 names the logs; $2 is the -destination.
set -uo pipefail
TAG="$1"
DEST="$2"
mkdir -p out apps
for B in change control; do
  LOG="out/compile-$TAG-lab-$B-simulator.log"
  (
    cd "trees/lab-$B" && xcodegen generate > /dev/null && \
    xcodebuild build \
      -project Ammy.xcodeproj \
      -scheme Ammy \
      -configuration Release \
      -destination "$DEST" \
      -derivedDataPath build-sim \
      MARKETING_VERSION=1.0 \
      CURRENT_PROJECT_VERSION=158 \
      CODE_SIGNING_ALLOWED=NO
  ) > "$LOG" 2>&1
  STATUS=$?
  {
    echo "== lab-$B for the simulator, $(xcodebuild -version | tr '\n' ' '), iphonesimulator SDK $(xcrun --sdk iphonesimulator --show-sdk-version): exit $STATUS"
    grep -E "error:|warning:|\*\* BUILD" "$LOG" | sort -u | head -80
    P="trees/lab-$B/build-sim/Build/Products/Release-iphonesimulator/Ammy.app"
    if [ -d "$P" ]; then
      rm -rf "apps/$B"
      mkdir -p "apps/$B"
      cp -R "$P" "apps/$B/"
      plutil -p "$P/Info.plist" | grep -E "DTSDKName|DTXcode|DTPlatformVersion|MinimumOSVersion|CFBundleVersion"
      lipo -info "$P/Ammy"
    fi
  } | tee -a "out/compile-$TAG-summary.txt"
done
