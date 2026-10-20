import AppKit
import HushwordCore

@MainActor
final class PasteTargetTracker {
    private let workspace: NSWorkspace
    private var selector: TargetApplicationSelector
    private var observer: NSObjectProtocol?

    private(set) var application: NSRunningApplication?

    init(
        workspace: NSWorkspace = .shared,
        ownProcessIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier
    ) {
        self.workspace = workspace
        selector = TargetApplicationSelector(
            ownProcessIdentifier: ownProcessIdentifier
        )
        observe(workspace.frontmostApplication)
        observer = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey
            ] as? NSRunningApplication else {
                return
            }
            Task { @MainActor in
                self?.observe(application)
            }
        }
    }

    deinit {
        if let observer {
            workspace.notificationCenter.removeObserver(observer)
        }
    }

    func lock() {
        observe(workspace.frontmostApplication)
        selector.lockSelection()
    }

    func unlock() {
        selector.unlockSelection()
        observe(workspace.frontmostApplication)
    }

    private func observe(_ candidate: NSRunningApplication?) {
        guard let candidate else { return }
        let accepted = selector.observe(
            processIdentifier: candidate.processIdentifier,
            isRegularApplication: candidate.activationPolicy == .regular,
            isTerminated: candidate.isTerminated
        )
        if accepted {
            application = candidate
        }
    }
}
