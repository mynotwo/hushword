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
    package static let currentVersion = 2

    package static func shouldPresent(completedVersion: Int) -> Bool {
        completedVersion < currentVersion
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
