import HushwordCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Dictation") {
                Picker("Language", selection: $model.selectedLanguage) {
                    Text("中文（普通话）").tag("zh-CN")
                    Text("English (US)").tag("en-US")
                    Text("日本語").tag("ja-JP")
                    Text("한국어").tag("ko-KR")
                }
                Toggle("Insert into the active app automatically", isOn: $model.autoPaste)
                LabeledContent("Local dictation", value: "Tap Fn or ⌥ Space")
                LabeledContent(
                    "Fast rewrite last dictation",
                    value: "Hold Fn or ⌥⇧ Space"
                )
            }

            Section("Local transcription") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.whisperModelStatusText)
                        Text("The 574 MB Whisper model runs on this Mac. Apple Speech remains available while it downloads.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.isWhisperModelBusy {
                        ProgressView(
                            value: model.whisperModelDownloadProgress
                        )
                        .frame(width: 110)
                    } else if model.canPrepareWhisperModel {
                        Button(
                            model.whisperModelState.isFailure
                                ? "Retry" : "Download 574 MB"
                        ) {
                            model.prepareWhisperModel()
                        }
                    }
                }
            }

            Section("Personal dictionary") {
                Text("One replacement per line: spoken form = preferred spelling")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Direct edits after automatic paste can become local corrections; manual entries always win.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Repeated technical terms in history are used only as recognition hints. Clearing history clears those hints.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $model.personalDictionaryText)
                    .font(.body.monospaced())
                    .frame(minHeight: 180)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.quaternary)
                    )
            }

            Section("Optional AI rewrite") {
                Picker("Fn rewrite Agent", selection: $model.agentPreference) {
                    Text("Auto").tag(AgentPreference.auto)
                    Text("Claude").tag(AgentPreference.claude)
                    Text("Codex").tag(AgentPreference.codex)
                    Text("Coco").tag(AgentPreference.coco)
                    Text("Off").tag(AgentPreference.off)
                }
                Picker("Style", selection: $model.polishMode) {
                    Text("Natural").tag(AIPolishMode.natural)
                    Text("Concise").tag(AIPolishMode.concise)
                    Text("Professional").tag(AIPolishMode.professional)
                    Text("Casual").tag(AIPolishMode.casual)
                }
                LabeledContent(
                    model.agentAvailabilityStatus.title,
                    value: model.agentAvailabilityStatus.selectedProvider == nil
                        ? "Unavailable" : "Ready"
                )
                Text(model.agentAvailabilityStatus.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Agent rewrite is bring-your-own-Agent. The selected provider may receive the transcript. Slow or unavailable results never replace the original text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                Text("Microphone captures audio. Apple Speech may use Apple's speech service. Accessibility is required only for automatic paste.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent(
                    "Microphone",
                    value: model.microphonePermission.title
                )
                LabeledContent(
                    "Speech Recognition",
                    value: model.speechRecognitionPermission.title
                )
                LabeledContent(
                    "Automatic paste",
                    value: model.hasAccessibilityPermission ? "Enabled" : "Permission required"
                )
                if !model.hasAccessibilityPermission {
                    Button("Enable Automatic Paste") {
                        model.requestAccessibilityPermission()
                    }
                }
            }

            Section("Updates & privacy") {
                Button("Check for Updates…") {
                    model.checkForUpdates()
                }
                HStack {
                    Button("Support") {
                        model.openSupport()
                    }
                    Button("Privacy Policy") {
                        model.openPrivacyPolicy()
                    }
                }
                Text("Local Whisper audio and correction memory stay on this Mac. Apple Speech and optional Agent rewrite follow those providers' privacy terms.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent(
                    "Version",
                    value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"))"
                )
            }

            HStack {
                Spacer()
                Button("Save") {
                    model.saveSettings()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
}

private extension WhisperModelState {
    var isFailure: Bool {
        if case .failed = self {
            return true
        }
        return false
    }
}
