import Foundation
import SwiftUI

/// The header lab's switches, read once from the launch arguments. This file,
/// and every use of it, exists only on the header-lab-ammy branch, which is a
/// lab and is never merged: it lets CI draw Ammy's one screen three ways, so
/// the owner can compare them as they would look on the phone.
///
///   -HeaderLab current    build 156 as it is (also what no argument gives)
///   -HeaderLab noHeaders  option 1: no "Now Playing", "Endpoint" or "Status"
///                         header; the Endpoint footer stays
///   -HeaderLab inline     option 2: the title inline, the headers kept
///   -HeaderLabDemo        the owner's screen while a session runs: a track
///                         with a cover, an address, Connected and Stop, set
///                         by hand, with nothing started, saved or sent
enum HeaderLab {
    enum Variant: String {
        case current, noHeaders, inline
    }

    static let variant: Variant = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-HeaderLab"),
              flag + 1 < arguments.count,
              let variant = Variant(rawValue: arguments[flag + 1])
        else { return .current }
        return variant
    }()

    static let demo = ProcessInfo.processInfo.arguments.contains("-HeaderLabDemo")
}

extension View {
    /// Option 2's one change: the page's title inline. Every other variant
    /// leaves the title as build 156 has it.
    @ViewBuilder
    func headerLabTitleMode() -> some View {
        if HeaderLab.variant == .inline {
            navigationBarTitleDisplayMode(.inline)
        } else {
            self
        }
    }
}
