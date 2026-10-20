import SwiftUI

package struct FlowTypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    package init() {}

    package var body: some Scene {
        Settings { EmptyView() }
    }
}
