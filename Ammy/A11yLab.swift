// Lab only: a11y-lab-nowplaying, never merged. What lets CI read the Now
// Playing card's accessibility element with and without the change of
// 4 Nov 2026 (AmmyApp.swift, NowPlayingRow.body: .accessibilityLabel { Text
// ("Now Playing"); label } after .accessibilityElement(children: .combine)):
//
//   A11yLab        a song set by hand, from the -a11yLabTrack launch
//                  argument, since the simulator has no Music app.
//                  NowPlayingMonitor.refresh() publishes it in place of the
//                  player's, so the row draws it as it would a real one.
//   A11yLabProbe   when the UI test sets LAB_OUT and LAB_TAG: the window's
//                  metrics, when the song first showed, and, each time the
//                  test asks, everything the app vends to VoiceOver (label,
//                  value, traits, frame) in the order a walk of the
//                  accessibility containers meets it.
//
// Nothing here touches the row or AmmyApp.swift; NowPlayingMonitor reads the
// song and starts the probe.

import SwiftUI
import UIKit

@MainActor
enum A11yLab {
    /// "short", "explicit" or "long", from -a11yLabTrack; nil without it.
    static let trackName: String? = UserDefaults.standard.string(forKey: "a11yLabTrack")

    /// The song -a11yLabTrack names, and its cover, made once. The cover is a
    /// plain two-colour square drawn here (the header lab's), so nothing is
    /// fetched; storeID "0" is what a local file reports, so nothing is
    /// looked up either.
    static let demo: (track: Track, cover: UIImage)? = {
        guard let name = trackName else { return nil }
        let fields: (title: String, artist: String, explicit: Bool)
        switch name {
        case "short":
            fields = ("Blue", "Joni Mitchell", false)
        case "explicit":
            fields = ("HUMBLE.", "Kendrick Lamar", true)
        case "long":
            // From the owner's recording of Music on 1 Nov 2026 (CLAUDE.md,
            // Open work item 10): both lines overflow the row and scroll.
            fields = ("Prime Time Golden Hour Show (Soundtrack)",
                      "Shiori Sasaki, ATLUS Sound Team & ATLUS GAME MUSIC", false)
        default:
            return nil
        }
        let size = CGSize(width: 600, height: 600)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let cover = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(red: 0.93, green: 0.55, blue: 0.22, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.80, green: 0.27, blue: 0.36, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: size.height * 0.62, width: size.width, height: size.height * 0.38))
        }
        let track = Track(
            title: fields.title,
            artist: fields.artist,
            album: "",
            duration: 200,
            elapsed: 0,
            storeID: "0",
            artworkJPEG: cover.jpegData(compressionQuality: 0.9),
            explicit: fields.explicit
        )
        return (track, cover)
    }()
}

@MainActor
final class A11yLabProbe {
    static let shared = A11yLabProbe()

    private var dir: String?
    private var tag: String?
    private var poller: DispatchSourceTimer?
    private var trackNoted = false

    /// Does nothing unless the UI test set LAB_OUT and LAB_TAG.
    func startIfAsked() {
        let env = ProcessInfo.processInfo.environment
        guard dir == nil, let dir = env["LAB_OUT"], let tag = env["LAB_TAG"] else { return }
        self.dir = dir
        self.tag = tag
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        note([
            "k": "start",
            "track": A11yLab.trackName ?? "",
            "os": UIDevice.current.systemVersion,
            "args": ProcessInfo.processInfo.arguments,
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            MainActor.assumeIsolated { A11yLabProbe.shared.metrics() }
        }
        // The test asks for a dump by creating <tag>.axreq.<label> in LAB_OUT
        // and waits for <tag>-ax-<label>.json.
        let prefix = tag + ".axreq."
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "a11ylab.requests"))
        timer.schedule(deadline: .now() + 0.2, repeating: 0.2)
        timer.setEventHandler { @Sendable in
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
            for name in names where name.hasPrefix(prefix) {
                try? FileManager.default.removeItem(atPath: (dir as NSString).appendingPathComponent(name))
                let label = String(name.dropFirst(prefix.count))
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { A11yLabProbe.shared.dump(label) }
                }
            }
        }
        timer.resume()
        poller = timer
    }

    /// The moment the lab's song was first published, which is when the row's
    /// lines start their loop.
    func trackShown(_ track: Track) {
        guard !trackNoted else { return }
        trackNoted = true
        note(["k": "track", "title": track.title, "artist": track.artist, "explicit": track.explicit])
    }

    // MARK: Records

    private func metrics() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        let window = windows.first(where: \.isKeyWindow) ?? windows.first
        var r: [String: Any] = [
            "k": "metrics",
            "scale": Double(UIScreen.main.scale),
            "screen": rect(UIScreen.main.bounds),
            "contentSize": UIApplication.shared.preferredContentSizeCategory.rawValue,
            "reduceMotion": UIAccessibility.isReduceMotionEnabled,
            "voiceOver": UIAccessibility.isVoiceOverRunning,
        ]
        if let bar = scenes.first?.statusBarManager?.statusBarFrame { r["statusBar"] = rect(bar) }
        if let window {
            let s = window.safeAreaInsets
            r["safeArea"] = [Double(s.top), Double(s.left), Double(s.bottom), Double(s.right)]
            r["style"] = window.traitCollection.userInterfaceStyle == .dark ? "dark" : "light"
        }
        note(r)
    }

    /// Every element the app vends to VoiceOver, in the order a walk of the
    /// accessibility containers meets them: an element is recorded and not
    /// entered (VoiceOver stops there too); a container is entered through
    /// accessibilityElements, then accessibilityElement(at:), then, for a
    /// plain view, its subviews. Hidden views and accessibilityElementsHidden
    /// are skipped. Also the list's cells, in the window, for the geometry.
    private func dump(_ label: String) {
        guard let dir, let tag else { return }
        let started = Date().timeIntervalSince1970
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        var elements: [[String: Any]] = []
        for window in windows where !window.isHidden {
            visit(window, depth: 0, path: [], into: &elements)
        }
        for (i, _) in elements.enumerated() { elements[i]["index"] = i }
        var cells: [[String: Any]] = []
        for window in windows {
            for cell in all(UICollectionViewCell.self, in: window) where !cell.isHidden {
                cells.append([
                    "class": String(describing: type(of: cell)),
                    "frame": rect(cell.convert(cell.bounds, to: nil)),
                ])
            }
        }
        let record: [String: Any] = [
            "label": label,
            "wall": started,
            "took": Date().timeIntervalSince1970 - started,
            "voiceOver": UIAccessibility.isVoiceOverRunning,
            "elements": elements,
            "cells": cells,
        ]
        let path = (dir as NSString).appendingPathComponent("\(tag)-ax-\(label).json")
        guard JSONSerialization.isValidJSONObject(record),
              let data = try? JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
        else {
            note(["k": "dump-failed", "label": label])
            return
        }
        do {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            note(["k": "dump-failed", "label": label, "error": "\(error)"])
        }
    }

    private func visit(_ object: NSObject, depth: Int, path: [String], into out: inout [[String: Any]]) {
        guard depth < 80 else { return }
        if let view = object as? UIView, view.isHidden || view.alpha < 0.01 { return }
        if object.accessibilityElementsHidden { return }
        if object.isAccessibilityElement {
            out.append(describe(object, depth: depth, path: path))
            return
        }
        let next = path + [String(describing: type(of: object))]
        if let children = object.accessibilityElements, !children.isEmpty {
            for case let child as NSObject in children {
                visit(child, depth: depth + 1, path: next, into: &out)
            }
            return
        }
        let count = object.accessibilityElementCount()
        if count > 0, count != NSNotFound {
            for i in 0..<count {
                if let child = object.accessibilityElement(at: i) as? NSObject {
                    visit(child, depth: depth + 1, path: next, into: &out)
                }
            }
            return
        }
        if let view = object as? UIView {
            for sub in view.subviews {
                visit(sub, depth: depth + 1, path: next, into: &out)
            }
        }
    }

    private func describe(_ o: NSObject, depth: Int, path: [String]) -> [String: Any] {
        var d: [String: Any] = [
            "class": String(describing: type(of: o)),
            "label": o.accessibilityLabel as Any? ?? NSNull(),
            "value": o.accessibilityValue as Any? ?? NSNull(),
            "hint": o.accessibilityHint as Any? ?? NSNull(),
            "traits": Self.traitNames(o.accessibilityTraits),
            "traitsRaw": String(format: "0x%llx", o.accessibilityTraits.rawValue),
            "frame": rect(o.accessibilityFrame),
            "depth": depth,
            "path": Array(path.suffix(4)),
        ]
        if let attributed = o.accessibilityAttributedLabel {
            d["attributedLabel"] = attributed.string
            var runs: [[String: Any]] = []
            attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, range, _ in
                runs.append([
                    "range": [range.location, range.length],
                    "text": (attributed.string as NSString).substring(with: range),
                    "keys": attributes.keys.map(\.rawValue).sorted(),
                ])
            }
            d["attributedRuns"] = runs
        }
        if let identified = o as? UIAccessibilityIdentification, let id = identified.accessibilityIdentifier, !id.isEmpty {
            d["identifier"] = id
        }
        if let language = o.accessibilityLanguage { d["language"] = language }
        if let inputLabels = o.accessibilityUserInputLabels, !inputLabels.isEmpty { d["inputLabels"] = inputLabels }
        if let actions = o.accessibilityCustomActions, !actions.isEmpty { d["customActions"] = actions.map(\.name) }
        return d
    }

    private static func traitNames(_ traits: UIAccessibilityTraits) -> [String] {
        let known: [(UIAccessibilityTraits, String)] = [
            (.button, "button"), (.link, "link"), (.header, "header"), (.searchField, "searchField"),
            (.image, "image"), (.selected, "selected"), (.playsSound, "playsSound"),
            (.keyboardKey, "keyboardKey"), (.staticText, "staticText"), (.summaryElement, "summaryElement"),
            (.notEnabled, "notEnabled"), (.updatesFrequently, "updatesFrequently"),
            (.startsMediaSession, "startsMediaSession"), (.adjustable, "adjustable"),
            (.allowsDirectInteraction, "allowsDirectInteraction"), (.causesPageTurn, "causesPageTurn"),
            (.tabBar, "tabBar"), (.toggleButton, "toggleButton"), (.supportsZoom, "supportsZoom"),
        ]
        var names: [String] = []
        var rest = traits.rawValue
        for (trait, name) in known where traits.contains(trait) {
            names.append(name)
            rest &= ~trait.rawValue
        }
        if rest != 0 { names.append(String(format: "other:0x%llx", rest)) }
        return names
    }

    // MARK: Helpers

    private func note(_ record: [String: Any]) {
        guard let dir, let tag else { return }
        var record = record
        record["wall"] = Date().timeIntervalSince1970
        guard JSONSerialization.isValidJSONObject(record),
              let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        else { return }
        let path = (dir as NSString).appendingPathComponent(tag + ".probe.jsonl")
        let line = data + Data([0x0A])
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            FileManager.default.createFile(atPath: path, contents: line)
        }
    }

    private func rect(_ r: CGRect) -> [Double] {
        [r.minX, r.minY, r.width, r.height].map { v in
            v.isFinite ? (Double(v) * 100).rounded() / 100 : -1
        }
    }

    private func all<T: UIView>(_ type: T.Type, in root: UIView) -> [T] {
        var found: [T] = []
        var pending: [UIView] = [root]
        while let view = pending.popLast() {
            if let match = view as? T { found.append(match) }
            pending.append(contentsOf: view.subviews.reversed())
        }
        return found
    }
}
