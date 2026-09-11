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
///
/// ## Ownership semantics
///
/// `UIApplication.isIdleTimerDisabled` is process-global, so every
/// caller in the process shares one flag. The protocol is
/// **reference-counted** by contract: each `keepScreenAwake()` claim
/// must be paired with exactly one `allowScreenSleep()` release; the
/// underlying idle-timer flag only flips back to auto-locking once the
/// last outstanding claim is released. Individual conformances MAY be
/// per-instance (see `RecordingIdleTimerControl`), but the production
/// path routes through a shared coordinator so two live sessions or an
/// unrelated component all coexist safely.
@MainActor
public protocol IdleTimerControl: Sendable {
    /// Adds one claim requesting the screen stay on. Balanced by a
    /// matching `allowScreenSleep()`.
    func keepScreenAwake()
    /// Releases one claim previously made by `keepScreenAwake()`.
    /// Unmatched calls (release with no outstanding claim) are safe
    /// no-ops — they do NOT force the flag off underneath other
    /// claim-holders.
    func allowScreenSleep()
}

/// Process-shared reference counter that owns the actual
/// `UIApplication.isIdleTimerDisabled` mutation. Every production
/// `SystemIdleTimerControl` instance forwards to `.shared`, so
/// overlapping sessions — or a future unrelated component that wants
/// the screen awake — all coexist without stepping on each other.
///
/// Exposed for @testable use so tests can inspect the count without
/// touching `UIApplication`. Regular production code goes through
/// `SystemIdleTimerControl`.
@MainActor
public final class IdleTimerCoordinator {
    /// The one process-wide coordinator. Production
    /// `SystemIdleTimerControl` always talks to this instance.
    public static let shared = IdleTimerCoordinator()

    private var claimCount: Int = 0

    /// Test hook: current number of outstanding claims. `internal`-
    /// friendly (public because Swift's @testable requires public or
    /// internal, and we ship this in a library target). Read-only.
    public var currentClaimCount: Int { claimCount }

    internal init() {}

    /// Add one claim. First non-zero → disable the idle timer.
    public func retain() {
        claimCount += 1
        if claimCount == 1 { applyIdleTimerDisabled(true) }
    }

    /// Release one claim. Zero → re-enable the idle timer. Unmatched
    /// releases (already at zero) are safe no-ops.
    public func release() {
        guard claimCount > 0 else { return }
        claimCount -= 1
        if claimCount == 0 { applyIdleTimerDisabled(false) }
    }

    /// Test hook: reset to zero and re-enable auto-lock. Do NOT call
    /// from production code.
    internal func resetForTesting() {
        claimCount = 0
        applyIdleTimerDisabled(false)
    }

    private func applyIdleTimerDisabled(_ disabled: Bool) {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }
}

/// Production implementation: a per-instance handle that forwards to
/// `IdleTimerCoordinator.shared` for the actual reference counting.
///
/// Each `SystemIdleTimerControl` may hold at most ONE outstanding
/// claim of its own, so a second `keepScreenAwake()` on the same
/// instance without an intervening `allowScreenSleep()` is a no-op
/// (this matches the view-model's `.idle → .connected → .ended`
/// state transitions where at most one claim is live per session).
/// Different instances do NOT interfere — two active sessions each
/// hold their own claim, and only when BOTH release does the shared
/// coordinator drop back to auto-locking.
public final class SystemIdleTimerControl: IdleTimerControl {
    // Isolated to main actor via the protocol; the field is only ever
    // read/written from main-actor code, so plain storage is enough.
    private var hasOutstandingClaim: Bool = false

    public nonisolated init() {}

    @MainActor
    public func keepScreenAwake() {
        guard !hasOutstandingClaim else { return }
        hasOutstandingClaim = true
        IdleTimerCoordinator.shared.retain()
    }

    @MainActor
    public func allowScreenSleep() {
        guard hasOutstandingClaim else { return }
        hasOutstandingClaim = false
        IdleTimerCoordinator.shared.release()
    }
}

/// Test / preview implementation. Records the sequence of on/off calls
/// so tests can assert the view model toggles exactly once per session.
///
/// Its own per-instance semantics match `SystemIdleTimerControl`: a
/// second `keepScreenAwake()` on the same instance without an
/// intervening `allowScreenSleep()` is a no-op, and an unmatched
/// release is a no-op. Different instances don't interfere.
@MainActor
public final class RecordingIdleTimerControl: IdleTimerControl {
    public enum Event: Equatable, Sendable { case keepAwake, allowSleep }

    public private(set) var events: [Event] = []
    private var hasOutstandingClaim: Bool = false

    public nonisolated init() {}

    public func keepScreenAwake() {
        guard !hasOutstandingClaim else { return }
        hasOutstandingClaim = true
        events.append(.keepAwake)
    }

    public func allowScreenSleep() {
        guard hasOutstandingClaim else { return }
        hasOutstandingClaim = false
        events.append(.allowSleep)
    }

    /// True while this instance holds an outstanding claim.
    public var isCurrentlyKeepingAwake: Bool { hasOutstandingClaim }
}
