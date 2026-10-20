import AppKit
import HushwordCore

@MainActor
final class FunctionKeyMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var state = FunctionKeyClickState()
    private var longPressTask: Task<Void, Never>?
    private let shortPressAction: () -> Void
    private let longPressAction: () -> Bool

    init(
        shortPressAction: @escaping () -> Void,
        longPressAction: @escaping () -> Bool
    ) {
        self.shortPressAction = shortPressAction
        self.longPressAction = longPressAction
        if !installEventTap() {
            installMonitors()
        }
    }

    deinit {
        longPressTask?.cancel()
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let eventTapRunLoopSource {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                eventTapRunLoopSource,
                .commonModes
            )
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }

    private func installEventTap() -> Bool {
        let eventMask = CGEventMask(1) << CGEventType.flagsChanged.rawValue
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<FunctionKeyMonitor>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                return monitor.handleEventTap(
                    proxy: proxy,
                    type: type,
                    event: event
                )
            },
            userInfo: context
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            eventTap,
            0
        )
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        self.eventTap = eventTap
        eventTapRunLoopSource = source
        return true
    }

    private func installMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .flagsChanged
        ) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .flagsChanged
        ) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    nonisolated private func handleEventTap(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Task { @MainActor [weak self] in
                guard let self else { return }
                longPressTask?.cancel()
                longPressTask = nil
                state.reset()
                if let eventTap {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                }
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags.intersection(.maskSecondaryFn)
        let functionPressed = flags.contains(.maskSecondaryFn)
        let otherFlags = event.flags.intersection([
            .maskShift,
            .maskControl,
            .maskAlternate,
            .maskCommand,
        ])
        let shouldConsume = otherFlags.isEmpty

        Task { @MainActor [weak self] in
            self?.handle(
                functionPressed: functionPressed,
                hasOtherModifiers: !otherFlags.isEmpty
            )
        }

        return shouldConsume ? nil : Unmanaged.passUnretained(event)
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let functionPressed = flags.contains(.function)
        let otherFlags = flags.subtracting(.function)
        handle(
            functionPressed: functionPressed,
            hasOtherModifiers: !otherFlags.isEmpty
        )
    }

    private func handle(
        functionPressed: Bool,
        hasOtherModifiers: Bool
    ) {
        let action = state.consume(
            functionPressed: functionPressed,
            hasOtherModifiers: hasOtherModifiers
        )
        switch action {
        case .startedPress:
            longPressTask?.cancel()
            longPressTask = Task { @MainActor [weak self] in
                try? await Task.sleep(
                    nanoseconds: AgentRewritePolicy
                        .longPressActivationNanoseconds
                )
                guard !Task.isCancelled, let self else { return }
                if state.consumeLongPress() == .longPress,
                   !longPressAction() {
                    state.cancelLongPress()
                }
                longPressTask = nil
            }
        case .shortPress:
            longPressTask?.cancel()
            longPressTask = nil
            shortPressAction()
        case .longPress, .none:
            if !functionPressed {
                longPressTask?.cancel()
                longPressTask = nil
            }
        }
    }
}
