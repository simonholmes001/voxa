import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Abstracts the platform "keep the screen awake" affordance. During a
/// Talk session the app isn't receiving touch input, so after ~30 s of
/// no touches iOS dims the screen and puts the device to sleep — that
/// tears down the WebSocket and ends the session unexpectedly.
///
/// `TalkSessionViewModel` toggles this on when the session transitions
/// into `.connected` and off when the session tears down, so the app
/// never leaves the screen locked-open outside a live tutor session.
///
/// The protocol keeps the view model unit-testable on platforms and
/// hosts where `UIApplication` isn't available (macOS test host,
/// previews, offline tests).
@MainActor
public protocol IdleTimerControl: Sendable {
    /// Requests the screen stay on. Reference-counted at the platform
    /// level — nested calls are safe as long as they're paired.
    func keepScreenAwake()
    /// Undoes a prior `keepScreenAwake()` call. Idempotent — a second
    /// call while already off is a no-op.
    func allowScreenSleep()
}

/// Production implementation: sets `UIApplication.isIdleTimerDisabled`.
/// Idempotent: repeated `keepScreenAwake()` calls without an intervening
/// `allowScreenSleep()` don't stack, so the caller doesn't have to
/// balance them precisely — matches the view-model's toggle-on / toggle-
/// off pattern.
public struct SystemIdleTimerControl: IdleTimerControl {
    /// `nonisolated` init so the default value `SystemIdleTimerControl()`
    /// baked into `TalkSessionViewModel.init(...)` can be evaluated in the
    /// caller's actor context. The interesting work — reading /
    /// mutating `UIApplication.isIdleTimerDisabled` — is main-actor only
    /// via the protocol, so the type is still safe.
    public nonisolated init() {}

    @MainActor
    public func keepScreenAwake() {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = true
        #endif
    }

    @MainActor
    public func allowScreenSleep() {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = false
        #endif
    }
}

/// Test / preview implementation. Records the sequence of on/off calls
/// so tests can assert the view model toggles exactly once per session.
@MainActor
public final class RecordingIdleTimerControl: IdleTimerControl {
    public enum Event: Equatable, Sendable { case keepAwake, allowSleep }

    public private(set) var events: [Event] = []

    public nonisolated init() {}

    public func keepScreenAwake() { events.append(.keepAwake) }
    public func allowScreenSleep() { events.append(.allowSleep) }

    /// True if the last balanced call left the screen kept awake.
    public var isCurrentlyKeepingAwake: Bool {
        events.reduce(0) { count, event in
            count + (event == .keepAwake ? 1 : -1)
        } > 0
    }
}
