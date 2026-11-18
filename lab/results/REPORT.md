# pip-bar-lab, 18 Nov 2026

The question: the pip-bar branch (commit b017fb8) gives the bottom bar's room to the main page's UIKit safe area (`BarRoom`, `additionalSafeAreaInsets.bottom` on the page's view controller) instead of SwiftUI's (`.safeAreaPadding`), so iOS rests Picture in Picture above Start and Stop. Does PiP now rest there, and is everything else about the bar as build 201 had it?

The real Ammy, built as CI builds a release (Xcode 26.6, iOS 26.5 SDK), with keyboard-lab's probe and the bar picked at launch: `main` is build 201's arrangement, `fix` the branch's, `form148` the bar on the Form (the jump's positive control). Dark mode. Setups: the SE and 17e device types copied with the iPad's PiP flags (`lab/fakepip.py`) on iOS 27.0 (runtime 24A434, Xcode 27.1) and iOS 26.5 (Xcode 26.6), and an iPad Air 11-inch (M2) on iOS 27.0. `analyse.py` wrote each run's `analysis.txt` and `sheets/`; `cases/` holds each setup's text files.

## Run 44397032602: everything

All five tests on all five setups. The keyboard cases, the ends of the page, the History slides and the screen at rest are the same in `fix` and `main` on every setup: the buttons 21 pt above the keyboard; a focused Key field on the SE ending exactly at the bar's top; History 36.00 pt above Stop at the end of the page on the SE (default size and XXXL), with the list's bottom inset 87.5 in both; the page's copy of the bar on the stack bar's frame at every layout (y 579.5 on the SE, 756.67 on the 17e, 1092.5 on the iPad); 0 differing pixels below the status bar at rest on iOS 27 (on 26.5, a notifications prompt over one screenshot and glass pixels off by up to 3 of 255). Slow drags tracked the finger within 1.5 to 8 pt a frame in `fix` and `main`; `form148` jumped up to 39.5.

Its PiP test was right on the iOS 27 setups. On 26.5 the test runner's `UIScreen.main` said 320 x 480, so the drags went to the top, and its History step measured PiP where the keyboard step left it, or tapped PiP instead of the History row.

## Run 44404318290: the PiP test again

The screen read from SpringBoard, PiP parked at the bottom right before History opens, the scroll started high on the screen and the History row tapped near its start. The 17e on 26.5 passed in attempt 2 (attempt 1 never got a runner) and the SE on 27.0 in attempt 3 (in attempt 1 XCUITest lost Ammy's process at a launch while Ammy kept running); `cases/lab-se-pip-ios27` is attempt 3.

| PiP at a bottom corner | SE, 27.0 and 26.5 | 17e, 27.0 and 26.5 | iPad, 27.0 |
|---|---|---|---|
| `main` | 10 pt from the bottom, over the button by 61 | 44, over it by 27.33 | 44, over it by 27 |
| `main`, keyboard up | over Stop and Restart by 61.5 | by 61.33 | by 47.5 |
| `fix` | 97.5 from the bottom, 26 above the button | 97.33 to 98, 26 to 26.67 above | 111.5, 40 above |
| `fix`, keyboard up | 26 above Stop and Restart | 26 above | 40 above |
| `fix`, over History | 10 from the bottom | 44 | 44 |
| `fix`, back from History | 97.5 | 97.33 | 111.5 |

SpringBoard's own log shows the room Ammy reports: with `fix`, 87.5 on the SE, 87.33 on the 17e and 87.5 on the iPad, and with the keyboard up 347.5, 415.33 on the 17e on 27.0 (422.33 on 26.5, whose keyboard is 7 pt taller) and 424.5, the keyboard and the bar together. `main` reports 0, 34 and 20.

The PiP side is also in the design library, `apple/ios-pip-placement/`.
