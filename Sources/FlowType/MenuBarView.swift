import FlowTypeCore
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if model.autoPaste && !model.hasAccessibilityPermission {
                accessibilityBanner
            }
            recordCard
            transcriptCard
            historySection
            footer
        }
        .padding(18)
        .frame(width: 380, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("FlowType")
                    .font(.title2.weight(.bold))
                Text("Speak naturally. Type anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Tap Fn  Dictate")
                Text("Hold Fn  Rewrite last")
            }
            .font(.caption2.monospaced())
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
        }
    }

    private var accessibilityBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("One-time setup for automatic paste")
                .font(.subheadline.weight(.semibold))
            Text("Allow FlowType in Privacy & Security → Accessibility. Transcripts are still copied even without this permission.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Enable Automatic Paste") {
                model.requestAccessibilityPermission()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private var recordCard: some View {
        Button {
            model.toggleRecording()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: model.isRecording ? "stop.fill" : "mic.fill")
                    .font(.title2)
                    .frame(width: 38, height: 38)
                    .foregroundStyle(.white)
                    .background(
                        model.isRecording ? Color.red : Color.accentColor,
                        in: Circle()
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.isRecording ? "Stop & insert" : "Start dictation")
                        .font(.headline)
                    Text(model.statusTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.isRecording ? "Recording" : "Last output")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !model.lastOutput.isEmpty {
                    Button("Copy") { model.copyLastOutput() }
                        .buttonStyle(.link)
                }
            }
            Text(displayedText)
                .font(.body)
                .foregroundStyle(displayedText.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
                .textSelection(.enabled)
            if !model.lastOutput.isEmpty {
                HStack(spacing: 8) {
                    if let provider = model.aiRewriteProvider {
                        ProgressView()
                            .controlSize(.small)
                        Text("\(provider.displayName) is rewriting…")
                            .font(.caption)
                        Spacer()
                        Button("Cancel") {
                            model.cancelAIRewrite()
                        }
                    } else {
                        Button("Claude rewrite") {
                            model.rewriteLastOutput(with: .claude)
                        }
                        Button("Coco rewrite") {
                            model.rewriteLastOutput(with: .coco)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Text(
                    model.isAIRewriting
                        ? "Fn rewrite stops within three seconds; manual rewrites can take longer."
                        : "Fn uses your selected Agent; slow results never replace the original."
                )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private var displayedText: String {
        if model.isRecording {
            return "Start speaking…"
        }
        return model.lastOutput.isEmpty ? "Your dictation appears here." : model.lastOutput
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent")
                    .font(.headline)
                Spacer()
                if !model.history.isEmpty {
                    Button("Clear") { model.clearHistory() }
                        .buttonStyle(.link)
                }
            }
            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(model.history.prefix(8)) { item in
                        Button {
                            model.copyHistoryItem(item)
                        } label: {
                            HStack {
                                Text(item.text)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "doc.on.doc")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Button("Settings…", action: openSettings)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .buttonStyle(.link)
    }
}

private extension AIProvider {
    var displayName: String {
        switch self {
        case .none: return "AI"
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .coco: return "Coco"
        }
    }
}
