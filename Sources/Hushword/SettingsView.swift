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
                LabeledContent("Start or stop", value: "Tap Fn or ⌥ Space")
                Toggle("Keep audio on this Mac", isOn: $model.keepAudioOnMac)
                Text(
                    model.keepAudioOnMac
                        ? "Apple Speech uses only on-device models. If your language has none, Whisper transcribes alone."
                        : "Apple Speech may send audio to Apple's servers for higher accuracy."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            Section("Permissions") {
                Text("Microphone captures audio. Speech Recognition enables Apple's recognizer. Accessibility is required only for automatic paste.")
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
                Text("Recordings, Whisper transcription, history, and correction memory stay on this Mac. Hushword has no account, analytics, or AI rewrite service.")
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
