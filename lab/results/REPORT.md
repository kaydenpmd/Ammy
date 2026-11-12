# keyboard-lab, 12 Nov 2026

Run 43177485233, this branch's first push. Ammy built once
as build-ipa.yml builds a release (macos-26, Xcode 26.6, iOS 26.5 SDK), run on
an iPhone SE and an iPhone 17e, iOS 27.0 (Xcode 27.1 test runner) and iOS 26.5
(Xcode 26.6), the simulator in dark mode, the software keyboard. Variants by
`-labBar` (Ammy/LabProbe.swift): `fix` (the keyboard-bar branch), `main`
(build 172), `form148` (the bar on the Form, one reading, as builds 77 to 148),
`ignore` (the bar ignores the home indicator's inset instead of reading it).
`-labRunning YES` shows a session without sending; typing one letter in the
URL or Key field splits the bar into Stop + Restart.

`analysis.txt` is `python lab/analyse.py` over the four artifacts; `cases/`
holds each case's frames as XCUITest read them; `sheets/` the dark
screenshots side by side. iOS leaves the keyboard out of screenshots while the
secure Key field is focused, so in the Key sheets a button under the keyboard
still shows; the frames and `hittable` say where it really is.

## The cause

The bottom inset read outside the bar counts the keyboard. With the keyboard
up it reads 260 pt on the SE and 328 on the 17e (233 and 301 mid-animation),
against 0 and 34 without. The bar's padding was `edgeGap - inset` = 21 - 260
on the SE, so the bar sank 66.5 pt below the keyboard's top (66.3 on the 17e),
its buttons not hittable. The same in `form148`: the bar on the Form was no
different, because the reading was the same. Before build 77 (c02919b, 18 Sept
2026) the padding was `max(0, 16 - inset)`, which clamps to 0 with the
keyboard up; build 77 dropped the clamp. Builds 70 to 76 were not run here.

## The fix

The inset is read a second time from a background that ignores the keyboard
(it reads 0 and 34 throughout), and with the keyboard up the bar pads
`edgeGap` above it.

| setup | keyboard top (pt) | fix: buttons | build 172 / form148 |
|---|---|---|---|
| SE iOS 27.0 | 407 | 335.5-386.0, 21.0 above, hittable | 423.0-473.5, 66.5 under, not hittable |
| SE iOS 26.5 | 407 | same | same |
| 17e iOS 27.0 | 516 | 444.7-495.0, 21.0 above, hittable | 532.0-582.3, 66.3 under, not hittable |
| 17e iOS 26.5 | 509 | 437.7-488.0, 21.0 above, hittable | 525.0-575.3, 66.3 under, not hittable |

The same for the URL field and the Key field, for Start alone, Stop alone and
Stop + Restart. On the SE the focused Key field is scrolled to end exactly at
the bar's top (298.5-319.5 pt).

At rest, the fix against build 172, below the status bar: 0 differing pixels
on every setup but the SE on iOS 26.5 with a session, where 44 pixels on the
glass capsule's rim differ by at most 3 of 255 with identical frames
(rendering noise). `ignore` moved the bar at rest on the 17e (55 pt from the
edge instead of 21) and was dropped.

## The jump

Each variant dragged slowly, faster and flicked from the top, at the default
size and XXXL, the probe logging every frame. The metric here (content moved
less finger moved, from the first frame with a pan) is cruder than the jitter
lab's and includes touch slop, so it is read as fix against build 172: they
match on every gesture and setup (slow drags: biggest one-frame change 2.0-6.0
pt for the fix, 2.5-6.0 for 172), while the `form148` control reaches 8.5-37.5
pt on the same drags. The fix changes no view's position in the hierarchy and
nothing at rest, so this is the expected result.

## Not covered

A real device (the owner's SE runs 27.2); iPad and its floating or hardware
keyboards; History with the keyboard up. The keyboard rising was looked at only
in the 17e iOS 27.0 recording (`sheets/keyboard-rising-17e-ios27-fix.png`, 30
frames from 36.33 to 37.43 s pts_time): Stop rides up with the keyboard and
settles 21 pt above it, with no visible step where the padding changes by 34 pt.
The iOS 26.5 runner's recorder drops frames while things move.
