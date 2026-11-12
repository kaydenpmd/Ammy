import os
import SwiftUI
import VisionKit

private let log = Logger(subsystem: "com.local.ammy", category: "scan")

/// An endpoint and key handed over by QR code, so neither has to be typed.
///
/// The code is plain JSON, `{"endpoint": "...", "key": "..."}`, the two
/// values under the names a receiver shows them by. Issun draws it on its
/// setup window's last page (`PairingCode` in Issun), and any other receiver
/// can draw the same. It isn't a link: a link would name an app to open, and
/// the Camera app would offer to open a URL with the key in it.
struct EndpointCode: Decodable, Equatable {
    let endpoint: String
    let key: String

    /// Nil for any code that isn't one of these, so scanning a menu's QR
    /// code by mistake changes nothing. The endpoint must be an https URL
    /// with a host, the rule `PresenceRelay.normalised` applies to a typed one.
    static func parse(_ text: String) -> EndpointCode? {
        guard let data = text.data(using: .utf8),
              let code = try? JSONDecoder().decode(EndpointCode.self, from: data),
              let url = URL(string: code.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false
        else { return nil }
        return EndpointCode(endpoint: url.absoluteString, key: code.key)
    }
}

/// The scanning sheet: VisionKit's own scanner, the camera with the system's
/// highlighting and guidance, under an inline title with Cancel, as a sheet
/// in a system app would have it. Closes itself on the first code that is an
/// endpoint's; every other code is ignored.
struct CodeScannerSheet: View {
    let onFound: (EndpointCode) -> Void
    @Environment(\.dismiss) private var dismiss

    /// The scanner works on this device: VisionKit needs an A12 or later and
    /// a camera. The row that opens this is hidden where it's false.
    static var isSupported: Bool { DataScannerViewController.isSupported }

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isAvailable {
                    CodeScanner { code in
                        onFound(code)
                        dismiss()
                    }
                    .ignoresSafeArea()
                } else {
                    // isAvailable is false when camera access was turned off
                    // for Ammy, or the camera is restricted.
                    ContentUnavailableView(
                        "Camera Not Available",
                        systemImage: "camera",
                        description: Text("Allow Ammy to use the camera in Settings to scan a code.")
                    )
                }
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct CodeScanner: UIViewControllerRepresentable {
    let onFound: (EndpointCode) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onFound = onFound
        // Scanning starts once the view is in a window; starting earlier
        // throws. It asks for camera access itself the first time.
        if !scanner.isScanning {
            DispatchQueue.main.async {
                do {
                    try scanner.startScanning()
                } catch {
                    log.error("couldn't start scanning: \(String(describing: error), privacy: .public)")
                }
            }
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onFound: (EndpointCode) -> Void
        private var done = false

        init(onFound: @escaping (EndpointCode) -> Void) { self.onFound = onFound }

        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in addedItems {
                guard case .barcode(let barcode) = item, let text = barcode.payloadStringValue else { continue }
                if let code = EndpointCode.parse(text) {
                    done = true
                    log.notice("scanned an endpoint code (key \(code.key.isEmpty ? "empty" : "\(code.key.count) characters", privacy: .public))")
                    onFound(code)
                    return
                }
                log.notice("ignored a QR code that isn't an endpoint's (\(text.count) characters)")
            }
        }
    }
}
