import AppKit
import AVFoundation
import Combine
import FlowTypeCore
import Foundation
import Speech

package enum AppStatus: Equatable {
    case idle
    case requestingPermission
    case listening
    case processing
    case success
    case copied(String)
    case error(String)

    package var lifecycleState: DictationLifecycleState {
        switch self {
        case .idle:
            return .idle
        case .requestingPermission:
            return .requestingPermission
        case .listening:
            return .listening
        case .processing:
            return .processing
        case .success, .copied:
            return .success
        case .error:
            return .failure
        }
    }

    package var title: String {
        switch self {
        case .idle:
            return "Ready"
        case .requestingPermission:
            return "Requesting permission…"
        case .listening:
            return "Listening…"
        case .processing:
            return "Transcribing…"
        case .success:
            return "Inserted"
        case .copied(let message), .error(let message):
            return message
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var status: AppStatus = .idle {
        didSet {
            publishPresentation()
        }
    }
    @Published private(set) var audioLevel = 0.0 {
        didSet {
            publishPresentation()
        }
    }
    @Published private(set) var lastOutput = ""
    @Published private(set) var history: [HistoryItem] = []
    @Published private(set) var aiRewriteProvider: AIProvider? {
        didSet {
            publishPresentation()
        }
    }
    @Published private(set) var hasAccessibilityPermission = false
    @Published private(set) var whisperModelState: WhisperModelState = .notInstalled
    @Published private(set) var microphonePermission: SystemPermissionState = .notDetermined
    @Published private(set) var speechRecognitionPermission: SystemPermissionState = .notDetermined
    @Published private(set) var availableAgentProviders = Set<AIProvider>()
    @Published private(set) var onboardingVersion = 0
    @Published var autoPaste = true
    @Published var selectedLanguage = "zh-CN"
    @Published var personalDictionaryText = ""
    @Published var polishMode: AIPolishMode = .natural
    @Published var agentPreference = AgentPreference.auto

    var onPresentationChanged: ((DictationPresentation) -> Void)? {
        didSet {
            publishPresentation()
        }
    }

    private let dictationEngine = DictationEngine()
    private let inserter = TextInserter()
    private let store = AppStore()
    private let aiRewriteService = AIRewriteService()
    private let pasteTarget = PasteTargetTracker()
    private let whisperModelManager = WhisperModelManager()
    private let endToEndTimingStore = EndToEndTimingStore()
    private let timingClock = ContinuousClock()
    private var startRecordingTask: Task<Bool, Never>?
    private var deferredRecordingStart = DeferredRecordingStart()
    private var activeDictationContext: DictationContext?
    private var lastInsertionObservation: CorrectionObservation?
    private var endToEndTimingSession: EndToEndTimingSession?
    private var learnedCorrections: [LearnedCorrection] = []
    private var correctionObservationTask: Task<Void, Never>?
    private var aiRewriteTask: Task<Void, Never>?
    private var fastRewritePreparationTask: Task<Void, Never>?
    private var readyFastRewriteProviders = Set<AIProvider>()
    private var aiRewriteRequestID: UUID?
    private var cancellables = Set<AnyCancellable>()

    init() {
        let settings = store.loadSettings()
        autoPaste = settings.autoPaste
        selectedLanguage = settings.language
        personalDictionaryText = settings.dictionaryText
        agentPreference = settings.agentPreference
        onboardingVersion = settings.onboardingVersion
        history = store.loadHistory()
        lastOutput = history.first?.text ?? ""
        learnedCorrections = store.loadLearnedCorrections()
        hasAccessibilityPermission = inserter.hasAccessibilityPermission
        refreshPermissions()
        refreshAgentAvailability()
        whisperModelState = whisperModelManager.state
        whisperModelManager.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.whisperModelState = state
            }
            .store(in: &cancellables)
        whisperModelManager.$downloadProgress
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        whisperModelManager.prepareIfNeeded()
        prepareFastRewrite()
    }

    var isRecording: Bool {
        presentation.isRecording
    }

    var isAIRewriting: Bool {
        aiRewriteProvider != nil
    }

    var whisperModelStatusText: String {
        whisperModelManager.statusText
    }

    var whisperModelDownloadProgress: Double? {
        whisperModelManager.downloadProgress
    }

    var agentAvailabilityStatus: AgentAvailabilityStatus {
        AgentAvailabilityPolicy.status(
            preference: agentPreference,
            availableProviders: availableAgentProviders
        )
    }

    var shouldPresentOnboarding: Bool {
        OnboardingPolicy.shouldPresent(
            completedVersion: onboardingVersion
        )
    }

    var isWhisperModelBusy: Bool {
        switch whisperModelState {
        case .downloading, .verifying:
            return true
        case .notInstalled, .ready, .failed:
            return false
        }
    }

    var canPrepareWhisperModel: Bool {
        switch whisperModelState {
        case .notInstalled, .failed:
            return true
        case .downloading, .verifying, .ready:
            return false
        }
    }

    private var lifecycleState: DictationLifecycleState {
        status.lifecycleState
    }

    private var presentation: DictationPresentation {
        DictationPresentation(
            lifecycleState: lifecycleState,
            audioLevel: audioLevel,
            isAIRewriting: isAIRewriting
        )
    }

    private func publishPresentation() {
        onPresentationChanged?(presentation)
    }

    var statusTitle: String {
        if let aiRewriteProvider {
            return "\(aiRewriteProvider.rawValue.capitalized) rewriting…"
        }
        return status.title
    }

    func toggleRecording() {
        guard !isAIRewriting else { return }
        switch DictationControlPolicy.toggleAction(for: lifecycleState) {
        case .start:
            startRecording()
        case .stop:
            stopRecording()
        case .startWhenReady:
            deferredRecordingStart.toggle()
        }
    }

    func startRecording() {
        let context = currentDictationContext
        activeDictationContext = context
        endToEndTimingSession = EndToEndTimingSession(
            startActionAt: timingClock.now,
            autoPaste: autoPaste
        )
        pasteTarget.lock()
        audioLevel = 0
        status = .requestingPermission

        startRecordingTask?.cancel()
        startRecordingTask = Task { [weak self] in
            guard let self else { return false }
            do {
                try await dictationEngine.start(
                    localeIdentifier: selectedLanguage,
                    context: context,
                    onAudioLevel: { [weak self] level in
                        guard let self, self.isRecording else { return }
                        self.audioLevel = AudioLevelPolicy.smoothedLevel(
                            previous: self.audioLevel,
                            current: level
                        )
                    }
                )
                guard !Task.isCancelled else { return false }
                if status == .requestingPermission {
                    status = .listening
                    endToEndTimingSession?.listeningAt = timingClock.now
                }
                return true
            } catch {
                let completionOwnedByStop = status == .processing
                audioLevel = 0
                status = .error(error.localizedDescription)
                activeDictationContext = nil
                finishEndToEndTiming(outcome: .failed)
                if !completionOwnedByStop {
                    completeRecordingSession()
                }
                return false
            }
        }
    }

    func stopRecording() {
        endToEndTimingSession?.stopActionAt = timingClock.now
        endToEndTimingSession?.autoPaste = autoPaste
        let context = activeDictationContext ?? currentDictationContext
        activeDictationContext = nil
        audioLevel = 0
        status = .processing

        Task {
            let captureStarted = await startRecordingTask?.value ?? true
            startRecordingTask = nil
            guard captureStarted else {
                finishEndToEndTiming(outcome: .failed)
                if status == .processing {
                    status = .idle
                }
                completeRecordingSession()
                return
            }
            let finalTranscript = await dictationEngine.finish(
                context: context
            )
            endToEndTimingSession?.recognitionReadyAt = timingClock.now
            await finishRecording(with: finalTranscript)
        }
    }

    private func finishRecording(with finalTranscript: String) async {
        guard !finalTranscript.isEmpty else {
            status = .idle
            finishEndToEndTiming(outcome: .noText)
            completeRecordingSession()
            return
        }

        lastOutput = finalTranscript
        recordHistory(finalTranscript)
        lastInsertionObservation = nil

        let shouldAutoPaste = autoPaste
        endToEndTimingSession?.autoPaste = shouldAutoPaste
        if shouldAutoPaste {
            let attempt = await inserter.insert(
                finalTranscript,
                into: pasteTarget.application
            )
            hasAccessibilityPermission = inserter.hasAccessibilityPermission
            switch attempt.result {
            case .pasted:
                status = .success
                lastInsertionObservation = attempt.correctionObservation
                observeCorrection(from: attempt.correctionObservation)
                finishEndToEndTiming(
                    outcome: .pasted,
                    insertionMetrics: attempt.metrics,
                    textDelivered: true
                )
            case .copiedAccessibilityPermissionRequired:
                status = .copied("Copied. Enable Accessibility to auto-paste.")
                finishEndToEndTiming(
                    outcome: .copied,
                    insertionMetrics: attempt.metrics,
                    textDelivered: true
                )
            case .copiedTargetUnavailable:
                status = .copied("Copied. Return to a text field and try again.")
                finishEndToEndTiming(
                    outcome: .copied,
                    insertionMetrics: attempt.metrics,
                    textDelivered: true
                )
            case .copyFailed:
                status = .error("Could not copy the transcript.")
                finishEndToEndTiming(
                    outcome: .failed,
                    insertionMetrics: attempt.metrics
                )
            }
        } else {
            if inserter.copy(finalTranscript) {
                status = .copied("Copied to clipboard.")
                finishEndToEndTiming(outcome: .copied, textDelivered: true)
            } else {
                status = .error("Could not copy the transcript.")
                finishEndToEndTiming(outcome: .failed)
            }
        }

        if completeRecordingSession() {
            return
        }
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        if status == .success {
            status = .idle
        }
    }

    func shutdown() {
        startRecordingTask?.cancel()
        startRecordingTask = nil
        correctionObservationTask?.cancel()
        correctionObservationTask = nil
        aiRewriteTask?.cancel()
        aiRewriteTask = nil
        fastRewritePreparationTask?.cancel()
        fastRewritePreparationTask = nil
        Task { [aiRewriteService] in
            await aiRewriteService.shutdownFastRewrite()
        }
        aiRewriteRequestID = nil
        aiRewriteProvider = nil
        activeDictationContext = nil
        lastInsertionObservation = nil
        deferredRecordingStart.consume()
        pasteTarget.unlock()
        dictationEngine.shutdown()
    }

    func copyLastOutput() {
        guard !lastOutput.isEmpty else { return }
        inserter.copy(lastOutput)
    }

    func copyHistoryItem(_ item: HistoryItem) {
        inserter.copy(item.text)
    }

    func rewriteLastOutput(with provider: AIProvider) {
        rewriteLastOutput(with: provider, replacingLastInsertion: false)
    }

    @discardableResult
    func rewriteAndReplaceLastOutput() -> Bool {
        guard canRewriteLastOutput else {
            return false
        }
        guard let provider = selectedAgentProvider else {
            status = .error(agentAvailabilityStatus.detail)
            return false
        }
        rewriteLastOutput(
            with: provider,
            replacingLastInsertion: true
        )
        return true
    }

    private var selectedAgentProvider: AIProvider? {
        AgentProviderSelection.resolve(
            preference: agentPreference,
            availableProviders: aiRewriteService.availableProviders(),
            readyProviders: readyFastRewriteProviders
        )
    }

    private var canRewriteLastOutput: Bool {
        !lastOutput.isEmpty
            && !isRecording
            && status != .processing
            && !isAIRewriting
    }

    private func rewriteLastOutput(
        with provider: AIProvider,
        replacingLastInsertion: Bool
    ) {
        guard canRewriteLastOutput else { return }
        let requestID = UUID()
        let sourceText = lastOutput
        let mode = polishMode
        let observation = replacingLastInsertion
            ? lastInsertionObservation
            : nil
        let timeoutNanoseconds = replacingLastInsertion
            ? AgentRewritePolicy.longPressTimeoutNanoseconds
            : nil
        aiRewriteRequestID = requestID
        aiRewriteProvider = provider

        aiRewriteTask = Task { [weak self] in
            guard let self else { return }
            defer {
                finishAIRewrite(requestID: requestID)
            }
            do {
                let rewritten: String
                if replacingLastInsertion,
                   provider == .claude || provider == .codex,
                   let timeoutNanoseconds {
                    rewritten = try await aiRewriteService.rewriteFast(
                        sourceText,
                        with: provider,
                        mode: mode,
                        timeoutNanoseconds: timeoutNanoseconds
                    )
                } else {
                    rewritten = try await aiRewriteService.rewrite(
                        sourceText,
                        with: provider,
                        mode: mode,
                        timeoutNanoseconds: timeoutNanoseconds
                    )
                }
                guard !Task.isCancelled,
                      aiRewriteRequestID == requestID else {
                    return
                }
                lastOutput = rewritten
                recordHistory(rewritten)
                if replacingLastInsertion {
                    correctionObservationTask?.cancel()
                    correctionObservationTask = nil
                    let attempt = await inserter.replace(
                        rewritten,
                        using: observation
                    )
                    switch attempt.result {
                    case .pasted:
                        lastInsertionObservation = nil
                        status = .success
                    case .copiedAccessibilityPermissionRequired:
                        status = .copied(
                            "Copied. Enable Accessibility to replace the last dictation."
                        )
                    case .copiedTargetUnavailable:
                        status = .copied(
                            "Copied. The last dictation was not replaced."
                        )
                    case .copyFailed:
                        status = .error("Could not copy the rewrite.")
                    }
                } else {
                    inserter.copy(rewritten)
                    status = .success
                }
            } catch is CancellationError {
            } catch {
                if aiRewriteRequestID == requestID {
                    status = .error(error.localizedDescription)
                }
                if replacingLastInsertion {
                    prepareFastRewrite(provider: provider)
                }
            }
        }
    }

    private func prepareFastRewrite(
        provider: AIProvider? = nil,
        resetSession: Bool = false
    ) {
        guard fastRewritePreparationTask == nil else { return }
        fastRewritePreparationTask = Task { [weak self] in
            guard let self else { return }
            if resetSession {
                await aiRewriteService.shutdownFastRewrite()
                guard !Task.isCancelled else { return }
                readyFastRewriteProviders.removeAll()
            }
            let availableProviders = aiRewriteService.availableProviders()
            let providers: [AIProvider]
            if let provider {
                providers = [provider]
            } else {
                switch agentPreference {
                case .auto:
                    providers = [.claude, .codex]
                        .filter(availableProviders.contains)
                case .claude:
                    providers = [.claude]
                case .codex:
                    providers = [.codex]
                case .coco, .off:
                    providers = []
                }
            }
            for provider in providers where availableProviders.contains(
                provider
            ) {
                if await aiRewriteService.prepareFastRewrite(
                    provider: provider
                ) {
                    readyFastRewriteProviders.insert(provider)
                    if agentPreference == .auto {
                        break
                    }
                } else {
                    readyFastRewriteProviders.remove(provider)
                }
            }
            guard !Task.isCancelled else { return }
            fastRewritePreparationTask = nil
        }
    }

    private func finishAIRewrite(requestID: UUID) {
        guard aiRewriteRequestID == requestID else { return }
        aiRewriteRequestID = nil
        aiRewriteProvider = nil
        aiRewriteTask = nil
        let completedStatus = status
        switch completedStatus {
        case .success, .copied, .error:
            break
        case .idle, .requestingPermission, .listening, .processing:
            return
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let self,
                  aiRewriteProvider == nil,
                  status == completedStatus else {
                return
            }
            status = .idle
        }
    }

    func cancelAIRewrite() {
        aiRewriteTask?.cancel()
        aiRewriteTask = nil
        aiRewriteRequestID = nil
        aiRewriteProvider = nil
        status = .idle
    }

    func clearHistory() {
        history = []
        store.saveHistory([])
    }

    func saveSettings() {
        store.saveSettings(
            AppSettings(
                autoPaste: autoPaste,
                language: selectedLanguage,
                dictionaryText: personalDictionaryText,
                agentPreference: agentPreference,
                onboardingVersion: onboardingVersion
            )
        )
        refreshAgentAvailability()
        fastRewritePreparationTask?.cancel()
        fastRewritePreparationTask = nil
        prepareFastRewrite(resetSession: true)
    }

    func requestAccessibilityPermission() {
        guard AutomaticPastePermissionPolicy.shouldRequest(for: .userInitiated) else {
            return
        }
        inserter.requestAccessibilityPermission()
        Task {
            for _ in 0..<120 {
                if inserter.hasAccessibilityPermission {
                    hasAccessibilityPermission = true
                    return
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    func refreshPermissions() {
        hasAccessibilityPermission = inserter.hasAccessibilityPermission
        microphonePermission = Self.microphonePermissionState
        speechRecognitionPermission = Self.speechRecognitionPermissionState
    }

    func prepareWhisperModel() {
        whisperModelManager.prepareIfNeeded()
    }

    func requestMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshPermissions()
                }
            }
        case .denied, .restricted:
            openSystemSettings("Privacy_Microphone")
        case .authorized:
            refreshPermissions()
        @unknown default:
            refreshPermissions()
        }
    }

    func requestSpeechRecognitionPermission() {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { [weak self] _ in
                Task { @MainActor in
                    self?.refreshPermissions()
                }
            }
        case .denied, .restricted:
            openSystemSettings("Privacy_SpeechRecognition")
        case .authorized:
            refreshPermissions()
        @unknown default:
            refreshPermissions()
        }
    }

    func completeOnboarding() {
        onboardingVersion = OnboardingPolicy.currentVersion
        saveSettings()
    }

    func refreshAgentAvailability() {
        availableAgentProviders = aiRewriteService.availableProviders()
    }

    func checkForUpdates() {
        guard UpdateConfiguration(
            infoDictionary: Bundle.main.infoDictionary ?? [:]
        ) != nil else {
            status = .error(
                "Automatic updates are not configured in this build."
            )
            return
        }
        NotificationCenter.default.post(
            name: .flowTypeCheckForUpdates,
            object: nil
        )
    }

    func openSupport() {
        guard let links = ProductLinks(
            infoDictionary: Bundle.main.infoDictionary ?? [:]
        ) else { return }
        NSWorkspace.shared.open(links.supportURL)
    }

    func openPrivacyPolicy() {
        guard let links = ProductLinks(
            infoDictionary: Bundle.main.infoDictionary ?? [:]
        ) else { return }
        NSWorkspace.shared.open(links.privacyURL)
    }

    private func openSystemSettings(_ pane: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func recordHistory(_ text: String) {
        history.insert(
            HistoryItem(text: text, createdAt: Date()),
            at: 0
        )
        history = Array(history.prefix(50))
        store.saveHistory(history)
    }

    private func observeCorrection(
        from observation: CorrectionObservation?
    ) {
        correctionObservationTask?.cancel()
        guard let observation else {
            correctionObservationTask = nil
            return
        }
        correctionObservationTask = Task { [weak self] in
            guard let self,
                  let correction = await observation.waitForCorrection(),
                  !Task.isCancelled else {
                return
            }
            let updated = CorrectionMemoryPolicy.updating(
                correction,
                in: learnedCorrections,
                manualDictionaryText: personalDictionaryText
            )
            guard updated != learnedCorrections else { return }
            learnedCorrections = updated
            store.saveLearnedCorrections(updated)
        }
    }

    private func finishEndToEndTiming(
        outcome: EndToEndTimingOutcome,
        insertionMetrics: TextInsertionMetrics? = nil,
        textDelivered: Bool = false
    ) {
        guard let session = endToEndTimingSession else { return }
        endToEndTimingSession = nil
        let completedAt = timingClock.now
        let record = EndToEndTimingRecord(
            startToListeningMilliseconds: durationMilliseconds(
                from: session.startActionAt,
                to: session.listeningAt
            ),
            stopToRecognitionReadyMilliseconds: durationMilliseconds(
                from: session.stopActionAt,
                to: session.recognitionReadyAt
            ),
            targetActivationMilliseconds:
                insertionMetrics?.activationMilliseconds,
            pasteMilliseconds: insertionMetrics.map {
                max(0, $0.totalMilliseconds - $0.activationMilliseconds)
            },
            stopToTextDeliveredMilliseconds: textDelivered
                ? durationMilliseconds(
                    from: session.stopActionAt,
                    to: completedAt
                )
                : nil,
            autoPaste: session.autoPaste,
            outcome: outcome
        )
        endToEndTimingStore.enqueue(record)
    }

    @discardableResult
    private func completeRecordingSession() -> Bool {
        pasteTarget.unlock()
        guard deferredRecordingStart.consume() else { return false }
        startRecording()
        return true
    }

    private func durationMilliseconds(
        from start: ContinuousClock.Instant?,
        to end: ContinuousClock.Instant?
    ) -> Int64? {
        guard let start, let end else { return nil }
        let components = start.duration(to: end).components
        guard components.seconds >= 0, components.attoseconds >= 0 else {
            return 0
        }
        let (seconds, overflow) = components.seconds.multipliedReportingOverflow(
            by: 1_000
        )
        guard !overflow else { return Int64.max }
        let milliseconds = components.attoseconds / 1_000_000_000_000_000
        let (total, additionOverflow) = seconds.addingReportingOverflow(
            milliseconds
        )
        return additionOverflow ? Int64.max : total
    }

    private var currentDictationContext: DictationContext {
        DictationContext(
            personalDictionaryText: personalDictionaryText,
            learnedCorrections: learnedCorrections,
            historyTexts: history.map(\.text)
        )
    }

    private static var microphonePermissionState: SystemPermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }

    private static var speechRecognitionPermissionState: SystemPermissionState {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }
}

extension Notification.Name {
    static let flowTypeCheckForUpdates = Notification.Name(
        "FlowTypeCheckForUpdates"
    )
}

private struct EndToEndTimingSession {
    let startActionAt: ContinuousClock.Instant
    var listeningAt: ContinuousClock.Instant?
    var stopActionAt: ContinuousClock.Instant?
    var recognitionReadyAt: ContinuousClock.Instant?
    var autoPaste: Bool
}

struct HistoryItem: Codable, Identifiable, Hashable {
    let id: UUID
    let text: String
    let createdAt: Date

    init(id: UUID = UUID(), text: String, createdAt: Date) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

package struct AppSettings: Codable {
    package var autoPaste = true
    package var language = "zh-CN"
    package var dictionaryText = ""
    package var agentPreference = AgentPreference.auto
    package var onboardingVersion = 0

    package init(
        autoPaste: Bool = true,
        language: String = "zh-CN",
        dictionaryText: String = "",
        agentPreference: AgentPreference = .auto,
        onboardingVersion: Int = 0
    ) {
        self.autoPaste = autoPaste
        self.language = language
        self.dictionaryText = dictionaryText
        self.agentPreference = agentPreference
        self.onboardingVersion = onboardingVersion
    }

    private enum CodingKeys: String, CodingKey {
        case autoPaste
        case language
        case dictionaryText
        case agentPreference
        case onboardingVersion
    }

    package init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        autoPaste = try values.decodeIfPresent(
            Bool.self,
            forKey: .autoPaste
        ) ?? true
        language = try values.decodeIfPresent(
            String.self,
            forKey: .language
        ) ?? "zh-CN"
        dictionaryText = try values.decodeIfPresent(
            String.self,
            forKey: .dictionaryText
        ) ?? ""
        agentPreference = try values.decodeIfPresent(
            AgentPreference.self,
            forKey: .agentPreference
        ) ?? .auto
        onboardingVersion = try values.decodeIfPresent(
            Int.self,
            forKey: .onboardingVersion
        ) ?? 0
    }
}
