# Feedback Assistant report, ready to file

Filed from: Feedback Assistant → iOS & iPadOS → Developer Technologies & SDKs → SwiftUI.
Attach: SafeAreaBarLargeTitle.zip (the Xcode project from the "Jitter repro" CI run on the
jitter-lab branch), and a screen recording of the repro (optional but helpful).

---

**Title**

safeAreaBar on a List or Form makes the large title snap shut and the list jump ahead of the finger at the start of a scroll

**Description**

In a NavigationStack with a large title, attaching `.safeAreaBar(edge: .bottom)` to a List or Form breaks the large title's collapse. As soon as the user starts scrolling down, the title collapses completely, in one frame on iOS 26.5 and over about three frames on iOS 27.0, and the list jumps ahead of the finger by up to the full collapse distance (52 pt). Attaching the same bar to the NavigationStack instead, or using `safeAreaInset(edge: .bottom)`, gives a smooth collapse that tracks the finger.

**Steps to reproduce**

1. Open the attached project and run it on an iPhone or the iOS simulator. "Bar on List" is on.
2. Put a finger on the list and drag upward slowly.
3. Turn "Bar on List" off, which moves the same safeAreaBar to the NavigationStack, and repeat step 2.

**Expected:** In both cases the large title collapses gradually as the finger moves, and the list stays under the finger.

**Actual:** With the bar on the List, the title snaps shut as the drag begins and the list jumps up, 52 pt in one frame on iOS 26.5 and about 34 pt over three frames on iOS 27.0. With the bar on the NavigationStack it behaves as expected.

**What we measured**

We logged every display frame (contentOffset, adjustedContentInset, the navigation bar's height, and the finger's position) and every inset change with its call stack:

- With safeAreaBar on the List, the List's UICollectionView sits inside `_UIInteractionView<_UIScrollPocketCollectorInteraction, …>`. During the collapse, UIKit's eager safe-area update (`-[UIViewController _updateViewSafeAreaInsetsAndEagerlyUpdateContentScrollView:]` → `-[UIView _eagerlyUpdateSafeAreaInsetsToDescendant:]`) no longer reaches the collection view. Its new top inset arrives only from SwiftUI's display-list render: `DisplayList.ViewUpdater.Platform.updateGeometry` → `-[UIView setCenter:]` → `-[UIView _updateCombinedInsetsIfNecessary]` → `-[UIScrollView setSafeAreaInsets:]`.
- Each late inset change re-pins the content offset (`_UIScrollViewAdjustForOverlayInsetsChangeIfNecessary`). That advances the collapse, which triggers another render. On iOS 26.5 a 0.5 pt finger movement produced 35 inset updates inside one frame (126 → 74 pt in 1.5 pt steps), leaving the content 52 pt ahead of the finger for the rest of the drag.
- It happens with any safeAreaBar content (zero height included), with List and Form, partly with ScrollView, and with `.scrollEdgeEffectStyle(.hard, for: .bottom)` or `.scrollEdgeEffectHidden(true, for: .bottom)`.
- It doesn't happen with `safeAreaInset`, `contentMargins`, `safeAreaPadding`, a `.bottomBar` toolbar, or safeAreaBar on the NavigationStack. Those all update through UIKit's eager path, and the collapse tracks the finger (≤ 2.5 pt).

**Configurations**

- iPhone SE (3rd generation), iOS 27.2: app built with Xcode 26.6 (iOS 26.5 SDK). Also recorded on the same device on 11 September 2026, iOS version not noted: at the start of most downward scrolls the list jumped 49–57 pt in a single frame.
- iOS 26.5 simulator (Xcode 26.6) and iOS 27.0 simulator (Xcode 27.2 RC), iPhone SE (3rd generation).

**Workaround and its cost**

We moved the safeAreaBar to the NavigationStack. That runs into FB23732628: the stack doesn't pass the bar's inset down to the List, so the List needs `contentMargins(.bottom, barHeight, for: .scrollContent)`, and the bar has to be hidden by hand on pushed screens, because a stack's bar outlives its pages.
