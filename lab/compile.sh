#!/bin/bash
# Lab only (keepalive-lab). Builds with whichever Xcode is selected:
#   pure  the checkout itself, i.e. the fix exactly as the working tree had it
#         and no lab code, for the device as build-ipa.yml builds a release and
#         for the simulator as it builds the Appetize copy
#   lab   trees/lab (lab/make-lab-tree.py), for the simulator, into apps/lab
# $1 names the logs; $2 is "lab" to build the lab app as well.
set -uo pipefail
TAG="$1"; WANT_LAB="${2:-}"
mkdir -p out apps
S="out/compile-$TAG-summary.txt"
{
  echo "== $TAG: $(xcodebuild -version | tr '\n' ' ') at $(xcode-select -p)"
  echo "iphoneos SDK $(xcrun --sdk iphoneos --show-sdk-version), iphonesimulator SDK $(xcrun --sdk iphonesimulator --show-sdk-version)"
  echo "the three changed files, as built:"
  shasum -a 256 Ammy/KeepAlive.swift Ammy/KeepAliveJournal.swift Ammy/Diagnostics.swift
} | tee -a "$S"

build() {   # name, sdk, derived data, project dir
  local LOG="out/compile-$TAG-$1.log"
  (
    cd "$4" || exit 1
    [ -d Ammy.xcodeproj ] || xcodegen generate > /dev/null || exit 1
    xcodebuild -project Ammy.xcodeproj -scheme Ammy -configuration Release -sdk "$2" \
      -derivedDataPath "$3" MARKETING_VERSION=1.0 CURRENT_PROJECT_VERSION=999 \
      CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO
  ) > "$LOG" 2>&1
  local STATUS=$?
  {
    echo "-- $1 ($2): exit $STATUS, $(grep -E '\*\* BUILD (SUCCEEDED|FAILED)' "$LOG" | tail -1)"
    echo "   errors: $(grep -c 'error:' "$LOG")"
    echo "   distinct warnings, all files: $(grep -E 'warning:' "$LOG" | sort -u | wc -l | tr -d ' ')"
    echo "   warnings and errors in KeepAlive.swift, KeepAliveJournal.swift, Diagnostics.swift (and LabFaults.swift):"
    grep -E '(KeepAlive|KeepAliveJournal|Diagnostics|LabFaults)\.swift:[0-9]+:[0-9]+: (warning|error):' "$LOG" | sed 's|.*/Ammy/||' | sort -u | sed 's/^/     /'
    grep -E 'warning:|error:' "$LOG" | sed 's|.*/Ammy/||' | sort -u | head -40 | sed 's/^/   all| /'
    local P
    P=$(ls -d "$4/$3"/Build/Products/Release-*/Ammy.app 2>/dev/null | head -1)
    if [ -n "$P" ]; then
      plutil -p "$P/Info.plist" | grep -E "DTSDKName|DTXcode|DTPlatformVersion|MinimumOSVersion"
      lipo -info "$P/Ammy"
    fi
  } | tee -a "$S"
}

if [ "$WANT_LAB" = lab ]; then
  # First, so the copy is of the checkout before anything is built in it.
  python3 -I lab/make-lab-tree.py | tee -a "$S"
fi
build pure-device iphoneos build .
build pure-simulator iphonesimulator build-sim .
if [ "$WANT_LAB" = lab ]; then
  build lab-simulator iphonesimulator build-sim trees/lab
  rm -rf apps/lab
  mkdir -p apps/lab
  cp -R trees/lab/build-sim/Build/Products/Release-iphonesimulator/Ammy.app apps/lab/ || echo "no lab app" | tee -a "$S"
fi
exit 0
