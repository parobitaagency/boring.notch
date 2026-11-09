//
//  ParobitaSettings.swift
//  boringNotch
//
//  Settings added in the Parobita build: Liquid Glass notch and the
//  iPhone-style lock screen player.
//

import Defaults
import SwiftUI

extension Defaults.Keys {
    /// The open notch uses the macOS 26 Liquid Glass material instead of black.
    static let liquidGlassNotch = Key<Bool>("parobita.liquidGlassNotch", default: true)
    /// How dark the glass is tinted, so white text stays readable on light wallpapers.
    static let liquidGlassTint = Key<Double>("parobita.liquidGlassTint", default: 0.35)
    /// Show the now-playing player on the lock screen.
    static let lockScreenPlayer = Key<Bool>("parobita.lockScreenPlayer", default: true)
    /// Fill the lock screen with the zoomed album artwork behind the player.
    static let lockScreenArtwork = Key<Bool>("parobita.lockScreenArtwork", default: true)
}

/// The notch background: black when closed (it has to blend with the real
/// notch), Liquid Glass when open on macOS 26.
struct ParobitaNotchBackground<S: Shape>: View {
    let isOpen: Bool
    let shape: S
    @Default(.liquidGlassNotch) private var liquidGlass
    @Default(.liquidGlassTint) private var tint

    var body: some View {
        if isOpen, liquidGlass, #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.tint(.black.opacity(tint)), in: shape)
        } else {
            Color.black
        }
    }
}

/// The settings rows for the Parobita features.
struct ParobitaSettingsRows: View {
    @Default(.liquidGlassNotch) private var liquidGlass
    @Default(.liquidGlassTint) private var tint

    var body: some View {
        Defaults.Toggle(key: .liquidGlassNotch) {
            Text("Liquid Glass notch (macOS 26)")
        }
        if liquidGlass {
            HStack {
                Text("Glass darkness")
                Slider(value: $tint, in: 0...0.8)
                Text(String(format: "%.0f%%", tint * 100))
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
        }
        Defaults.Toggle(key: .lockScreenPlayer) {
            Text("Music player on lock screen")
        }
        Defaults.Toggle(key: .lockScreenArtwork) {
            Text("Album artwork as lock screen background")
        }
    }
}
