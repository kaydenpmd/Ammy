import Darwin
import Foundation
import os
import UIKit

/// Everything the phone knows about its own condition at the moment of a push,
/// bundled into the `diag` object the relay records.
///
/// The relay cannot tell "iOS killed the app" from "the app was alive but could
/// not reach the relay" — both look like silence. It also cannot see *why* a
/// kill happened. These fields exist to answer both questions after the fact,
/// because by the time anyone notices the app is gone there is nothing left
/// running to ask.
///
/// The two that decide it, most of the time:
///
///   - `engine_running` false while `running` is true means the keepalive is
///     dead and the app is on borrowed time. Expect death within the hour.
///   - `mem_mb` climbing before a death means iOS reclaimed the app under
///     memory pressure (jetsam), which is a different bug entirely and is not
///     fixed by anything in `KeepAlive`.
///
/// `device_uptime_s` is here because it dates the last reboot precisely. This
/// bug was first blamed on a phone restart; that claim is now checkable rather
/// than remembered.
struct PushDiagnostics: Sendable {
    var keepAlive: KeepAliveDiagnostics
    var appState: String
    /// Seconds of background execution iOS says are left, or -1 when the app is
    /// in the foreground and the question is meaningless.
    var backgroundTimeRemaining: Double
    var memoryMB: Double
    /// Headroom before iOS kills the app, and the lowest that headroom has been
    /// since launch. The current reading can recover before a push goes out; the
    /// low-water mark is what survives to describe the squeeze.
    var availableMemoryMB: Double
    var lowestAvailableMemoryMB: Double
    var memoryWarnings: Int
    var lowPowerMode: Bool
    var thermalState: String
    var appUptime: TimeInterval
    var deviceUptime: TimeInterval

    var dictionary: [String: Any] {
        var d = keepAlive.dictionary
        d["app_state"] = appState
        d["mem_mb"] = Int(memoryMB.rounded())
        d["mem_avail_mb"] = Int(availableMemoryMB.rounded())
        d["mem_avail_min_mb"] = Int(lowestAvailableMemoryMB.rounded())
        d["mem_warnings"] = memoryWarnings
        d["low_power"] = lowPowerMode
        d["thermal"] = thermalState
        d["app_uptime_s"] = Int(appUptime)
        d["device_uptime_s"] = Int(deviceUptime)
        if backgroundTimeRemaining >= 0 {
            d["bg_secs_left"] = Int(backgroundTimeRemaining)
        }
        return d
    }
}

enum DeviceDiagnostics {

    /// Process start. `ProcessInfo.systemUptime` measures the device; this
    /// measures the app, and the difference between them is how you tell a
    /// relaunch from a reboot.
    static let launchedAt = Date()

    /// Count of memory warnings this launch, and the observer that maintains
    /// it. Statics, so both reset when the process does — which is what makes
    /// them comparable with `appUptime` on a death line.
    private static var memoryWarnings = 0
    private static var lowestAvailable = Double.greatestFiniteMagnitude
    private static var warningObserver: NSObjectProtocol?

    @MainActor
    private static func observeMemoryWarningsIfNeeded() {
        guard warningObserver == nil else { return }
        warningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { _ in
            memoryWarnings += 1
        }
    }

    @MainActor
    static func snapshot(keepAlive: KeepAliveDiagnostics) -> PushDiagnostics {
        observeMemoryWarningsIfNeeded()

        let available = availableMemoryMB()
        if available >= 0 {
            lowestAvailable = min(lowestAvailable, available)
        }

        let app = UIApplication.shared

        let state: String
        switch app.applicationState {
        case .active:     state = "active"
        case .inactive:   state = "inactive"
        case .background: state = "background"
        @unknown default: state = "unknown"
        }

        // Returns .greatestFiniteMagnitude whenever the app is not actually
        // running down a background task, which is most of the time. Report
        // that as "not applicable" rather than as an absurd number.
        let remaining = app.backgroundTimeRemaining
        let bg = (remaining.isFinite && remaining < 100_000) ? remaining : -1

        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:    thermal = "nominal"
        case .fair:       thermal = "fair"
        case .serious:    thermal = "serious"
        case .critical:   thermal = "critical"
        @unknown default: thermal = "unknown"
        }

        return PushDiagnostics(
            keepAlive: keepAlive,
            appState: state,
            backgroundTimeRemaining: bg,
            memoryMB: memoryFootprintMB(),
            availableMemoryMB: available,
            lowestAvailableMemoryMB: lowestAvailable == .greatestFiniteMagnitude
                ? -1 : lowestAvailable,
            memoryWarnings: memoryWarnings,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalState: thermal,
            appUptime: Date().timeIntervalSince(launchedAt),
            deviceUptime: ProcessInfo.processInfo.systemUptime
        )
    }

    /// Physical footprint in MB — the number iOS actually uses when deciding
    /// what to reclaim. `phys_footprint`, not `resident_size`: the latter reads
    /// high and does not match what jetsam measures.
    ///
    /// Returns -1 rather than 0 on failure, so a broken read is distinguishable
    /// from an app using no memory.
    /// How much more the app may allocate before iOS terminates it.
    ///
    /// This is the number the footprint alone cannot give you. Ammy sitting at
    /// 19MB says nothing about whether it is about to be killed — jetsam decides
    /// by system-wide pressure and priority band, not by how small the victim
    /// is. If this figure collapses in the minutes before a death, the cause is
    /// memory pressure from everything *else* running. If it stays comfortable,
    /// the app was killed for some other reason and we can stop guessing at
    /// memory.
    ///
    /// Returns -1 rather than 0 when unavailable, so "unknown" stays
    /// distinguishable from "nothing left".
    static func availableMemoryMB() -> Double {
        let bytes = os_proc_available_memory()
        guard bytes > 0 else { return -1 }
        return Double(bytes) / (1024 * 1024)
    }

    static func memoryFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return Double(info.phys_footprint) / (1024 * 1024)
    }
}
