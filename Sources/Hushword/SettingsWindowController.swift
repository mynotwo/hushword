import AppKit
import SwiftUI

@MainActor
private final class SettingsPopoverCloseDelegate: NSObject, NSPopoverDelegate {
    var onClose: (() -> Void)?

    func popoverDidClose(_ notification: Notification) {
        onClose?()
    }
}

@MainActor
package final class SettingsWindowController<Content: View>: NSWindowController {
    private var popoverCloseDelegate: SettingsPopoverCloseDelegate?

    package init(
        rootView: Content,
        title: String = "Hushword Settings",
        size: NSSize = NSSize(width: 520, height: 500),
        minimumSize: NSSize = NSSize(width: 480, height: 460)
    ) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable,
            ],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentMinSize = minimumSize
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = NSHostingController(rootView: rootView)
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    package func show(activateApplication: Bool = true) {
        guard let window else { return }
        window.center()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        if activateApplication {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    package func showAfterClosingPopover(
        _ popover: NSPopover,
        activateApplication: Bool = true,
    ) {
        guard popover.isShown else {
            show(activateApplication: activateApplication)
            return
        }

        let closeDelegate = SettingsPopoverCloseDelegate()
        closeDelegate.onClose = { [weak self, weak popover] in
            popover?.delegate = nil
            self?.popoverCloseDelegate = nil
            DispatchQueue.main.async { [weak self] in
                self?.show(activateApplication: activateApplication)
            }
        }
        popoverCloseDelegate = closeDelegate
        popover.delegate = closeDelegate
        popover.animates = false
        popover.performClose(nil)
    }
}
