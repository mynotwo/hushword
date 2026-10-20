import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    let finish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "waveform")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 52, height: 52)
                    .background(
                        Color.accentColor.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                VStack(alignment: .leading, spacing: 5) {
                    Text("Welcome to Hushword")
                        .font(.title.weight(.semibold))
                    Text("Fast dictation where you already type.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }

            shortcutGuide

            VStack(alignment: .leading, spacing: 10) {
                Text("One-time permissions")
                    .font(.headline)
                permissionRow(
                    title: "Microphone",
                    detail: "Capture your voice",
                    state: model.microphonePermission,
                    action: model.requestMicrophonePermission
                )
                permissionRow(
                    title: "Speech Recognition",
                    detail: "Use Apple's speech recognizer when available",
                    state: model.speechRecognitionPermission,
                    action: model.requestSpeechRecognitionPermission
                )
                permissionRow(
                    title: "Accessibility",
                    detail: "Insert the transcript into the active app",
                    state: model.hasAccessibilityPermission
                        ? .granted : .notDetermined,
                    action: model.requestAccessibilityPermission
                )
            }

            localModel

            HStack {
                Text("Apple Speech may use Apple's service. Local Whisper runs on this Mac. Agent rewrite is optional and uses your chosen provider.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Start using Hushword") {
                    model.completeOnboarding()
                    finish()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 620)
    }

    private var shortcutGuide: some View {
        HStack(spacing: 0) {
            shortcut(
                key: "Fn",
                title: "Tap to dictate",
                detail: "Tap once to start, tap again to finish."
            )
            Divider()
                .padding(.vertical, 4)
            shortcut(
                key: "Fn",
                title: "Hold to rewrite",
                detail: "Optional. Requires your own signed-in Agent."
            )
        }
        .padding(.vertical, 14)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
    }

    private func shortcut(
        key: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(spacing: 12) {
            Text(key)
                .font(.headline.monospaced())
                .frame(width: 46, height: 34)
                .background(
                    Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.quaternary)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
    }

    private func permissionRow(
        title: String,
        detail: String,
        state: SystemPermissionState,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: state == .granted
                ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(state == .granted
                    ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if state == .granted {
                Text("Allowed")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                Button(state.title, action: action)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    private var localModel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Local high-accuracy model")
                        .font(.subheadline.weight(.semibold))
                    Text(model.whisperModelStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isWhisperModelBusy {
                    ProgressView(value: model.whisperModelDownloadProgress)
                        .frame(width: 110)
                } else if model.canPrepareWhisperModel {
                    Button("Download 574 MB") {
                        model.prepareWhisperModel()
                    }
                    .controlSize(.small)
                }
            }
            Text("Whisper improves private on-device recognition. You can continue with Apple Speech while it downloads.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            Color.green.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }
}
