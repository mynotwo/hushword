import Carbon
import HushwordCore
import HushwordAppKit
import Foundation

extension DictationEngineTestRunner {
    static func routesLocalDictationAndAgentRewriteShortcutsIndependently() async throws {
        let local = GlobalHotKeyShortcut.localDictation
        let rewrite = GlobalHotKeyShortcut.agentRewrite

        guard local.keyCode == UInt32(kVK_Space),
              local.modifiers == UInt32(optionKey),
              local.action == .localDictation,
              rewrite.keyCode == UInt32(kVK_Space),
              rewrite.modifiers == UInt32(optionKey | shiftKey),
              rewrite.action == .agentRewrite,
              local.identifier != rewrite.identifier else {
            throw TestFailure(
                description: "local dictation and Agent rewrite shortcuts are not isolated"
            )
        }
    }

    static func defaultsOldSettingsToAutomaticAgentSelection() async throws {
        let data = Data(
            """
            {
              "autoPaste": true,
              "language": "zh-CN",
              "dictionaryText": "长心存储 = 长鑫存储"
            }
            """.utf8
        )
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        guard settings.agentPreference == .auto,
              settings.autoPaste,
              settings.language == "zh-CN",
              settings.dictionaryText == "长心存储 = 长鑫存储" else {
            throw TestFailure(
                description: "old settings did not retain values with Auto Agent"
            )
        }
    }

    static func presentsOnboardingOnceForLegacySettings() async throws {
        let data = Data(
            """
            {
              "autoPaste": true,
              "language": "zh-CN"
            }
            """.utf8
        )
        let legacySettings = try JSONDecoder().decode(
            AppSettings.self,
            from: data
        )
        let completedSettings = AppSettings(
            onboardingVersion: OnboardingPolicy.currentVersion
        )

        guard legacySettings.onboardingVersion == 0,
              OnboardingPolicy.shouldPresent(
                completedVersion: legacySettings.onboardingVersion
              ),
              !OnboardingPolicy.shouldPresent(
                completedVersion: completedSettings.onboardingVersion
              ) else {
            throw TestFailure(
                description: "first-run onboarding is not presented exactly once"
            )
        }
    }

    static func explainsWhenNoBringYourOwnAgentIsAvailable() async throws {
        let missing = AgentAvailabilityPolicy.status(
            preference: .auto,
            availableProviders: []
        )
        let codex = AgentAvailabilityPolicy.status(
            preference: .codex,
            availableProviders: [.codex]
        )

        guard missing.selectedProvider == nil,
              missing.detail.contains("Dictation still works"),
              missing.detail.contains("install"),
              codex.selectedProvider == .codex,
              codex.detail.contains("Codex"),
              codex.detail.contains("provider") else {
            throw TestFailure(
                description: "Agent dependency status is ambiguous"
            )
        }
    }

    static func acceptsOnlyCompleteAutomaticUpdateConfiguration() async throws {
        let complete = UpdateConfiguration(
            infoDictionary: [
                "SUFeedURL": "https://updates.example.com/appcast.xml",
                "SUPublicEDKey": "public-key",
            ]
        )
        let missingKey = UpdateConfiguration(
            infoDictionary: [
                "SUFeedURL": "https://updates.example.com/appcast.xml",
            ]
        )
        let insecure = UpdateConfiguration(
            infoDictionary: [
                "SUFeedURL": "http://updates.example.com/appcast.xml",
                "SUPublicEDKey": "public-key",
            ]
        )

        guard complete?.feedURL.absoluteString
                == "https://updates.example.com/appcast.xml",
              missingKey == nil,
              insecure == nil else {
            throw TestFailure(
                description: "automatic updates accepted incomplete release metadata"
            )
        }
    }

    static func acceptsOnlySecureProductSupportLinks() async throws {
        let links = ProductLinks(
            infoDictionary: [
                "HushwordSupportURL": "https://example.com/support",
                "HushwordPrivacyURL": "https://example.com/privacy",
            ]
        )
        let insecure = ProductLinks(
            infoDictionary: [
                "HushwordSupportURL": "http://example.com/support",
                "HushwordPrivacyURL": "https://example.com/privacy",
            ]
        )

        guard links?.supportURL.absoluteString
                == "https://example.com/support",
              links?.privacyURL.absoluteString
                == "https://example.com/privacy",
              insecure == nil else {
            throw TestFailure(
                description: "product links accepted incomplete or insecure metadata"
            )
        }
    }
}
