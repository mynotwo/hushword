import HushwordCore

let interactionPolicyTests: [(String, () throws -> Void)] = [
    ("uses a short Fn press for dictation", {
        var state = FunctionKeyClickState()
        guard state.consume(
            functionPressed: true,
            hasOtherModifiers: false
        ) == .startedPress,
        state.consume(
            functionPressed: false,
            hasOtherModifiers: false
        ) == .shortPress else {
            throw TestFailure(description: "short Fn press did not toggle dictation")
        }
    }),
    ("uses a long Fn press only for Agent rewrite", {
        var state = FunctionKeyClickState()
        guard state.consume(
            functionPressed: true,
            hasOtherModifiers: false
        ) == .startedPress,
        state.consumeLongPress() == .longPress,
        state.consume(
            functionPressed: false,
            hasOtherModifiers: false
        ) == .none else {
            throw TestFailure(description: "long Fn press also toggled dictation")
        }
    }),
    ("falls back to a short Fn press when long press is unavailable", {
        var state = FunctionKeyClickState()
        guard state.consume(
            functionPressed: true,
            hasOtherModifiers: false
        ) == .startedPress,
        state.consumeLongPress() == .longPress else {
            throw TestFailure(description: "Fn long press was not recognized")
        }
        state.cancelLongPress()
        guard state.consume(
            functionPressed: false,
            hasOtherModifiers: false
        ) == .shortPress else {
            throw TestFailure(
                description: "unavailable Fn long press swallowed dictation"
            )
        }
    }),
    ("recovers Fn after its event stream is interrupted", {
        var state = FunctionKeyClickState()
        guard state.consume(
            functionPressed: true,
            hasOtherModifiers: false
        ) == .startedPress else {
            throw TestFailure(description: "initial Fn press was lost")
        }
        state.reset()
        guard state.consume(
            functionPressed: true,
            hasOtherModifiers: false
        ) == .startedPress else {
            throw TestFailure(
                description: "Fn remained stuck after event tap recovery"
            )
        }
    }),
    ("ignores Fn modifier combinations", {
        var state = FunctionKeyClickState()
        guard state.consume(
            functionPressed: true,
            hasOtherModifiers: true
        ) == .none,
        state.consume(
            functionPressed: false,
            hasOtherModifiers: false
        ) == .none else {
            throw TestFailure(description: "Fn combination incorrectly toggled dictation")
        }
    }),
    ("keeps the recording presentation out of a popover", {
        guard RecordingPresentationPolicy.shouldShowPopover(isRecording: true) == false,
              RecordingPresentationPolicy.shouldShowPopover(isRecording: false) else {
            throw TestFailure(description: "recording presentation left a popover visible")
        }
    }),
    ("maps dictation lifecycle to a continuous compact HUD", {
        guard RecordingPresentationPolicy.hudPhase(for: .idle) == .hidden,
              RecordingPresentationPolicy.hudPhase(for: .requestingPermission) == .listening,
              RecordingPresentationPolicy.hudPhase(for: .listening) == .listening,
              RecordingPresentationPolicy.hudPhase(for: .processing) == .processing,
              RecordingPresentationPolicy.hudPhase(for: .success) == .success,
              RecordingPresentationPolicy.hudPhase(for: .failure) == .failure else {
            throw TestFailure(description: "dictation lifecycle did not map to the expected HUD")
        }
    }),
    ("publishes one consistent presentation snapshot", {
        let listening = DictationPresentation(
            lifecycleState: .listening,
            audioLevel: 1.5,
            isAIRewriting: false
        )
        let processing = DictationPresentation(
            lifecycleState: .processing,
            audioLevel: 1,
            isAIRewriting: false
        )
        let rewriting = DictationPresentation(
            lifecycleState: .idle,
            audioLevel: 0,
            isAIRewriting: true
        )
        guard listening.isRecording,
              listening.hudPhase == .listening,
              listening.audioLevel == 1,
              processing.isRecording == false,
              processing.hudPhase == .processing,
              processing.audioLevel == 0,
              rewriting.isRecording == false,
              rewriting.hudPhase == .processing else {
            throw TestFailure(description: "presentation fields can drift out of sync")
        }
    }),
    ("queues the next recording while finalizing", {
        guard DictationControlPolicy.toggleAction(for: .idle) == .start,
              DictationControlPolicy.toggleAction(for: .requestingPermission) == .stop,
              DictationControlPolicy.toggleAction(for: .listening) == .stop,
              DictationControlPolicy.toggleAction(for: .processing)
                == .startWhenReady,
              DictationControlPolicy.toggleAction(for: .success) == .start,
              DictationControlPolicy.toggleAction(for: .failure) == .start else {
            throw TestFailure(
                description: "next dictation was discarded while finalizing"
            )
        }
    }),
    ("toggles and consumes one deferred recording start", {
        var deferredStart = DeferredRecordingStart()
        guard deferredStart.toggle(),
              deferredStart.isPending,
              deferredStart.toggle() == false,
              deferredStart.isPending == false,
              deferredStart.consume() == false else {
            throw TestFailure(
                description: "a second Fn press did not cancel the deferred start"
            )
        }

        guard deferredStart.toggle(),
              deferredStart.consume(),
              deferredStart.isPending == false,
              deferredStart.consume() == false else {
            throw TestFailure(
                description: "the deferred start was not consumed exactly once"
            )
        }
    }),
    ("keeps the last external target when Hushword becomes active", {
        var selector = TargetApplicationSelector(ownProcessIdentifier: 100)
        guard selector.observe(
            processIdentifier: 200,
            isRegularApplication: true,
            isTerminated: false
        ),
        selector.selectedProcessIdentifier == 200 else {
            throw TestFailure(description: "external target was not remembered")
        }

        guard selector.observe(
            processIdentifier: 100,
            isRegularApplication: false,
            isTerminated: false
        ) == false,
        selector.selectedProcessIdentifier == 200 else {
            throw TestFailure(description: "Hushword replaced the external target")
        }
    }),
    ("locks the paste target for the duration of a recording", {
        var selector = TargetApplicationSelector(ownProcessIdentifier: 100)
        _ = selector.observe(
            processIdentifier: 200,
            isRegularApplication: true,
            isTerminated: false
        )
        selector.lockSelection()
        guard selector.observe(
            processIdentifier: 300,
            isRegularApplication: true,
            isTerminated: false
        ) == false,
        selector.selectedProcessIdentifier == 200 else {
            throw TestFailure(description: "recording target changed before paste completed")
        }

        selector.unlockSelection()
        guard selector.observe(
            processIdentifier: 300,
            isRegularApplication: true,
            isTerminated: false
        ),
        selector.selectedProcessIdentifier == 300 else {
            throw TestFailure(description: "paste target stayed locked after completion")
        }
    }),
    ("waits until the target application is active before pasting", {
        var state = PasteActivationState(maximumChecks: 3)
        guard state.next(targetIsActive: false) == .retry,
              state.next(targetIsActive: false) == .retry,
              state.next(targetIsActive: true) == .paste else {
            throw TestFailure(description: "paste was sent before the target became active")
        }
    }),
    ("gives up instead of pasting into the wrong application", {
        var state = PasteActivationState(maximumChecks: 2)
        guard state.next(targetIsActive: false) == .retry,
              state.next(targetIsActive: false) == .giveUp else {
            throw TestFailure(description: "paste retry policy did not stop safely")
        }
    }),
    ("never prompts for accessibility without an explicit user action", {
        guard AutomaticPastePermissionPolicy.shouldRequest(for: .automatic) == false,
              AutomaticPastePermissionPolicy.shouldRequest(for: .userInitiated) else {
            throw TestFailure(description: "accessibility could be prompted automatically")
        }
    }),
]
