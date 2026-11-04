#!/bin/bash
# Lab only (a11y-lab-nowplaying). Four copies of the app to build:
#   trees/pure-change   5e63c79's Ammy and project.yml with this branch's
#                       Ammy/AmmyApp.swift, which is main's working tree on
#                       4 Nov 2026: the change and nothing else
#   trees/pure-control  5e63c79's Ammy and project.yml, the code build 158
#                       shipped
#   trees/lab-change    this branch's Ammy: the change, plus A11yLab.swift and
#                       its two hooks in NowPlayingMonitor.swift
#   trees/lab-control   the same with 5e63c79's AmmyApp.swift
# Then the differences between them, so the log shows that nothing else moved.
set -euo pipefail
BASE=5e63c79
rm -rf trees
for t in pure-change pure-control lab-change lab-control; do mkdir -p "trees/$t"; done
for t in pure-change pure-control; do
  git archive "$BASE" project.yml Ammy | tar -x -C "trees/$t"
done
cp Ammy/AmmyApp.swift trees/pure-change/Ammy/AmmyApp.swift
for t in lab-change lab-control; do
  cp project.yml "trees/$t/"
  cp -R Ammy "trees/$t/Ammy"
done
git show "$BASE:Ammy/AmmyApp.swift" > trees/lab-control/Ammy/AmmyApp.swift
echo "== AmmyApp.swift in each tree (sha256)"
shasum -a 256 trees/*/Ammy/AmmyApp.swift
echo "== pure-control -> pure-change"
diff trees/pure-control/Ammy/AmmyApp.swift trees/pure-change/Ammy/AmmyApp.swift || true
echo "== lab-control -> lab-change (the whole Ammy folder)"
diff -r trees/lab-control/Ammy trees/lab-change/Ammy || true
echo "== pure-change -> lab-change (the lab's additions)"
diff -r trees/pure-change trees/lab-change || true
