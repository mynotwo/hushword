import HushwordCore
import HushwordAppKit
import Foundation
import SwiftUI

extension DictationEngineTestRunner {
    static func showsCopiedRewriteAsSuccessfulDelivery() async throws {
        let status = AppStatus.copied(
            "Copied. The last dictation was not replaced."
        )
        let presentation = DictationPresentation(
            lifecycleState: status.lifecycleState,
            audioLevel: 0
        )

        guard presentation.hudPhase == .success,
              status.title == "Copied. The last dictation was not replaced." else {
            throw TestFailure(
                description: "a successful clipboard fallback still shows Try again"
            )
        }
    }

    @MainActor
    static func keepsNewListeningHUDAfterOldHideCompletes() async throws {
        var visibility = DictationHUDVisibilityState()
        let oldHideGeneration = visibility.beginHide()
        visibility.beginShow()

        guard visibility.shouldCompleteHide(
            generation: oldHideGeneration
        ) == false else {
            throw TestFailure(
                description: "an old HUD fade-out hid a new listening session"
            )
        }
    }

    @MainActor
    static func usesStationaryAllSpacesHUDWindow() async throws {
        let behavior = DictationHUDWindowPolicy.collectionBehavior
        guard behavior.contains(.canJoinAllSpaces),
              behavior.contains(.fullScreenAuxiliary),
              behavior.contains(.stationary),
              behavior.contains(.transient) == false else {
            throw TestFailure(
                description: "HUD can still be hidden by Space or Exposé management"
            )
        }
    }

    @MainActor
    static func showsAndReusesOneSettingsWindow() async throws {
        let controller = SettingsWindowController(
            rootView: Text("Settings regression test")
        )

        controller.show(activateApplication: false)
        guard let firstWindow = controller.window,
              firstWindow.isVisible else {
            throw TestFailure(description: "settings window did not become visible")
        }

        controller.show(activateApplication: false)
        guard controller.window === firstWindow else {
            throw TestFailure(description: "opening settings created duplicate windows")
        }
        firstWindow.close()
    }

    @MainActor
    static func showsSettingsAfterPopoverCloses() async throws {
        let controller = SettingsWindowController(
            rootView: Text("Deferred settings regression test")
        )
        let hostWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let anchor = NSButton(title: "Open", target: nil, action: nil)
        hostWindow.contentView = anchor
        hostWindow.makeKeyAndOrderFront(nil)
        let popover = NSPopover()
        popover.contentViewController = NSHostingController(
            rootView: Text("Popover").frame(width: 160, height: 100)
        )
        popover.show(
            relativeTo: anchor.bounds,
            of: anchor,
            preferredEdge: .minY
        )

        guard popover.isShown else {
            throw TestFailure(description: "test popover did not open")
        }
        controller.showAfterClosingPopover(
            popover,
            activateApplication: false
        )
        guard controller.window?.isVisible == false else {
            throw TestFailure(description: "settings appeared before the popover closed")
        }

        for _ in 0..<100 where controller.window?.isVisible == false {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        guard popover.isShown == false,
              controller.window?.isVisible == true else {
            throw TestFailure(
                description: "settings did not appear after the popover closed "
                    + "(popover shown: \(popover.isShown), "
                    + "window visible: \(controller.window?.isVisible == true))"
            )
        }
        controller.window?.close()
        hostWindow.close()
    }
}
