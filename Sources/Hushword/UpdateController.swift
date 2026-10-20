import Foundation
import Sparkle

@MainActor
package final class UpdateController {
    private var updaterController: SPUStandardUpdaterController?
    private var observer: NSObjectProtocol?

    package init(
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) {
        guard UpdateConfiguration(infoDictionary: infoDictionary) != nil else {
            return
        }
        let updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.updaterController = updaterController
        observer = NotificationCenter.default.addObserver(
            forName: .hushwordCheckForUpdates,
            object: nil,
            queue: .main
        ) { [weak updaterController] _ in
            updaterController?.checkForUpdates(nil)
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
