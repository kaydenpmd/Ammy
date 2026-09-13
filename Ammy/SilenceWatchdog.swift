import Foundation
import UserNotifications

/// An inverted dead-man's switch.
///
/// A dead app cannot notify you that it died. A living one can leave a note
/// that goes off if it stops. So this schedules a notification 15 minutes out
/// and pushes the deadline back on every successful relay push: while Ammy is
/// alive the notification never arrives, and if iOS kills the app the pending
/// request stays in the notification daemon and fires on schedule. That is why
/// it survives force quit, eviction and reboot — it no longer depends on this
/// process existing. Don't replace it with something that tries to detect
/// death directly; there is nothing left running to do the detecting.
///
/// The premise only holds if a notification can be scheduled at all, and that
/// requires authorization. Requesting it is not optional: `add(_:)` on an
/// unauthorized center succeeds silently and delivers nothing, which looks
/// exactly like a working watchdog that never needed to fire.
@MainActor
final class SilenceWatchdog {

    /// Reusing one identifier means each schedule *replaces* the pending
    /// request instead of stacking hundreds of them.
    private static let requestID = "ammy.silence"

    /// Same discipline for the failure note: a second failure replaces the
    /// first rather than adding a second banner.
    private static let failureID = "ammy.failure"

    /// Comfortably longer than the 30s heartbeat, so ordinary network jitter
    /// or a brief backgrounding never trips it.
    private static let delay: TimeInterval = 15 * 60

    private let center = UNUserNotificationCenter.current()
    private var authorized = false

    /// Ask once. Safe to call on every start — iOS only prompts the first time
    /// and returns the existing answer afterwards.
    func requestAuthorizationIfNeeded() async {
        authorized = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Push the deadline back. Call after every successful push, including
    /// "nothing playing" ones — this measures whether the app is alive, not
    /// whether music is playing.
    func postpone() {
        guard authorized else { return }

        // Short on purpose: a notification is scanned, not read. And "isn't
        // running" states the current fact without asserting a history the
        // watchdog cannot know — after a reboot the app never started at all,
        // so "stopped" would be wrong. Resist adding a guess at the cause;
        // force quit, a reboot and a dead battery all look identical from here.
        let content = UNMutableNotificationContent()
        content.title = "Ammy isn't running"
        content.body = "Tap to open"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: Self.requestID,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: Self.delay, repeats: false)
        )

        center.add(request, withCompletionHandler: nil)
    }

    /// Report that the session ended on its own, right now.
    ///
    /// The inverse of the watchdog above, and it lives here because this type
    /// owns the authorization both depend on. The watchdog has to schedule
    /// ahead because nothing will be alive to speak; this fires from inside the
    /// failure itself, while the app is still running, so it can deliver
    /// immediately with a nil trigger.
    ///
    /// `reason` is the same string the status row is showing — it comes from
    /// PushOutcome.summary, so the banner and the screen can never tell two
    /// different stories about the same failure.
    func reportFailure(_ reason: String) {
        guard authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Ammy stopped"
        content.body = "\(reason). Tap to open."
        content.sound = .default

        center.add(
            UNNotificationRequest(identifier: Self.failureID, content: content, trigger: nil),
            withCompletionHandler: nil
        )
    }

    /// Stopping on purpose is not a failure, so clear the note.
    ///
    /// Delivered as well as pending: once a notification has fired it sits in
    /// Notification Center until something removes it, and removePending alone
    /// leaves it there saying Ammy isn't running long after it is.
    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.requestID])
        center.removeDeliveredNotifications(withIdentifiers: [Self.requestID])
    }

    /// Called whenever the app comes to the front.
    ///
    /// Opening Ammy answers the question either notification was asking,
    /// whether or not it was the notification that brought you here. A banner
    /// still sitting in Notification Center while you are looking at the app
    /// is exactly the stale, contradictory state these are meant to prevent.
    ///
    /// Only *delivered* notices are cleared. The watchdog's pending request is
    /// the live dead-man's switch and must stay armed — only postpone() and
    /// cancel() have any business touching that.
    func clearDelivered() {
        center.removeDeliveredNotifications(
            withIdentifiers: [Self.requestID, Self.failureID]
        )
    }
}
