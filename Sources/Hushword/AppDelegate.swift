import AppKit
import HushwordCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var hotKeyMonitor: GlobalHotKeyMonitor?
    private var functionKeyMonitor: FunctionKeyMonitor?
    private var dictationHUD: DictationHUDController?
    private var updateController: UpdateController?
    private var onboardingWindow: SettingsWindowController<OnboardingView>?
    private lazy var settingsWindow = SettingsWindowController(
        rootView: SettingsView(model: model)
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        HushwordTemporaryFileCleanup.schedule()
        updateController = UpdateController()
        dictationHUD = DictationHUDController()
        installMenuBarItem()
        model.onPresentationChanged = { [weak self] presentation in
            self?.updatePresentation(presentation)
        }
        hotKeyMonitor = GlobalHotKeyMonitor { action in
            Task { @MainActor in
                switch action {
                case .localDictation:
                    self.model.toggleRecording()
                case .agentRewrite:
                    _ = self.model.rewriteAndReplaceLastOutput()
                }
            }
        }
        functionKeyMonitor = FunctionKeyMonitor(
            shortPressAction: {
                Task { @MainActor in
                    self.model.toggleRecording()
                }
            },
            longPressAction: {
                self.model.rewriteAndReplaceLastOutput()
            }
        )
        if model.shouldPresentOnboarding {
            let controller = SettingsWindowController(
                rootView: OnboardingView(
                    model: model,
                    finish: { [weak self] in
                        self?.onboardingWindow?.close()
                        self?.onboardingWindow = nil
                    }
                ),
                title: "Welcome to Hushword",
                size: NSSize(width: 620, height: 660),
                minimumSize: NSSize(width: 600, height: 620)
            )
            onboardingWindow = controller
            DispatchQueue.main.async { [weak self] in
                self?.onboardingWindow?.show()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }

    private func installMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "waveform.circle.fill",
            accessibilityDescription: "Hushword"
        )
        item.button?.target = self
        item.button?.action = #selector(togglePopover)

        let panel = NSPopover()
        panel.behavior = .transient
        panel.contentSize = NSSize(width: 380, height: 520)
        panel.contentViewController = NSHostingController(
            rootView: MenuBarView(
                model: model,
                openSettings: { [weak self, weak panel] in
                    guard let self, let panel else { return }
                    settingsWindow.showAfterClosingPopover(panel)
                }
            )
        )

        statusItem = item
        popover = panel
    }

    private func updatePresentation(_ presentation: DictationPresentation) {
        dictationHUD?.update(presentation)
        statusItem?.button?.image = NSImage(
            systemSymbolName: presentation.isRecording
                ? "waveform.circle.fill"
                : "waveform.circle",
            accessibilityDescription: presentation.isRecording
                ? "Hushword is listening"
                : "Hushword"
        )
        if !RecordingPresentationPolicy.shouldShowPopover(
            isRecording: presentation.isRecording
        ) {
            popover?.performClose(nil)
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.refreshPermissions()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
