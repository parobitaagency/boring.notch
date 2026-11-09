//
//  LockScreenPlayer.swift
//  boringNotch
//
//  An iPhone-style now-playing screen on the macOS lock screen: the album
//  artwork zoomed to fill the screen, a clock, and a glass player card with
//  the artwork, title, progress and controls in front of it.
//
//  The windows are moved into the SkyLight space that sits above the lock
//  screen, the same way the notch itself appears there. The background
//  never takes clicks or keys, so typing the password and Touch ID keep
//  working; it fades out at the bottom so the password field stays visible.
//

import AppKit
import Combine
import Defaults
import SkyLightWindow
import SwiftUI

private final class LockScreenPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(frame: NSRect, level: NSWindow.Level, clickThrough: Bool) {
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = clickThrough
        self.level = level
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        alphaValue = 0
    }
}

@MainActor
final class LockScreenPlayer {
    static let shared = LockScreenPlayer()

    private var backgroundWindow: LockScreenPanel?
    private var cardWindow: LockScreenPanel?
    private var observers: [Any] = []
    private var cancellables = Set<AnyCancellable>()
    private var isLocked = false
    private var started = false

    static let cardSize = CGSize(width: 440, height: 196)

    func start() {
        guard !started else { return }
        started = true
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isLocked = true
                self?.update()
            }
        })
        observers.append(center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isLocked = false
                self?.update()
            }
        })
        MusicManager.shared.$isPlayerIdle
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)
        Defaults.publisher(.lockScreenPlayer, options: []).map { _ in () }
            .merge(with: Defaults.publisher(.lockScreenArtwork, options: []).map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                // Rebuild so the background follows the setting.
                self.hide(animated: false)
                self.update()
            }
            .store(in: &cancellables)
    }

    private var shouldShow: Bool {
        isLocked && Defaults[.lockScreenPlayer] && !MusicManager.shared.isPlayerIdle
    }

    private func update() {
        if shouldShow { show() } else { hide(animated: isLocked) }
    }

    private func show() {
        guard cardWindow == nil, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame

        if Defaults[.lockScreenArtwork] {
            // Below the notch (mainMenu + 3) and below the card.
            let background = LockScreenPanel(frame: frame, level: .mainMenu + 1, clickThrough: true)
            background.contentView = NSHostingView(rootView: LockScreenBackgroundView(music: .shared))
            background.setFrame(frame, display: false)
            present(background)
            backgroundWindow = background
        }

        let size = Self.cardSize
        // Centred, a little below the middle: under the clock, above the
        // user picture and password field.
        let cardFrame = NSRect(x: frame.midX - size.width / 2,
                               y: frame.minY + frame.height * 0.36,
                               width: size.width, height: size.height)
        let card = LockScreenPanel(frame: cardFrame, level: .mainMenu + 2, clickThrough: false)
        card.contentView = NSHostingView(rootView: LockScreenPlayerCard(music: .shared))
        card.setFrame(cardFrame, display: false)
        present(card)
        cardWindow = card
    }

    private func present(_ window: LockScreenPanel) {
        window.orderFrontRegardless()
        SkyLightOperator.shared.delegateWindow(window)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            window.animator().alphaValue = 1
        }
    }

    private func hide(animated: Bool) {
        for window in [backgroundWindow, cardWindow].compactMap({ $0 }) {
            let finish = {
                SkyLightOperator.shared.undelegateWindow(window)
                window.orderOut(nil)
                window.close()
            }
            if animated {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.25
                    window.animator().alphaValue = 0
                }, completionHandler: finish)
            } else {
                finish()
            }
        }
        backgroundWindow = nil
        cardWindow = nil
    }
}

// MARK: - Views

private struct LockScreenBackgroundView: View {
    @ObservedObject var music: MusicManager

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                Image(nsImage: music.albumArt)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .id(music.albumArt.hashValue)
                    .transition(.opacity)
                // Keep white text readable on bright covers.
                LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.25)],
                               startPoint: .top, endPoint: .bottom)
                LockScreenClock()
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, proxy.size.height * 0.08)
            }
            .animation(.easeInOut(duration: 0.4), value: music.albumArt.hashValue)
            // Fade out at the bottom, where macOS shows the user and password.
            .mask(
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.70),
                    .init(color: .clear, location: 0.88),
                ], startPoint: .top, endPoint: .bottom)
            )
        }
        .ignoresSafeArea()
    }
}

/// Our own clock: the system one sits under the artwork.
private struct LockScreenClock: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 2) {
                Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text(context.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 104, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(.white.opacity(0.92))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 2)
        }
    }
}

private struct LockScreenPlayerCard: View {
    @ObservedObject var music: MusicManager

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Image(nsImage: music.albumArt)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(music.songTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                    Text(music.artistName)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            progress
            controls
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(width: LockScreenPlayer.cardSize.width, height: LockScreenPlayer.cardSize.height)
        .background(cardBackground)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular.tint(.black.opacity(0.15)), in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let duration = max(music.songDuration, 0)
            let elapsed = min(max(music.estimatedPlaybackPosition(at: context.date), 0), duration)
            VStack(spacing: 4) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.25))
                        Capsule().fill(.white)
                            .frame(width: duration > 0 ? proxy.size.width * elapsed / duration : 0)
                    }
                }
                .frame(height: 5)
                HStack {
                    Text(Self.format(elapsed))
                    Spacer()
                    Text("-" + Self.format(max(duration - elapsed, 0)))
                }
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 46) {
            control("backward.fill", size: 22) { music.previousTrack() }
            control(music.isPlaying ? "pause.fill" : "play.fill", size: 30) { music.togglePlay() }
            control("forward.fill", size: 22) { music.nextTrack() }
        }
    }

    private func control(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 44, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
