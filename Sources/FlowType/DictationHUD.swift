import AppKit
import FlowTypeCore
import SwiftUI

package struct DictationHUDVisibilityState {
    private var generation = 0

    package init() {}

    package mutating func beginShow() {
        generation += 1
    }

    package mutating func beginHide() -> Int {
        generation += 1
        return generation
    }

    package func shouldCompleteHide(generation: Int) -> Bool {
        self.generation == generation
    }
}

package enum DictationHUDWindowPolicy {
    package static let collectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
        .ignoresCycle,
        .stationary,
    ]
}

@MainActor
final class DictationHUDController {
    private let panel: NSPanel
    private let viewModel = DictationHUDViewModel()
    private var hideTask: Task<Void, Never>?
    private var visibilityState = DictationHUDVisibilityState()

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 116, height: 42),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = DictationHUDWindowPolicy.collectionBehavior
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.contentView = NSHostingView(
            rootView: DictationHUDView(viewModel: viewModel)
        )
        panel.setContentSize(NSSize(width: 116, height: 42))
    }

    func update(_ presentation: DictationPresentation) {
        viewModel.audioLevel = presentation.audioLevel
        let phase = presentation.hudPhase
        hideTask?.cancel()
        hideTask = nil

        guard phase != .hidden else {
            viewModel.audioLevel = 0
            hide()
            return
        }

        viewModel.phase = phase
        visibilityState.beginShow()
        positionPanel()
        if panel.isVisible {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        } else {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(
                    name: .easeOut
                )
                panel.animator().alphaValue = 1
            }
        }

        if phase == .failure {
            hideTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                guard !Task.isCancelled else { return }
                self?.hide()
            }
        }
    }

    private func positionPanel() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first {
            NSMouseInRect(mouseLocation, $0.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }

        let origin = NSPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.minY + 34
        )
        panel.setFrameOrigin(origin)
    }

    private func hide() {
        guard panel.isVisible else { return }
        let generation = visibilityState.beginHide()
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(
                    name: .easeIn
                )
                panel.animator().alphaValue = 0
            },
            completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if visibilityState.shouldCompleteHide(
                        generation: generation
                    ) {
                        panel.orderOut(nil)
                    } else {
                        panel.orderFrontRegardless()
                    }
                    panel.alphaValue = 1
                }
            }
        )
    }
}

@MainActor
private final class DictationHUDViewModel: ObservableObject {
    @Published var phase: DictationHUDPhase = .hidden
    @Published var audioLevel = 0.0
}

private struct DictationHUDView: View {
    @ObservedObject var viewModel: DictationHUDViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 9) {
            phaseIcon
                .frame(width: 24, height: 24)
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.opacity)
        }
        .padding(.horizontal, 13)
        .frame(height: 38)
        .background(Color.black.opacity(0.88), in: Capsule())
        .frame(width: 116, height: 42)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.18),
            value: viewModel.phase
        )
    }

    @ViewBuilder
    private var phaseIcon: some View {
        switch viewModel.phase {
        case .listening:
            ListeningWave(
                level: viewModel.audioLevel,
                reduceMotion: reduceMotion
            )
        case .processing:
            ProgressView()
                .controlSize(.small)
                .tint(.white)
        case .success:
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(red: 0.42, green: 0.92, blue: 0.62))
        case .failure:
            Image(systemName: "exclamationmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(red: 1, green: 0.48, blue: 0.44))
        case .hidden:
            EmptyView()
        }
    }

    private var label: String {
        switch viewModel.phase {
        case .listening:
            return "Listening"
        case .processing:
            return "Working"
        case .success:
            return "Done"
        case .failure:
            return "Try again"
        case .hidden:
            return ""
        }
    }
}

private struct ListeningWave: View {
    let level: Double
    let reduceMotion: Bool

    var body: some View {
        let heights = AudioWaveformPolicy.barHeights(level: level)
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(.white)
                    .frame(
                        width: 2.5,
                        height: heights[index]
                    )
            }
        }
        .frame(width: 22, height: 22)
        .animation(
            reduceMotion ? nil : .linear(duration: 0.07),
            value: level
        )
    }
}
