import HushwordCore
import Foundation

package enum SystemPermissionState: Equatable {
    case notDetermined
    case granted
    case denied

    package var title: String {
        switch self {
        case .notDetermined:
            return "Not requested"
        case .granted:
            return "Allowed"
        case .denied:
            return "Open System Settings"
        }
    }
}

package enum OnboardingPolicy {
    package static let currentVersion = 1

    package static func shouldPresent(completedVersion: Int) -> Bool {
        completedVersion < currentVersion
    }
}

package struct AgentAvailabilityStatus: Equatable {
    package let selectedProvider: AIProvider?
    package let title: String
    package let detail: String
}

package enum AgentAvailabilityPolicy {
    package static func status(
        preference: AgentPreference,
        availableProviders: Set<AIProvider>
    ) -> AgentAvailabilityStatus {
        if preference == .off {
            return AgentAvailabilityStatus(
                selectedProvider: nil,
                title: "Agent rewrite is off",
                detail: "Dictation still works without an Agent."
            )
        }

        let selectedProvider: AIProvider?
        switch preference {
        case .auto:
            selectedProvider = [.claude, .codex, .coco].first(
                where: availableProviders.contains
            )
        case .claude:
            selectedProvider = availableProviders.contains(.claude)
                ? .claude : nil
        case .codex:
            selectedProvider = availableProviders.contains(.codex)
                ? .codex : nil
        case .coco:
            selectedProvider = availableProviders.contains(.coco)
                ? .coco : nil
        case .off:
            selectedProvider = nil
        }

        if let selectedProvider {
            let name = selectedProvider.displayName
            return AgentAvailabilityStatus(
                selectedProvider: selectedProvider,
                title: "\(name) detected",
                detail: "\(name) is a third-party provider. Hushword uses your existing installation and account for optional rewrites."
            )
        }

        let requestedName: String?
        switch preference {
        case .auto, .off:
            requestedName = nil
        case .claude:
            requestedName = "Claude"
        case .codex:
            requestedName = "Codex"
        case .coco:
            requestedName = "Coco"
        }
        return AgentAvailabilityStatus(
            selectedProvider: nil,
            title: requestedName.map { "\($0) not detected" }
                ?? "No Agent detected",
            detail: "Dictation still works without an Agent. To use Hold Fn, install and sign in to \(requestedName ?? "Claude, Codex, or Coco")."
        )
    }
}

package struct UpdateConfiguration: Equatable {
    package let feedURL: URL
    package let publicKey: String

    package init?(infoDictionary: [String: Any]) {
        guard let feed = infoDictionary["SUFeedURL"] as? String,
              let feedURL = URL(string: feed),
              feedURL.scheme?.lowercased() == "https",
              let publicKey = infoDictionary["SUPublicEDKey"] as? String,
              !publicKey.trimmingCharacters(
                in: .whitespacesAndNewlines
              ).isEmpty else {
            return nil
        }
        self.feedURL = feedURL
        self.publicKey = publicKey
    }
}

package struct ProductLinks: Equatable {
    package let supportURL: URL
    package let privacyURL: URL

    package init?(infoDictionary: [String: Any]) {
        guard let support = Self.secureURL(
            for: "HushwordSupportURL",
            in: infoDictionary
        ),
        let privacy = Self.secureURL(
            for: "HushwordPrivacyURL",
            in: infoDictionary
        ) else {
            return nil
        }
        supportURL = support
        privacyURL = privacy
    }

    private static func secureURL(
        for key: String,
        in infoDictionary: [String: Any]
    ) -> URL? {
        guard let value = infoDictionary[key] as? String,
              let url = URL(string: value),
              url.scheme?.lowercased() == "https" else {
            return nil
        }
        return url
    }
}

private extension AIProvider {
    var displayName: String {
        switch self {
        case .none:
            return "Agent"
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        case .coco:
            return "Coco"
        }
    }
}
