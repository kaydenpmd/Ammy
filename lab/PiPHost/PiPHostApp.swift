import AVFoundation
import AVKit
import SwiftUI
import UIKit

// pip-lab only, never merged: floats a solid magenta video in Picture in
// Picture, so the UI tests can find the PiP window by its colour over any
// other app. The movie is written at launch (no network, no bundled file).
// Every step goes to host.log in LAB_OUT, and the PiP state every 2 s, so the
// log shows whether PiP stayed up while other apps were in front.

@main
struct PiPHostApp: App {
    var body: some Scene {
        WindowGroup { HostView().ignoresSafeArea() }
    }
}

struct HostView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> HostController { HostController() }
    func updateUIViewController(_ controller: HostController, context: Context) {}
}

final class PlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

final class HostController: UIViewController, AVPictureInPictureControllerDelegate {
    private let playerView = PlayerView()
    private let status = UILabel()
    private let button = UIButton(type: .system)
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var pip: AVPictureInPictureController?
    private var observations: [NSKeyValueObservation] = []
    private var notes: [String] = []
    private var timer: Timer?
    private var logHandle: FileHandle?

    override func viewDidLoad() {
        super.viewDidLoad()
        openLog()
        view.backgroundColor = .black
        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.backgroundColor = .darkGray
        view.addSubview(playerView)
        status.translatesAutoresizingMaskIntoConstraints = false
        status.textColor = .white
        status.font = .preferredFont(forTextStyle: .footnote)
        status.numberOfLines = 0
        status.accessibilityIdentifier = "status"
        view.addSubview(status)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Start PiP", for: .normal)
        button.accessibilityIdentifier = "startPiP"
        button.addTarget(self, action: #selector(startTapped), for: .touchUpInside)
        view.addSubview(button)
        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            playerView.heightAnchor.constraint(equalTo: playerView.widthAnchor, multiplier: 9.0 / 16.0),
            status.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            status.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40),
        ])
        note("launched, iOS \(UIDevice.current.systemVersion)")
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
            note("audio session active")
        } catch {
            note("audio session failed: \(error)")
        }
        note("supported=\(AVPictureInPictureController.isPictureInPictureSupported())")
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            // A main run loop timer fires on the main thread.
            MainActor.assumeIsolated {
                guard let self else { return }
                let state = UIApplication.shared.applicationState
                self.note("tick active=\(self.pip?.isPictureInPictureActive ?? false) possible=\(self.pip?.isPictureInPicturePossible ?? false) app=\(state == .active ? "active" : state == .background ? "background" : "inactive") rate=\(self.player?.rate ?? -1)", show: false)
            }
        }
        Task { await prepare() }
    }

    private func openLog() {
        guard let dir = ProcessInfo.processInfo.environment["LAB_OUT"] else { return }
        let path = (dir as NSString).appendingPathComponent("host.log")
        FileManager.default.createFile(atPath: path, contents: nil)
        logHandle = FileHandle(forWritingAtPath: path)
    }

    private func note(_ text: String, show: Bool = true) {
        let line = String(format: "%.3f ", Date().timeIntervalSince1970) + text
        print("[host] \(line)")
        if let data = (line + "\n").data(using: .utf8) {
            logHandle?.seekToEndOfFile()
            logHandle?.write(data)
            try? logHandle?.synchronize()
        }
        if show {
            notes.append(text)
            status.text = notes.suffix(8).joined(separator: "\n")
        }
    }

    private func prepare() async {
        do {
            let url = try await Self.makeMovie()
            note("movie written")
            let item = AVPlayerItem(url: url)
            let player = AVQueuePlayer()
            looper = AVPlayerLooper(player: player, templateItem: item)
            playerView.playerLayer.player = player
            playerView.playerLayer.videoGravity = .resizeAspect
            self.player = player
            player.play()
            guard let pip = AVPictureInPictureController(playerLayer: playerView.playerLayer) else {
                note("no PiP controller")
                return
            }
            pip.delegate = self
            pip.canStartPictureInPictureAutomaticallyFromInline = true
            self.pip = pip
            observations.append(pip.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] c, _ in
                DispatchQueue.main.async { self?.note("possible=\(c.isPictureInPicturePossible)") }
            })
            observations.append(pip.observe(\.isPictureInPictureActive, options: [.new]) { [weak self] c, _ in
                DispatchQueue.main.async { self?.note("active=\(c.isPictureInPictureActive)") }
            })
        } catch {
            note("movie failed: \(error)")
        }
    }

    @objc private func startTapped() {
        note("start tapped, possible=\(pip?.isPictureInPicturePossible ?? false)")
        pip?.startPictureInPicture()
    }

    // MARK: AVPictureInPictureControllerDelegate

    func pictureInPictureControllerWillStartPictureInPicture(_ c: AVPictureInPictureController) { note("willStart") }
    func pictureInPictureControllerDidStartPictureInPicture(_ c: AVPictureInPictureController) { note("didStart") }
    func pictureInPictureController(_ c: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        note("failedToStart: \(error)")
    }
    func pictureInPictureControllerWillStopPictureInPicture(_ c: AVPictureInPictureController) { note("willStop") }
    func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) { note("didStop") }

    // MARK: The movie

    /// Two seconds of solid magenta, 640 x 360, H.264, written to tmp.
    static func makeMovie() async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("magenta.mov")
        try? FileManager.default.removeItem(at: url)
        let width = 640, height = 360
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        var made: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes, &made)
        guard let frame = made else { throw CocoaError(.fileWriteUnknown) }
        CVPixelBufferLockBaseAddress(frame, [])
        if let base = CVPixelBufferGetBaseAddress(frame) {
            let rowBytes = CVPixelBufferGetBytesPerRow(frame)
            let p = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    let i = y * rowBytes + x * 4
                    p[i] = 255      // B
                    p[i + 1] = 0    // G
                    p[i + 2] = 255  // R
                    p[i + 3] = 255  // A
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(frame, [])
        for i in 0..<60 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 5_000_000) }
            adaptor.append(frame, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        return url
    }
}
