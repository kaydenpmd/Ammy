#!/bin/bash
# Lab only (keepalive-lab). Runs each scenario against the installed lab build
# of Ammy in a booted simulator, from outside the app:
#   bash lab/run-scenarios.sh UDID OUT [scenario ...]
# Per scenario, OUT/<name>/ gets marks.txt (what this script did, when),
# probe.txt (the app's own line a second; a gap is time it wasn't running),
# pids.txt (launchctl's pid every 5 s), and the app's keepalive journal.
# Pushes land in OUT/pushes.jsonl, written by lab/receiver.py.
set -u
UDID="$1"; OUT="$2"; shift 2
EP="https://localhost:8443/now-playing"
APP=com.local.ammy
now() { python3 -c 'import time; print("%.3f" % time.time())'; }
mark() { echo "$(now) $2" >> "$1/marks.txt"; echo "$(date +%T) [$(basename "$1")] $2"; }
pid_now() { xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep -F "$APP" | awk '{print $1}' | head -1; }
watch_for() {   # dir, seconds: the pid every 5 s
  local dir="$1" end=$(( $(date +%s) + $2 ))
  while [ "$(date +%s)" -lt "$end" ]; do
    echo "$(now) $(pid_now)" >> "$dir/pids.txt"
    sleep 5
  done
}
launch() {      # dir, then launch arguments
  local dir="$1"; shift
  xcrun simctl launch "$UDID" "$APP" -labOut "$dir" -relay_endpoint "$EP" -relay_key lab "$@" >> "$dir/launch.txt" 2>&1
}
journal() {     # dir, tag
  local c; c=$(xcrun simctl get_app_container "$UDID" "$APP" data 2>/dev/null) || return
  cp "$c/Library/Application Support/keepalive.log" "$1/journal-$2.log" 2>/dev/null
  cp "$c/Library/Application Support/keepalive.alive" "$1/alive-$2.txt" 2>/dev/null
  cp "$c/Documents/probe.txt" "$1/probe-documents.txt" 2>/dev/null
}
# name, seconds in the background, then "front S" or "kill S", then launch arguments
run() {
  local name="$1" bg="$2" how="$3" after="$4"; shift 4
  local dir="$OUT/$name"; rm -rf "$dir"; mkdir -p "$dir"
  xcrun simctl terminate "$UDID" "$APP" > /dev/null 2>&1; sleep 2
  mark "$dir" "launch $*"
  launch "$dir" "$@"
  watch_for "$dir" 20                     # autostart, first pushes
  mark "$dir" "background"
  xcrun simctl launch "$UDID" com.apple.Preferences >> "$dir/launch.txt" 2>&1
  watch_for "$dir" "$bg"
  if [ "$how" = kill ]; then
    journal "$dir" before-kill
    mark "$dir" "terminate (suspended)"
    xcrun simctl terminate "$UDID" "$APP" >> "$dir/launch.txt" 2>&1
    sleep 3
    mark "$dir" "relaunch"
    launch "$dir"
  else
    mark "$dir" "foreground"
    launch "$dir"                         # already running: brought to the front
  fi
  watch_for "$dir" "$after"
  journal "$dir" end
  mark "$dir" "end"
}
[ $# -gt 0 ] || set -- A C-hold C-nohold D-hold F-hold E-hold
for s in "$@"; do
  case "$s" in
    A)       run A-control 150 front 30 ;;
    C-hold)  run C-hold   120 front 40 -labStopAt 30 -labFailStage engine.start -labFailFor 15 ;;
    C-nohold) run C-nohold 120 front 40 -labStopAt 30 -labFailStage engine.start -labFailFor 15 -labNoHold YES ;;
    D-hold)  run D-hold   250 front 50 -labStopAt 30 -labFailStage engine.start -labFailFor 200 ;;
    F-hold)  run F-hold   120 kill  45 -labStopAt 30 -labFailStage engine.start -labFailFor 200 ;;
    E-hold)  run E-hold   100 front 30 -labStopAt 30 -labFailStage setActive -labFailFor 8 -labEndAt 10 ;;
    # The engine never runs in these processes (LabFaults, -labFailFromLaunch),
    # so the simulator's audio HAL holds no assertion and only the hold can
    # keep a backgrounded Ammy running.
    G-hold)   run G-hold   120 front 30 -labFailFromLaunch YES -labFailStage engine.start -labFailFor 35 ;;
    G-nohold) run G-nohold 120 front 30 -labFailFromLaunch YES -labFailStage engine.start -labFailFor 35 -labNoHold YES ;;
    H-hold)   run H-hold   190 front 40 -labFailFromLaunch YES -labFailStage engine.start -labFailFor 170 ;;
    H-nohold) run H-nohold 190 front 40 -labFailFromLaunch YES -labFailStage engine.start -labFailFor 170 -labNoHold YES ;;
    I-hold)   run I-hold    90 kill  45 -labFailFromLaunch YES -labFailStage engine.start -labFailFor 600 ;;
    *) echo "unknown scenario $s" ;;
  esac
done
xcrun simctl terminate "$UDID" "$APP" > /dev/null 2>&1
exit 0
